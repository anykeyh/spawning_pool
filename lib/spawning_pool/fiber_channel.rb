class SpawningPool
  class FiberChannel
    class ClosedError < RuntimeError; end

    def initialize(capacity: 0)
      @messages = []
      @pushers = Queue.new
      @receivers = Queue.new
      @capacity = capacity
      @closed = false

      # for multithreading purpose
      @receiver_mutex = ThreadMutex.new
      @pusher_mutex = ThreadMutex.new
    end

    def wakeup(fiber_pool)
      return if fiber_pool.empty?

      fiber = fiber_pool.pop

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

      pushers = @pushers
      @pushers = []

      receivers = @receivers
      @receivers = []

      [pushers, receivers].each do |arr|
        until arr.empty?
          fiber = arr.pop
          Scheduler.for(fiber).raise(fiber, ClosedError)
        end
      end
    end

    def push(message)
      puts "#{Thread.current.name} > push #{message}"
      @pusher_mutex.synchronize do
        puts "#{Thread.current.name} > got push lock"

        raise ClosedError if closed?

        # There is case where the fiber can resume but the message queue is
        # still full due to scheduler waking up twice.
        wait_as @pushers while full?

        @messages << message
      end

      puts "#{Thread.current.name} > push done. Wake up receivers"

      wakeup @receivers

      puts "#{Thread.current.name} > push all done."

      self
    end

    def receive
      puts "#{Thread.current.name} > rcv"
      msg = @receiver_mutex.synchronize do
        puts "#{Thread.current.name} > acquired rcv lock"
        while empty?
          raise ClosedError if closed?
          wait_as @receivers
        end

        @messages.shift
      end

      puts "#{Thread.current.name} > rcv done"

      wakeup @pushers

      puts "#{Thread.current.name} > wakeup pushers done"

      msg
    end

    alias << push
  end
end
