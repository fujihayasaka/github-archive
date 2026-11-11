# frozen_string_literal: true

require "unicorn"

module Ernicorn
  Stats = Raindrops::Struct.new(:connections_total,
                                :connections_completed,
                                :workers_idle).new

  class Server < Unicorn::HttpServer

    # Private HttpServer methods we're overriding to
    # implement BertRPC instead of HTTP.

    def initialize(app, options = {})
      @source_root = options.delete(:source_root)
      Ernicorn.set_source_root(@source_root)
      super app, options
    end

    def build_app!
    end

    def worker_loop(worker)
      Stats.incr_workers_idle

      if worker.nr == (self.worker_processes - 1)
        old_pid = "#{self.pid}.oldbin"
        if File.exist?(old_pid) && self.pid != old_pid
          begin
            Process.kill("QUIT", File.read(old_pid).to_i)
          rescue Errno::ENOENT, Errno::ESRCH
            # someone else did our job for us
          end
        end
      end

      super
    ensure
      Stats.decr_workers_idle
    end

    def process_client(client, ai)
      @client = client

      Stats.decr_workers_idle
      Stats.incr_connections_total

      # We want to accept HTTP and BERT payloads so we peek at the start of the
      # request and guesstimate whether we think that's the BERT-RPC size or the
      # start of a HTTP request.

      r = nil
      loop do
        r = client.recv(4, Socket::MSG_PEEK)
        # The client closed the connection, move on
        return if r.nil?
        # We need at least four bytes to determine the protocol
        break if r.bytesize >= 4
      end

      is_bertrpc = case r
      when "GET ", "POST"
        # Looks like HTTP to me
        false
      else
        # It's probably the length of a BERT-RPC
        true
      end

      if is_bertrpc
        if Ernicorn.respond_to?(:around_action)
          Ernicorn.around_action { process_ernicorn_client(client, ai) }
        else
          process_ernicorn_client(client, ai)
        end
      else
        process_http_client(client)
      end
    ensure
      @client.close rescue nil
      @client = nil

      Stats.incr_connections_completed
      Stats.incr_workers_idle
    end

    def process_http_client(client)
      # We can delegate the HTTP parsing to the code unicorn would have used
      # itself.
      env = @request.read(client)
      status, headers, body = @app.call(env)

      http_response_write(client, status, headers, body,
                          @request.response_start_sent)

    end

    def process_ernicorn_client(client, ai)
      @client = client
      # bail out if client only sent EOF
      return if @client.recvmsg_nonblock(1, Socket::MSG_PEEK).nil?

      iruby, oruby = Ernicorn.process(self, self)
    rescue EOFError
      logger.error("EOF from #{ai rescue nil}")
    rescue Object => e
      logger.error(e)

      begin
        error = t[:error, t[:server, 0, e.class.to_s, e.message, e.backtrace]]
        Ernicorn.write_berp(self, error)
      rescue Object => ex
        logger.error(ex)
      end
    end

    # Stolen from Unicorn.  I saw 8192 on my machine, but I'm not sure what
    # is in production.
    BUF_SIZE = 16384 # :nodoc:

    # We pass ourselves as both input and output to Ernicorn.process, which
    # calls the following blocking read/write methods.

    def read(len)
      data = String.new capacity: len

      # If we're lucky, the entire blob has been buffered by the OS.  In that
      # case, we can read from the socket straight in to the buffer so we
      # only end up with 1 call to malloc (above).
      if len <= BUF_SIZE
        data = @client.readpartial(len, data)
        return data if data.bytesize == len
      end

      # Otherwise, start reading BUF_SIZE chunks from the socket
      buf = String.new capacity: BUF_SIZE

      # We read BUF_SIZE chunks from the socket because the socket can only
      # buffer so much data.  If we pass (for example) 10MB to the read call,
      # kgio will ensure that the buffer has 10MB free so that it can put the
      # expected bytes in there.  However, since there is no way we have 10MB
      # buffered by the OS, it means we'll have allocated 10MB for nothing.
      # If we read a smaller amount, something closer to what the OS actually
      # buffers, then we won't waste the allocator's time with trying to find
      # large buffers
      while data.bytesize < len
        to_read = len - data.bytesize
        to_read = BUF_SIZE if to_read > BUF_SIZE
        buf = @client.readpartial(to_read, buf)
        data << buf
      end

      data
    end

    def write(data)
      @client.write(data)
    end

    def stop(graceful = true)
      self.pid = "#{self.pid}.#{$$}" if pid.end_with?(".oldbin")
      super
    end
  end
end
