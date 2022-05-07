# frozen_string_literal: true

RSpec.describe SpawningPool do

  it "has a version number" do
    expect(SpawningPool::VERSION).not_to be nil
  end

  it "condition variable" do
    SpawningPool do
      m = Mutex.new
      c = ConditionVariable.new

      pool.spawn do
        m.synchronize do
          c.wait(m)
          puts "we waited enough!"
        end
      end

      pool.spawn do
        m.synchronize do
          sleep 0.5
          puts "ok bro, your turn!"
          c.signal
        end
      end

    end
  end

  it "can communicate between two fibers" do
    sum = 0

    ichannel = SpawningPool.channel(capacity: 10)

    SpawningPool do
      pool.spawn do
        100.times{ |x| ichannel << x }
        ichannel << nil
      end

      pool.spawn do
        while value = ichannel.receive
          sum += value
        end
      end
    end

    expect(sum).to eq(4950)
  end

  it "can spawn some workers" do
    sum = 0

    ichannel = SpawningPool.channel(capacity: 10)

    SpawningPool do
      pool.spawn do
        100.times{ |x| ichannel << x }
        ichannel.close
      end

      pool.spawn(ichannel, workers: 2) do |value|
        sum += value
      end

    end

    expect(sum).to eq(4950)
  end

  it "unlimited capacity channel" do
    sum = 0

    ichannel = SpawningPool.channel

    SpawningPool do
      pool.spawn do
        time = Time.now.to_f
        10.times{ |x|
          ichannel << x
          sleep 0.01
        }
        ichannel.close
      end

      pool.spawn(ichannel, workers: 32) do |value|
        sum += value
        sleep(0.01)
      end
    end

  end

  describe "multi-thread" do
    it "multi-thread channel" do
      SpawningPool do
        ichannel = SpawningPool.channel
        sum = 0

        pool.spawn_thread "sender_thread" do
          time = Time.now.to_f
          50.times{ |x|
            ichannel << x
            sleep 0.001
          }
          ichannel.close
        end

        pool.spawn_thread "receiver_thread" do
          pool.spawn(ichannel, workers: 32) do |value|
            sum += value
            sleep(0.001)
          end
        end

      end
    end

    it "double way multi-thread channel" do
      SpawningPool do
        # Collatz conjecture fun. The worst way you can run it !
        ichannel = pool.channel capacity: 1
        ichannel << 27

        pool.spawn_thread "3x+1" do
          loop do
            value = ichannel.receive

            if value & 1 == 1
              ichannel << (3*value + 1)
            else
              ichannel << value # give to the other thread
              sleep 0.001
            end
          rescue SpawningPool::Channel::ClosedError
            break # do nothing
          end
        end

        pool.spawn_thread "x/2" do
          loop do
            value = ichannel.receive

            if value == 1
              ichannel.close
              break
            end

            if value & 1 == 0
              ichannel << value / 2
            else
              ichannel << value
              sleep 0.001
            end
          end
        end
      end
    end

    it "unmanaged multi-thread channel" do
      channel = SpawningPool.channel
      sum = 0

      $stdout.sync = false

      t1 = Thread.new do
        10.times do |x|
          channel << x
        end
        channel.close
      end

      t2 = Thread.new do
        loop do
          v = channel.receive
          sum += v
        rescue SpawningPool::Channel::ClosedError
          break
        end
      end

      [t1, t2].map(&:join)
      expect(sum).to eq(45)
    end

    it "mixed managed and unmanaged multi-thread channel" do
      channel = SpawningPool.channel(capacity: 5)
      sum = 0

      t1 = Thread.new do
        Thread.stop
        puts "let's start"
        100.times do |x|
          channel << x
        end
        puts "done sent?"
        channel.close
      end
      t1.name = "SenderThread"
      sleep 0.01 while t1.status!='sleep'
      t1.run

      # t2 = Thread.new do
      #   while t1.alive? do
      #     sleep 5
      #     puts
      #     Thread.list.each {|t| p t}
      #   end
      # end

      SpawningPool do
        puts "spawn?"
        pool.spawn(channel, workers: 1) do |message|
          sum += message
        end
      end

      t1.join
      expect(sum).to eq(4950)

    end

  end
end
