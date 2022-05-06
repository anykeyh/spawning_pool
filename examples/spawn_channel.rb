require_relative "../lib/spawning_pool"

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