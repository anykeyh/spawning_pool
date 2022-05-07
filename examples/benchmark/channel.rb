require "benchmark"
require "tempfile"
require_relative "../../lib/spawning_pool"

THREAD_COUNTS = 5
REPEAT = 1500
CAPACITY = 32

def perform(value)
  file = Tempfile.new("foo#{value}")
  begin
    # push enough bytes to take advantage of buffer sync

    (2 ** 4).times do
      file << 256.times.map{ |x| rand(0..255).chr }.join
    end
    sleep 0.0001 # simulate some delay (e.g. api call)
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


def fiber_multit_test
  SpawningPool do
    channel = pool.channel(capacity: CAPACITY, multithread: true)

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
  channel = SpawningPool.channel(capacity: CAPACITY, multithread: true)

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
  channel = SpawningPool.channel(capacity: CAPACITY, multithread: true)

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
  channel = SpawningPool.channel(capacity: CAPACITY, multithread: true)

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

Benchmark.bmbm do |x|
  x.report("1T") { nude_test }
  x.report("1T, MF") { fiber_test }
  x.report("1T, MF, CMT") { fiber_multit_test }
  x.report("MT PUSH, MF RECV") { pusher_external }
  x.report("F PUSH, MT RECV") { puller_external }
  x.report("MT only") { thread_test }
end