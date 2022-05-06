class SpawningPool
  class ThreadChannel
    class ClosedError < RuntimeError; end

    def initialize(capacity: 1)
      @capacity = capacity
      @r, @w = IO.pipe
      @messages = []
    end

    def full?
      @messages.size >= @capacity
    end

    def empty?
      @messages.empty?
    end

    def close
      @messages.close
    end

    def push(message)
      @messages << message
      @w.write("\0")
      self
    end

    def receive
      @r.read(1)
      @messages.shift
    end

    alias << push
  end
end
