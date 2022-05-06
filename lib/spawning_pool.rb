# frozen_string_literal: true

require_relative "spawning_pool/version"

require_relative "spawning_pool/thread_mutex"

require_relative "spawning_pool/selector"
require_relative "spawning_pool/scheduler"
require_relative "spawning_pool/channel"
require_relative "spawning_pool/thread"

class SpawningPool
  attr_reader :threads

  def initialize(join, &block)
    if Fiber.scheduler
      raise "Error: This thread is already managed by scheduler. Don't use SpawningPool into another SpawningPool."
    end

    @spawned_threads = []

    Thread.current.name = "SpawningPool"

    @thread_id = 0
    t = spawn_thread(&block)
    t.join if join
    @spawned_threads.each(&:join)
    t
  end

  def spawn_thread(name = nil, &block)
    t = SpawningPool::Thread.new(self, &block)
    @spawned_threads << t

    t.name = name || "spawning_pool #{(@thread_id += 1)}"
    t
  end

  def spawn(channel = nil, workers: 1, &block)
    if channel.nil?
      Fiber.scheduler.fiber(&block)
    else
      workers.times do
        Fiber.scheduler.fiber do
          loop do
            yield channel.receive
          rescue SpawningPool::Channel::ClosedError
            break
          end
        end
      end
    end
  end

  def self.channel(capacity: 0)
    SpawningPool::Channel.new(capacity: capacity)
  end

  def channel(capacity: 0)
    self.class.channel(capacity: capacity)
  end

  def timeout(time, &block)
    Fiber.scheduler.timeout(time, &block)
  end

  def self.current
    Fiber.scheduler.spawning_pool
  end
end

def SpawningPool(join = true, &block)
  SpawningPool.new(join, &block)
end

def pool
  Fiber.scheduler.spawning_pool
end
