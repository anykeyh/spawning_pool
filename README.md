# SpawningPool

A very simple to use Fiber and Fiber Scheduler for Ruby 3.0+.

- Use goroutine channel concept to communicate between fibers.
- Channel should be thread-safe and could be used to communicate between threads. (thus, this is experimental)
- Easy to use worker pool (see example below)

## Getting started

```bash
$ gem install spawning_pool
```

Then a quick example:

```ruby
require "spawning_pool"

SpawningPool do
    channel = pool.channel

    pool.spawn(channel) do |value|
        puts "received: #{value}"
    end

    channel << "a bunch of zerglings"
end
```

### `spawn` method

Spawn one (or more fibers):

```ruby
require "open-uri"

SpawningPool do
  stop = false

  pool.spawn do
    # Spawn and run the fiber now
    puts "this is a fiber"
    # The fiber won't keep the hand on IO operations...
    URI.open("https://www.ruby-lang.org/") do |f|
        f.each_line {|line| puts line}
    end
    stop = true
  end

  # so you can perform other operations in the mean time
  pool.spawn do
    until stop do
        puts "..."
        sleep 0.01
    end
  end
end
```

Using optional `channel` as entry point for your _spawner_ will run the block
everytime a message is received:

```ruby
SpawningPool do
  channel = pool.channel

  # default worker count is 1, meaning non parallel processing of the messages
  # of the channel.
  pool.spawn(channel, workers: 32) do |message|
      puts "I received a message: #{message}"
      sleep 1
  end

  32.times{ |x| channel << "message #{x}" }
  channel.close # Don't forget to close the channel so the spawn will not hang.
end
```

### `channel` method

```ruby
# A channel is a pipe to communicate between fibers/thread.
channel = pool.channel(capacity: 10)

# you can send a message:
channel.push "a message"
channel << "another way of pushing"

# then you can receive the message in another fiber
output = channel.receive

# By default, a channel has capacity of `0` (infinite).
#
# You can setup a capacity which will block the pusher until
# receiver consume messages.
#
# if your channel is full, the current fiber stop running.
# So don't forget to always have a consumer !
#
10.times{ channel << "spam" } # woops the code will stuck indefinitely, no consumers!

spawn { # Let's fix this by adding a consumer
    begin
        while message = channel.receive
            # perform some operation here.
        end
    end
}

# Channel can be closed:
channel.close
# Consumers will run until the remaining messages in channel are consumed.
# No new message can be pushed:
channel << "a new message" # SpawningPool::Channel::ClosedError !

# Using spawn(channel) do ... end syntax as above, we handle directly the close
# event :

spawn(channel) do |message|
    perform_operation(message)
end

channel << "one operation" << "and we're good!"
channel.close # The spawner above will automatically stop. There is nothing to do
```
## `spawn_thread` method

```ruby
# Like spawn, but will create a Thread instead of a fiber.
# The name is optional
pool.spawn_thread "a cool thread name" do
    spawn do
        # This fiber lives into the thread above
    end
end

# What is the interest then? For dealing with non-io or blocking operations,
# legacy ruby setup and so on...
```

## `timeout` method

```ruby
# You should not use the standard Timeout method when using SpawningPool, but instead:

SpawningPool do
    timeout(2.0) do
        long_task_might_fail
    end
rescue Timeout::Error
    puts "cannot finish under 2 seconds!"
end

# Note that due to the cooperative design of fibers, in such case 2 seconds would
# be "at least 2 seconds". If a fiber is keeping hand, the timeout might be
# triggered much later or even never (in which case your code has a problem).
```

## Mentions

- The selector is [forked from here](https://raw.githubusercontent.com/socketry/event/ee7f6bfa0b4a1df20af91639a73a23a241238a2c/lib/event/selector/select.rb)
- The scheduler is also deeply inspired and partially copied from the Async project
- [Async](https://github.com/socketry/async) is a great alternative to SpawningPool (both projects are not compatible).
- I wanted however to provide a much simpler alternative to Async which provide way more features.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/spawning_pool.
