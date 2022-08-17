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
      self.frame_queue = []
      self.socket = socket
      BambooSocket::Handshake.new(socket)
      init_buffer
      @callbacks = callbacks
      @opts = opts
      @unloading = false
    end

    # Queue the message that is sent to this guest
    # TODO: There should be another Fiber handling the queue unloading
    def send_message(payload = '', type: :text)
      frames = []
      frames << BambooFrame::Outgoing.new(payload:, opcode: BambooSocket::OPCODES[type])
      # TODO: if the message size is too large, split and queue
      frame_queue << frames
      unload_queue unless @unloading
    end

    # Listen for new frames
    def listen
      loop do
        logger.debug 'Listening for new frames.'
        ready = socket.wait 5
        raise SocketTimeout, "No incomming messages in #{@opts[:max_timeout]} seconds, socket dead" if ready.nil?

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

    ################# Close #################

    def signal_close
      logger.warn { 'Closing socket with closing frame' }
      PandaFrame::Outgoing.new(opcode: 0x08).send_frame(socket)
    rescue Errno::EPIPE
      logger.warn { 'Broken pipe, no closing frames sent' }
    rescue IOError
      logger.warn { 'Closed stream, no closing frames sent' }
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

    ################## Buffer #####################

    def init_buffer
      @buffer = []
      @buffer_size = 0
    end
  end
end
