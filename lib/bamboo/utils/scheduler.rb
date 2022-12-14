# frozen_string_literal: true

require 'fiber'
require 'io/nonblock'

class BambooSocket
  # Homebrew fiber scheduler
  class Scheduler
    MAXIMUM_TIMEOUT = 5000
    COLLECT_COUNTER_MAX = 16_384

    def initialize
      @readable = {}
      @writable = {}
      @waiting = {}
      @iovs = {}

      @lock = Mutex.new
      @blocking = 0
      @ready = []
      @collect_counter = 0

      init_selector
    end

    attr_reader :readable, :writable, :waiting

    def next_timeout
      _fiber, timeout = @waiting.min_by { |_key, value| value }

      if timeout
        offset = (timeout - current_time) * 1000 # Use mililisecond
        return 0 if offset.negative?
        return offset if offset < MAXIMUM_TIMEOUT
      end

      MAXIMUM_TIMEOUT
    end

    def run
      while @readable.any? || @writable.any? || @waiting.any? || @iovs.any? || @blocking.positive?
        readable, writable, iovs = wait

        readable&.each do |io|
          fiber = @readable.delete(io)
          fiber.resume if fiber&.alive?
        end

        writable&.each do |io|
          fiber = @writable.delete(io)
          fiber.resume if fiber&.alive?
        end

        unless iovs.nil?
          iovs&.each do |v|
            io, ret = v
            fiber = @iovs.delete(io)
            fiber.resume(ret) if fiber&.alive?
          end
        end

        collect

        if @waiting.any?
          time = current_time
          waiting = @waiting
          @waiting = {}

          waiting.each do |fiber, timeout|
            if timeout <= time && fiber.is_a?(Fiber) && fiber.alive?
              fiber.resume
            elsif timeout > time
              @waiting[fiber] = timeout
            end
          end
        end

        next unless @ready.any?

        ready = nil

        @lock.synchronize do
          ready = @ready
          @ready = []
        end

        ready.each do |fiber|
          fiber.resume if fiber.is_a?(Fiber) && fiber.alive?
        end
      end
    end

    def current_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Wait for the given file descriptor to match the specified events within
    # the specified timeout.
    # @parameter event [Integer] A bit mask of `IO::READABLE`,
    #   `IO::WRITABLE` and `IO::PRIORITY`.
    # @parameter timeout [Numeric] The amount of time to wait for the event in seconds.
    # @returns [Integer] The subset of events that are ready.
    def io_wait(io, events, _duration)
      @readable[io] = Fiber.current unless (events & IO::READABLE).zero?
      @writable[io] = Fiber.current unless (events & IO::WRITABLE).zero?
      register(io, events)
      Fiber.yield
      deregister(io)

      events
    end

    # Sleep the current task for the specified duration, or forever if not
    # specified.
    # @param duration [Numeric] The amount of time to sleep in seconds.
    def kernel_sleep(duration = nil)
      block(:sleep, duration)
    end

    # Block the calling fiber.
    # @parameter blocker [Object] What we are waiting on, informational only.
    # @parameter timeout [Numeric | Nil] The amount of time to wait for in seconds.
    # @returns [Boolean] Whether the blocking operation was successful or not.
    def block(_blocker, timeout = nil)
      if timeout
        @waiting[Fiber.current] = current_time + timeout
        begin
          Fiber.yield
        ensure
          @waiting.delete(Fiber.current)
        end
      else
        @blocking += 1
        begin
          Fiber.yield
        ensure
          @blocking -= 1
        end
      end
    end

    # Unblock the specified fiber.
    # @parameter blocker [Object] What we are waiting on, informational only.
    # @parameter fiber [Fiber] The fiber to unblock.
    # @reentrant Thread safe.
    def unblock(_blocker, fiber)
      @lock.synchronize do
        @ready << fiber
      end
    end

    # Invoked when the thread exits.
    def close
      run
    end

    # Collect closed streams in readables and writables
    def collect(opts = { force: false })
      if (@collect_counter < COLLECT_COUNTER_MAX) && !opts[:force]
        @collect_counter += 1
        return
      end

      @collect_counter = 0

      [@readable, @writable, @iovs].each do |io_type|
        io_type.each_key do |io|
          @readable.delete(io) if io.closed?
        end
      end
    end

    # Intercept the creation of a non-blocking fiber.
    # @returns [Fiber]
    def fiber(&block)
      fiber = Fiber.new(blocking: false, &block)
      fiber.resume
      fiber
    end

    def init_selector
      # Select is stateless
    end

    def register(io, interest)
      # Select is stateless
    end

    def deregister(io); end

    def wait
      IO.select(@readable.keys, @writable.keys, [], next_timeout / 1000)
    rescue IOError
      collect(force: true)
      [[], []]
    rescue Errno::EBADF
      collect(force: true)
      [[], []]
    end
  end
end
