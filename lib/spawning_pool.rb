# frozen_string_literal: true

require_relative "spawning_pool/version"

require_relative "spawning_pool/thread_mutex"

require_relative "spawning_pool/closed_channel_error"

require_relative "spawning_pool/fiber_channel"
require_relative "spawning_pool/multithread_channel"

require_relative "spawning_pool/selector"
require_relative "spawning_pool/scheduler"
require_relative "spawning_pool/thread"

class SpawningPool

  def initialize(deamon, &block)
    if Fiber.scheduler
      raise "Error: This thread is already managed by scheduler. Don't use SpawningPool into another SpawningPool."
    end

    t = SpawningPool::Thread.new(self, &block)
    Thread.current.name = "SpawningPool"
    t.join unless deamon
    t
  end

  def spawn(channel = nil, workers: 0, &block)
    if channel.nil?
      Fiber.scheduler.fiber(&block)
    else
      if workers <= 0
        Fiber.scheduler.fiber do
          loop do
            content = channel.receive

            Fiber.scheduler.fiber do
              yield content
            end
          rescue SpawningPool::ClosedChannelError
            break
          end
        end
      else
        workers.times do
          Fiber.scheduler.fiber do
            loop do
              yield channel.receive
            rescue SpawningPool::ClosedChannelError
              break
            end
          end
        end
      end
    end
  end

  def self.channel(capacity: 0, multithread: false)
    if multithread
      MultithreadChannel.new(capacity: capacity)
    else
      FiberChannel.new(capacity: capacity)
    end
  end

  def channel(capacity: 0, multithread: false)
    self.class.channel(capacity: capacity, multithread: multithread)
  end

  def timeout(time, &block)
    Fiber.scheduler.timeout(time, &block)
  end

  def self.timeout(time, &block)
    Fiber.scheduler.timeout(time, &block)
  end

  def self.current
    Fiber.scheduler.spawning_pool
  end
end

def SpawningPool(deamon: false, &block)
  SpawningPool.new(deamon, &block)
end

def pool
  Fiber.scheduler.spawning_pool
end
