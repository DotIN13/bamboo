# frozen_string_literal: true

require_relative 'common'

module BambooFrame
  # Outgoing frames
  class Outgoing < Common
    def initialize(payload: '', fin: 1, opcode: 1)
      super()
      self.payload = payload
      self.opcode = opcode
      self.fin = fin
      self.payload_size = payload.bytesize
    end
  end
end
