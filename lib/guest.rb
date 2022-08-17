# frozen_string_literal: true

require_relative 'handshake'
require_relative 'utils/logging'
require_relative 'utils/constants'
require_relative 'bamboo_frame/bamboo_frame'

class BambooSocket
  # Websocket guest.
  # Should keep the socket as a property,
  # should be able to perform handshakes,
  # and should be able to read from and write to the socket.
  class Guest
    include BambooSocket::Logging
    attr_accessor :socket, :frame_queue, :id

    # Initialize message queue and perform a handshake
    def initialize(socket, callbacks, opts)
      self.socket = socket
      self.frame_queue = []
      init_buffer
      @callbacks = callbacks
      @opts = opts
      @unloading = false
    end

    # Queue the message that is sent to this guest
    # TODO: There should be another Fiber handling the queue unloading
    def send_message(payload = '', type: :text)
      frame_queue << contruct_outgoing_frames(payload, type)
      Fiber.schedule { unload_queue unless @unloading }
    end

    # Listen for new frames
    def listen
      loop do
        logger.debug 'Listening for new frames.'
        ready = socket.wait 5
        raise SocketTimeout, "No incomming messages in #{@opts[:max_timeout]} seconds, socket dead" unless ready

        incomming = BambooFrame::Incomming.new(socket).receive
        @callbacks[:frame]&.call(self, incomming, type: incomming.type)
        # TODO: The handling can be asynchronous to ensure
        # that the internet bandwidth is fully used when receiving lengthy messages
        handle incomming
      end
    rescue SocketClosed
      socket.close
    end

    private

    ################# Ping & Pong #################

    def handle(incomming)
      pong if incomming.ping?
      signal_close if incomming.close?

      @buffer_size += incomming.payload_size
      @buffer << incomming if @buffer_size <= BambooSocket::MAX_BUFFER_SIZE
      return unless incomming.fin? # Always run message callback when a fin frame is reached

      @callbacks[:message]&.call(self, @buffer.map(&:payload).join, type: incomming.type)
      init_buffer
    end

    def pong
      send_message(type: :pong)
    end

    #################### Close ####################

    def signal_close
      logger.warn { 'Closing socket with a close frame' }
      PandaFrame::Outgoing.new(opcode: 0x08).send_frame(socket)
    rescue Errno::EPIPE
      logger.warn { 'Broken pipe, no close frames sent' }
    rescue IOError
      logger.warn { 'Socket already closed, no close frames sent' }
    ensure
      raise SocketClosed
    end

    ################ Message Queue #################

    def unload_queue
      @unloading = true
      fin = true
      frame_queue.lazy.each do |frames|
        while (frame = frames.shift)
          frame.send_frame(self)
          fin = frame.fin?
        end
        break unless fin # If the frames does not finish, break and wait for another frame being inserted
      end
      @unloading = false
    end

    #################### Buffer ######################

    def init_buffer
      @buffer = []
      @buffer_size = 0
    end

    ############# Outgoing messages ##################

    # Split large payload into continuation frames
    def contruct_outgoing_frames(payload, type)
      size = payload.size
      opcode = BambooSocket::OPCODES[type]
      step = BambooSocket::MAX_FRAME_SIZE
      return [BambooFrame::Outgoing.new(payload:, opcode:)] if size <= step

      frames = []
      index = 0
      while index - 1 <= size
        next_index = index + step - 1
        opcode = 0x00 if index.positive?
        fin = next_index >= size ? 0x01 : 0x00
        frames << BambooFrame::Outgoing.new(payload: payload[index..next_index], opcode:, fin:)
        index = next_index + 1
      end
      frames
    end
  end
end
