require "benchmark"
require "tempfile"
require_relative "../../lib/spawning_pool"

THREAD_COUNTS = 8
REPEAT = 1_500
CAPACITY = 10

def perform(value)
  file = Tempfile.new("foo#{value}")
  begin
    # push enough bytes to take advantage of buffer sync
    file << (' ' * value * 2048).to_s
    file.flush
    file.rewind
    file.read
  ensure
    file.close
    file.unlink   # deletes the temp file
  end
end

def nude_test
  REPEAT.times { |x| perform(x) }
end

def fiber_test
  SpawningPool do
    channel = pool.channel(capacity: CAPACITY)

    pool.spawn do
      REPEAT.times { |x| channel << x }
      channel.close
    end

    pool.spawn(channel, workers: THREAD_COUNTS) do |v|
      perform(v)
    end
  end
end

def thread_test
  channel = SpawningPool.channel(capacity: CAPACITY)

  t1 = Thread.new do
    REPEAT.times { |x| channel << x }
    channel.close
  end

  THREAD_COUNTS.times.map do
    Thread.new do
      loop do
        v = channel.receive
        perform(v)
      rescue SpawningPool::ClosedChannelError
        break
      end
    end
  end.map(&:join)
end

def pusher_external
  channel = SpawningPool.channel(capacity: CAPACITY)

  t1 = Thread.new do
    REPEAT.times { |x| channel << x }
    channel.close
  end

  SpawningPool do
    pool.spawn(channel, workers: THREAD_COUNTS) do |v|
      perform(v)
    end
  end

  t1.join
end

def puller_external
  channel = SpawningPool.channel(capacity: CAPACITY)

  SpawningPool(deamon: true) do
    pool.spawn do
      REPEAT.times { |x| channel << x }
      channel.close
    end
  end

  THREAD_COUNTS.times.map do
    Thread.new do
      loop do
        v = channel.receive
        perform(v)
      rescue SpawningPool::ClosedChannelError
        break
      end
    end
  end.map(&:join)
end

Benchmark.bm do |x|
  x.report("Mono thread no fiber") { nude_test }
  x.report("Between fibers") { fiber_test }
  x.report("Pusher external") { pusher_external }
  x.report("Puller external") { puller_external }
  x.report("Thread only") { thread_test }
end