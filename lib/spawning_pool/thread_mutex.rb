class SpawningPool
  # Thread level mutex.
  # does not lock multiple concurrent fiber running from the same thread.
  class ThreadMutex

    def initialize
      @entered_thread = nil
      @entered_count = 0
      @mutex = Mutex.new
    end

    def synchronize(&block)
      if @entered_thread == Thread.current
        begin
          @entered_count += 1
          yield
        ensure
          @entered_count -= 1
          @entered_thread = nil if @entered_count == 0
        end
      else
        @mutex.synchronize do
          begin
            @entered_thread = Thread.current
            @entered_count += 1
            yield
          ensure
            @entered_count -= 1
            @entered_thread = nil if @entered_count == 0
          end
        end
      end

    end

  end
end
