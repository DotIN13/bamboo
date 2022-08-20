# frozen_string_literal: true

require 'set'
require_relative '../lib/bamboo'

server = BambooSocket::Server.new
server.on(:add) do |_guest|
  puts 'New guest connected'
end
server.on(:message) do |guest, msg, type|
  guest.send_message('PONG') if type == :text && msg == 'PING'
  server.guest_list.each { |g| g.send_message(msg) if g != guest } if type == :text
end
server.on(:remove) do |_guest|
  puts 'Guest disconnected'
end
server.start
