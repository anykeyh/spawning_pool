require 'timeout'

class SpawningPool
  class Channel
    class ClosedError < RuntimeError; end

    def initialize(capacity: 0)
      @messages   = Queue.new
      @capacity   = capacity
      @closed     = false

      @push_mutex = Mutex.new
      @push_cv = ConditionVariable.new

      @rcv_mutex = Mutex.new
      @rcv_cv = ConditionVariable.new

      @empty_mutex = Mutex.new
      @empty_cv = ConditionVariable.new

      @fibers = {}
    end

    def push(message)
      raise ClosedError if closed?

      target = Fiber.scheduler ? Fiber.current : Thread.current

      begin
        @fibers[target] = true

        @push_mutex.synchronize do
          while full?
            @rcv_cv.signal
            @push_cv.wait(@push_mutex)
          end

          raise ClosedError if closed?

          @messages << message
          @rcv_cv.signal

          self
        end
      ensure
        @fibers.delete(target)
      end

    end

    def receive
      raise ClosedError if closed? && empty?

      target = Fiber.scheduler ? Fiber.current : Thread.current

      begin
        @fibers[target] = true

        @rcv_mutex.synchronize do
          begin
            while empty?
              raise ClosedError if closed?

              @push_cv.signal
              @rcv_cv.wait(@rcv_mutex)
            end

            msg = @messages.pop(true)

            @push_cv.signal

            msg
          rescue ThreadError # someone took the message before
            raise ClosedError if closed?
            retry # we wait again !
          end
        end
      ensure
        @fibers.delete(target)
      end
    end

    def close(now = false)
      @closed = true

      @push_cv.broadcast
      @rcv_cv.broadcast

      unless now
        # flush the existing messages...
        @empty_mutex.synchronize do
          until @messages.empty?
            @empty_cv.wait(@empty_mutex)
          end
        end
      end

      @fibers.each do |key, _|
        if key.is_a?(Thread)
          key&.raise(ClosedError)
        else
          fiber = Scheduler.for(key)
          fiber&.raise(key, ClosedError)
        end
      end
    end

    def full?
      @capacity != 0 && @messages.size == @capacity
    end

    def empty?
      @empty_mutex.synchronize do
        empty = @messages.empty?
        empty && @empty_cv.signal
        empty
      end
    end

    def closed?
      @closed
    end

    alias << push
  end
end
