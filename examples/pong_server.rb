# frozen_string_literal: true

require_relative '../lib/bamboo_socket'

server = BambooSocket::Server.new
server.on(:message) do |guest, _msg, _type|
  guest.send_message('PONG')
end
server.start
