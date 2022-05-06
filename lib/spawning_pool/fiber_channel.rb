class SpawningPool
  class FiberChannel
    class ClosedError < RuntimeError; end

    def initialize(capacity: 0)
      @messages = Queue.new
      @pushers = Queue.new
      @receivers = Queue.new
      @capacity = capacity
      @closed = false

      # for multithreading purpose
      @receiver_mutex = ThreadMutex.new
      @pusher_mutex = ThreadMutex.new
    end

    def wakeup(fiber_pool)
      fiber = fiber_pool.pop(true) rescue return

      Scheduler.for(fiber).unblock(nil, fiber)
    end

    def wait_as(fiber_pool)
      fiber_pool << Fiber.current

      Fiber.scheduler.block
    end

    # Wait for the channel to be empty before we resume the fiber.
    def flush
      until empty?
        Fiber.scheduler.yield
      end
      self
    end

    def full?
      @capacity != 0 && @messages.size == @capacity
    end

    def empty?
      @messages.empty?
    end

    def closed?
      @closed
    end

    def close
      @closed = true

      flush

      @pushers.close
      @receivers.close

      [@pushers, @receivers].each do |arr|
        loop do
          fiber = arr.pop(true)
          Scheduler.for(fiber).raise(fiber, ClosedError)
        rescue ThreadError
          break
        end
      end
    end

    def push(message)
      raise ClosedError if closed?

      # There is case where the fiber can resume but the message queue is
      # still full due to scheduler waking up twice.
      wait_as @pushers while full?

      @messages << message

      wakeup @receivers

      self
    end

    def receive
      while empty?
        raise ClosedError if closed?
        wait_as @receivers
      end

      msg = @messages.shift

      wakeup @pushers

      msg
    end

    alias << push
  end
end
