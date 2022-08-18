# frozen_string_literal: true

require_relative '../utils/logging'
require_relative '../utils/exeption'
require_relative '../utils/constants'

# General namespace for WebSocket frames
module BambooFrame
  # General methods
  class Common
    include BambooSocket::Logging
    attr_accessor :payload, :initial_size, :payload_size, :is_masked, :mask, :opcode, :fin

    def initialize; end

    # Prepare frame for sending
    # Applies to both frame forwarding and frame generation
    def frame_data
      data = [(fin << 7) + opcode].pack('C')
      data << pack_size
      data << payload
    end

    # Pack size number into binary before sending
    def pack_size
      if payload_size > 2**16 - 1
        [127, payload_size].pack('CQ>')
      elsif payload_size > 125
        [126, payload_size].pack('CS>')
      else
        [payload_size].pack('C')
      end
    end

    def send_frame(guest)
      guest.socket.write frame_data
      logger.info "Sent #{type} frame"
    end

    ############### Frame ###############

    def fin?
      @fin == 0x01
    end

    BambooSocket::OPCODES.each_key do |name|
      define_method("#{name}?") do
        opcode == BambooSocket::OPCODES[name]
      end
    end

    def type
      return :continuation if continuation?
      return :text if text?
      return :binary if binary?
      return :close if close?
      return :ping if ping?
    end
  end
end
