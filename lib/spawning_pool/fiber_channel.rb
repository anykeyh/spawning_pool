class SpawningPool
  class FiberChannel

    def initialize(capacity: 0)
      @messages   = []
      @pushers    = []
      @receivers  = []

      @capacity = capacity

      @thread = Thread.current
      @scheduler = Fiber.scheduler

      if @scheduler.nil?
        raise "This is mono-thread only. use SpawningPool.channel(multithread: true) outside of SpawningPool block"
      end

      @closed = false
    end

    def empty?
      @messages.empty?
    end

    def closed?
      @closed
    end

    def close
      ensure_mono_thread!

      @closed = true

      flush

      pushers = @pushers
      @pushers = []

      receivers = @receivers
      @receivers = []

      [pushers, receivers].each do |arr|
        until arr.empty?
          # cancel pusher
          fiber = arr.pop
          @scheduler.raise(fiber, ClosedChannelError)
        end
      end

    end

    def push(message)
      ensure_mono_thread!

      raise ClosedChannelError if closed?

      # There is case where the fiber can resume but the message queue is
      # still full due to scheduler waking up twice.
      wait_as @pushers while full?

      @messages << message

      wakeup @receivers

      self
    end

    def receive
      ensure_mono_thread!

      while empty?
        raise ClosedChannelError if closed?
        wait_as @receivers
      end

      msg = @messages.shift

      wakeup @pushers

      msg
    end

    alias << push

    def full?
      @capacity != 0 && @messages.size == @capacity
    end

    protected

    def wakeup(fiber_pool)
      return if fiber_pool.empty?

      fiber = fiber_pool.shift

      @scheduler.unblock(nil, fiber)
    end

    def wait_as(fiber_pool)
      fiber_pool << Fiber.current
      @scheduler.block
    end

    def flush
      @scheduler.yield until empty?
      self
    end

    def ensure_mono_thread!
      if Thread.current != @thread
        raise "You can't use this channel from another thread."
      end
    end

  end
end
