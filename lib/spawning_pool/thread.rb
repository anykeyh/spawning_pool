class SpawningPool
  class Thread < ::Thread

    def initialize(pool, &block)
      super do
        scheduler = SpawningPool::Scheduler.new(pool)
        Fiber.set_scheduler scheduler
        scheduler.fiber(&block)
        scheduler.run
      end
    end

  end
end
