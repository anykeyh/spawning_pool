require "fiber"
require "event"
require "timers"

class SpawningPool
  # This is ported from the awesome Async project.
  class Scheduler

    class << self
      def fiber_map
        @fiber_map ||= {}
      end

      def scheduler_map
        @scheduler_map ||= {}
      end

      def for(fiber)
        @scheduler_map[@fiber_map[fiber]]
      end
    end

    attr_reader :thread, :loop, :spawning_pool

    def initialize(spawning_pool)
      @loop = Fiber.current
      @selector = ::SpawningPool::Selector.new(Fiber.current)

      @thread = Thread.current

      @blocked = 0
      @timers = ::Timers::Group.new

      @spawning_pool = spawning_pool
      @spawned_count = 0
    end

    def yield
      @selector.yield
    end

    def timeout(timeout)
      fiber = Fiber.current

      timer = @timers.after(timeout) do
        fiber.raise(Timeout::Error)
      end

      yield
    ensure
      timer&.cancel
    end

    def raise(fiber, *arguments)
      @selector.raise(fiber, *arguments)
      @selector.continue if Thread.current != @thread
    end

    def block(_blocker = nil, timeout = nil)
      fiber = Fiber.current

      if timeout
        timer = @timers.after(timeout) do
          fiber.transfer # if fiber.alive?
        end
      end

      begin
        @blocked += 1
        @selector.transfer
      ensure
        @blocked -= 1
      end
    ensure
      timer&.cancel
    end

    def close
      @selector.close
    end

    def fiber
      @spawned_count += 1
      f = Fiber.new(blocking: false) do
        Scheduler.fiber_map[Fiber.current] = Thread.current
        yield
      ensure
        Scheduler.fiber_map.delete(Fiber.current)
        @spawned_count -= 1
      end
      @selector.resume(f)
    end

    def io_wait(io, events, timeout = nil)
      fiber = Fiber.current

      if timeout
        timer = @timers.after(timeout) do
          fiber.raise(Timeout::Error)
        end
      end

      @selector.io_wait(fiber, io, events)
    rescue TimeoutError
      false
    rescue TypeError
      # TODO: This error happens whenever we timeout a fiber
      #       It doesn't seems to cause any harm whatsoever for now.
      false
    ensure
      timer&.cancel
    end

    def kernel_sleep(duration = nil)
      if duration
        block(nil, duration)
      else
        @selector.transfer
      end
    end

    def process_wait(pid, flags)
      @selector.process_wait(Fiber.current, pid, flags)
    end

    def unblock(_blocker, fiber)
      @selector.push(fiber)
      @selector.continue if Thread.current != @thread
    end

    def get_tvar(symbol)
      Thread.current.thread_variable_get(symbol)
    end

    def set_tvar(symbol, value)
      Thread.current.thread_variable_set(symbol, value)
    end

    # Run one iteration of the event loop.
    # @parameter timeout [Float | Nil] The maximum timeout, or if nil, indefinite.
    # @returns [Boolean] Whether there is more work to do.
    def run_once(duration = nil)
      return false if @spawned_count.zero?

      # if there is timer, we wait for them. If not we run on timeout
      interval = @timers.wait_interval || duration

      begin
        if interval
          interval = 0 if interval < 0
          @selector.select(interval)
        else
          @selector.select(nil)
        end
      rescue Errno::EINTR
      end

      @timers.fire

      # The reactor still has work to do:
      true
    end

    def run
      Thread.handle_interrupt(Interrupt => :never) do
        Kernel.raise "Running scheduler on non-blocking fiber!" unless Fiber.blocking?

        self.class.scheduler_map[Thread.current] = self

        while self.run_once
          break if Thread.pending_interrupt?
        end
      ensure
        self.class.scheduler_map.delete(Thread.current)
      end
    end

  end
end
