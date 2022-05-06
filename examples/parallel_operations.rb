require_relative "../lib/spawning_pool"

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