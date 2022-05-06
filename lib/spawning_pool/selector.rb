# Imported and slightly modified from the work of Samuel G. D. Williams
# Copyright, 2021, by Samuel G. D. Williams. <http://www.codeotaku.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# original work here:
# https://raw.githubusercontent.com/socketry/event/ee7f6bfa0b4a1df20af91639a73a23a241238a2c/lib/event/selector/select.rb
#
# I had to fix an issue with Multi-thread Channel communication preventing
# the event loop to run properly and getting stuck indefinitely.
#
class SpawningPool
  class Selector

    READABLE = 1
    PRIORITY = 2
    WRITABLE = 4

    attr_reader :loop

    def initialize(loop)
      @loop = loop

      @readable = {}
      @writable = {}

      # Interruption IO for IO::Select
      @intr_io_r, @intr_io_w = IO.pipe

      @ready = []
      @mutex = Mutex.new
    end

    def close
      @loop = nil
      @readable = nil
      @writable = nil
      @intr_io_w.close rescue nil
    end

    Queue = Struct.new(:fiber, :raise_arg) do
      def transfer(*arguments)
        if raise_arg
          fiber&.raise(*raise_arg)
        else
          fiber&.transfer(*arguments)
        end
      end

      def alive?
        fiber&.alive?
      end

      def nullify
        self.fiber = nil
      end
    end

    # Transfer from the current fiber to the event loop.
    def transfer
      @loop.transfer
    end

    # Transfer from the current fiber to the specified fiber. Put the current fiber into the ready list.
    def resume(fiber, *arguments)
      queue = Queue.new(Fiber.current)
      @mutex.synchronize { @ready.push(queue) }

      fiber.transfer(*arguments)
    end

    # # Yield from the current fiber back to the event loop. Put the current fiber into the ready list.
    def yield
      queue = Queue.new(Fiber.current)
      @ready.push(queue)
      @loop.transfer
    end

    # Append the given fiber into the ready list.
    def push(fiber)
      queue = Queue.new(fiber)
      @mutex.synchronize { @ready.push(queue) }
    end

    # Transfer to the given fiber and raise an exception. Put the current fiber into the ready list.
    def raise(fiber, *arguments)
      queue = Queue.new(fiber, arguments)
      @mutex.synchronize { @ready.push(queue) }
    end

    def ready?
      @ready.any?
    end

    def io_wait(fiber, io, events)
      raise "MEH" if @io_error

      remove_readable = remove_writable = false

      if (events & READABLE) > 0 or (events & PRIORITY) > 0
        @readable[io] = fiber
        remove_readable = true
      end

      if (events & WRITABLE) > 0
        @writable[io] = fiber
        remove_writable = true
      end

      @loop.transfer
    ensure
      @readable.delete(io) if remove_readable
      @writable.delete(io) if remove_writable
    end

    if IO.const_defined?(:Buffer)
      def io_read(fiber, io, buffer, length)
        offset = 0

        while length > 0
          # The maximum size we can read:
          maximum_size = buffer.size - offset

          case result = io.read_nonblock(maximum_size, exception: false)
          when :wait_readable
            self.io_wait(fiber, io, READABLE)
          when :wait_writable
            self.io_wait(fiber, io, WRITABLE)
          else
            break if result.empty?

            buffer.copy(result, offset)

            offset += result.bytesize
            length -= result.bytesize
          end
        end

        return offset
      end

      def io_write(fiber, io, buffer, length)
        offset = 0

        while length > 0
          # From offset until the end:
          chunk = buffer.to_str(offset, length)
          case result = io.write_nonblock(chunk, exception: false)
          when :wait_readable
            self.io_wait(fiber, io, READABLE)
          when :wait_writable
            self.io_wait(fiber, io, WRITABLE)
          else
            offset += result
            length -= result
          end
        end

        return offset
      end
    end

    def process_wait(fiber, pid, flags)
      r, w = IO.pipe

      thread = Thread.new do
        Process::Status.wait(pid, flags)
      ensure
        w.close
      end

      self.io_wait(fiber, r, READABLE)

      return thread.value
    ensure
      r.close
      w.close
      thread&.kill
    end

    private def pop_ready
      return false if @ready.empty?

      ready = nil

      @mutex.synchronize do
        ready = @ready
        @ready = []
      end

      ready.each do |fiber|
        fiber.transfer if fiber.alive?
      end

      true
    end

    # write to the interruption pipe to for IO select to resolve in the
    # select block.
    def continue
      @intr_io_w.write("\0")
      @intr_io_w.flush
    rescue IOError
      # the target is already dead
    end

    def select(duration = nil)
      if pop_ready
        duration = 0
      end

      # if @readable.empty? && @writable.empty? && duration.nil?
      #   # wait for another thread to wake this thread up
      #   # if no IO are in progress in any fiber.
      #   Thread.stop
      #   return
      # end

      begin
        readables = @readable.keys
        readables <<  @intr_io_r

        readable, writable, = ::IO.select(readables, @writable.keys, nil, duration)
      rescue IOError, Errno::EBADF => e
        pp e
        pp readables
        pp @writable.keys
        @io_error = true
        # exit 0
        # @intr_io_r = nil
        # EBADF can appears in case the io pipe has been closed by another thread
        # do nothing.
      end

      ready = Hash.new(0)

      readable&.each do |io|
        if io == @intr_io_r
          # consume the pipe.
          io.read_nonblock(1, exception: false)
          next
        end

        fiber = @readable.delete(io)
        ready[fiber] |= READABLE
      end

      writable&.each do |io|
        fiber = @writable.delete(io)
        ready[fiber] |= WRITABLE
      end

      ready.each do |fiber, events|
        fiber.transfer(events) if fiber.alive?
      end
    end
  end
end
