# frozen_string_literal: true

class BambooSocket
  LOG = 'bamboo.log'
  # When receiving payload, read FRAGMENT size each time
  FRAGMENT = 4096
  ORIGINS = %w[https://localhost:4000].freeze
  OPCODES = {
    text: 0x01,
    binary: 0x02,
    ping: 0x09,
    close: 0x08,
    continuation: 0x00
  }.freeze
  MAX_BUFFER_SIZE = 1_000_000
  Headers = Struct.new('Headers', :http_method, :http_version, :origin, :upgrade, :connection,
                       :"sec-websocket-key", :"sec-websocket-version")
end
