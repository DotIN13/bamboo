# frozen_string_literal: true

require 'xorcist'
require_relative 'common'
require_relative '../utils/constants'

module BambooFrame
  # The incomming frames
  class Incomming < Common
    attr_accessor :socket

    def initialize(socket)
      super()
      self.socket = socket
    end

    # Incoming frames
    def receive
      parse_info
      parse_size
      parse_mask
      parse_payload
      self
    end

    def parse_info
      first = socket.getbyte
      raise FrameError, 'Received nil when reading, the socket might have already been closed' if first.nil?

      self.fin = first[7]
      self.opcode = first[0..3]
      raise FrameError, 'Opcode unsupported' unless [0x00, 0x01, 0x02, 0x08].include? opcode
    end

    # Read the next byte containing mask option and initial payload length
    def parse_size
      second = socket.getbyte
      self.is_masked = second & 0b10000000
      # Handle extended payload length
      self.initial_size = second & 0b01111111
      self.payload_size = initial_size > 125 ? measure_payload : initial_size
      logger.debug "Receiving #{type} frame: opcode #{opcode}, fin #{fin}, size #{payload_size}"
    end

    # Determine payload size based on initial_size
    def measure_payload
      raise FrameError, 'Unexpected payload size' if initial_size > 127

      return socket.read(2).unpack1('S>') if initial_size == 126
      return socket.read(8).unpack1('Q>') if initial_size == 127
    end

    # Read four bytes if the incomming frame is masked
    def parse_mask
      return unless is_masked

      @mask = socket.read(4)
    end

    def parse_payload
      self.payload = socket.read(payload_size)
      xor(payload) if is_masked
    end

    # Xor the incomming frame
    def xor(raw)
      size = raw.bytesize
      padding_size = 4 - size % 4
      raw << 0.chr * padding_size
      full_size = size + padding_size
      Xorcist.xor!(raw, mask * (full_size / 4))
      self.payload = raw[..size - 1]
    end
  end
end
