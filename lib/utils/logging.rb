# frozen_string_literal: true

require 'logger'
require 'English'
require_relative 'constants'

class BambooSocket
  # Handle IO output to multiple destinations
  class MultiIO
    def initialize(*targets)
      @targets = targets
    end

    def write(*args)
      @targets.each { |t| t.write(*args) }
    end

    def close
      @targets.each(&:close)
    end
  end

  # Logging utilities, implemented as a global standalone module
  module Logging
    def logger
      BambooSocket::Logging.logger
    end

    def production?
      BambooSocket::Logging.production?
    end

    def log_memory
      BambooSocket::Logging.logger.debug format('%.1fMB used', `ps -o rss= -p #{$PID}`.to_f / 1024)
    end

    class << self
      def logger
        @logger ||= new_logger
      end

      def new_logger
        logdev = production? ? $stderr : BambooSocket::MultiIO.new($stderr, File.open('./bamboo.log', 'w'))
        level = production? ? Logger::WARN : Logger::DEBUG
        @logger = Logger.new logdev, progname: 'Bamboo Socket', level:
      end

      # Default to development
      def production?
        ENV['BAMBOO_ENV'] == 'production'
      end
    end
  end
end
