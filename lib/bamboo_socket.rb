# frozen_string_literal: true

require 'socket'
require 'set'
require 'fiber'
require_relative 'utils/scheduler'
require_relative 'guest'

# Bamboo socket
class BambooSocket
  # Websocket server
  class Server
    include BambooSocket::Logging
    attr_accessor :greeter, :worker, :guest_list

    def initialize(guest_opts = {})
      trap_int
      @scheduler = BambooSocket::Scheduler
      @guest_opts = { max_timeout: 60 }.merge(guest_opts)
      @tcp_server = TCPServer.new 5613
      @callbacks = {}
      @current_id = 0
      @waiting_list = Thread::Queue.new
      @guest_list = Set.new
    end

    # Allow callbacks to be provided during the creation,
    # or even the excecution of the websocket server
    def on(event_type, &block)
      raise ArgumentError unless %i[add message frame remove].include?(event_type)

      @callbacks[event_type] = block
    end

    # WIP: Should close socket if not ws connection
    def start
      logger.info 'Bamboo Server is running.'
      init_greeter
      init_worker
      # [greeter, worker].each(&:join)
      greeter.join
    end

    private

    # Initialize the greeter thread
    # The greeter takes care of the handshakes with the clients
    def init_greeter
      self.greeter = Thread.new do
        Fiber.set_scheduler(@scheduler.new)
        Fiber.schedule do
          loop do
            socket = @tcp_server.accept

            Fiber.schedule { @waiting_list << BambooSocket::Guest.new(socket, @callbacks, @guest_opts) }
          end
        end
      end
    end

    # Initialize the worker thread
    # It is quite interesting that callbacks defined with Server::on are also run by this thread
    # TODO: Create a few worker threads, and take guests from the waiting list based on their index
    def init_worker
      self.worker = Thread.new do
        Fiber.set_scheduler(@scheduler.new)
        Fiber.schedule do
          loop do
            logger.debug 'Waiting for new guests.'
            guest = @waiting_list.shift

            new_guest(guest)
          end
        end
      end
    end

    def new_guest(guest)
      guest_list << guest
      guest.id = @current_id # Give each guest a unique id
      @current_id += 1
      @callbacks[:add]&.call(guest)
      Fiber.schedule do
        guest.listen
        guest_list.delete(guest)
        @callbacks[:remove]&.call(guest)
      end
    end

    # Exit all threads when receiving SIGINT
    def trap_int
      trap 'SIGINT' do
        warn 'Bamboo Server shutting down...'
        [greeter, worker].each(&:exit)
        exit 130
      end
    end
  end
end
