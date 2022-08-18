# frozen_string_literal: true

require_relative 'logging'

# Error handling
class BambooSocketError < StandardError
  include BambooSocket::Logging

  def initialize(msg)
    logger.error msg.to_s
    super msg
  end
end

class FrameError < BambooSocketError
end

class HandshakeError < BambooSocketError
end

# Socket timeout
class SocketTimeout < BambooSocketError
end

# Socket close
class SocketClosed < StandardError
end
