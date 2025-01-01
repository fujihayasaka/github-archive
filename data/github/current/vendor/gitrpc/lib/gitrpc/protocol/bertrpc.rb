# rubocop:disable Style/FrozenStringLiteralComment
require "gitrpc"
require "bertrpc"
require "securerandom"

require "iopromise/bertrpc"

module GitRPC
  class Protocol
    # The BERTRPC protocol implementation handles encoding and decoding of
    # remote backend method invocations using BERTRPC. See the BERTRPC website
    # for more information on the wire protocol:
    #
    # <http://bert-rpc.org/>
    #
    # BERTRPC URLs look like this:
    #
    #     bertrpc://example.org/path/to/repo.git
    #
    # They must include the host and path parts and may also include a port as
    # in the following example:
    #
    #     bertrpc://example.org:9119/path/to/repo.git
    #
    # The BERTRPCServer handler module is the server side. It must be running on
    # the remote host under a "gitrpc" module name.
    class BERTRPC < Protocol
      # The URI object used to construct this object.
      attr_reader :url

      # The host to connect to. This must be specified in the URL.
      attr_reader :host

      # The port to connect to. Defaults to 8149 when not given in the URL.
      attr_reader :port

      # The full path to the repository on disk on the remote machine. This must
      # be specified in the URL.
      attr_reader :path

      # Default BERTRPC port. Used when no port is given in the URL.
      class << self
        attr_accessor :port
      end
      self.port = 8149

      # Create a new BERTRPC protocol object for the given URL and options. No
      # actual connection is established until the #send_message method is
      # called so no exception.
      #
      # url     - A URI object whose scheme is "bertrpc". The host and path
      #           parts must be present. The port is optional but supported.
      # options - The options hash to pass to the backend.
      #
      def initialize(url, options = {})
        @spokesd_client = options.delete(:spokesd_client)
        @url = url
        @options = options.dup

        if @options[:timeout].nil? && GitRPC.timeout
          @options[:timeout] = GitRPC.timeout
        end

        @host = url.host
        @port = url.port || self.class.port
        @path = url.path

        @timeout = @options[:timeout]

        if GitRPC.local_access?(@host)
          @remote = BERTLocalFileWrapper.new(url, options)
        else
          @service = ::BERTRPC::Service.new(@host, @port, client_timeout,
                                           connect_timeout)
          @remote = @service.call.gitrpc
        end
      end

      def remote
        if @timeout != @options[:timeout]
          if GitRPC.local_access?(@host)
            @remote =  BERTLocalFileWrapper.new(url, options)
          else
            @service ||= ::BERTRPC::Service.new(@host, @port, client_timeout,
                                              connect_timeout)
            @service.timeout = client_timeout
            @remote = @service.call.gitrpc
          end
        end
        @remote
      end

      # Internal: Actual timeout value to use as the client connect / read
      # timeout. This is fudged for network access to give enough time
      # for the remote side to timeout and return giving a deeper backtrace.
      #
      # Returns a float number of seconds for the timeout or nil when no timeout
      # is given.
      def client_timeout
        GitRPC::Timer.fudge(timeout, :client)
      end

      def timeout
        options[:timeout]
      end

      # Grab connect_timeout from options or global value if not specified.
      def connect_timeout
        options[:connect_timeout] || GitRPC.connect_timeout
      end

      # Protocol implementations must expose the provided options hash.
      attr_reader :options

      def encode_bert_request(options, args, kwargs)
        encoded = {
          :options => encode_bert_field(options),
          :args => encode_bert_field(args),
          :kwargs => encode_bert_field(kwargs),
        }
        encoded_size = encoded.values.sum { |v| v.bytesize }
        if encoded_size > GitRPC.max_request_size
          raise GitRPC::RequestTooLarge.new(encoded_size)
        end
        encoded
      end

      def encode_bert_field(data)
        encoded = ::BERT::Encoder.encode(data)
        # Trim version byte
        encoded[1..]
      end

      def decode_bert_payload(raw)
        raise GitRPC::Error, "response does not contain a valid header" if raw.size < 4
        header_len = raw[0..3].unpack('N').first
        real_len = raw[4..].size
        raise GitRPC::Error, "response length #{real_len} does not match header #{header_len}" if real_len != header_len
        ::BERT::Decoder.decode(raw[4..])
      end

      # Make the remote call and translate exceptions if necessary.
      def send_message(message, *args, **kwargs)
        if !@spokesd_client.nil?
          return send_message_through_spokesd(message, *args, **kwargs)
        end
        GitRPC.instrument(:bertrpc_send_message, name: message, args: args, url: @url) do |instrument_payload|
          status, res = remote.send_message(@path, options, message, args, kwargs)
          if status == :ok
            res
          elsif status == :boom
            GitRPC::Failure.raise(res)
          else
            raise GitRPC::NetworkError, "invalid bertrpc status: #{status.inspect}"
          end
        end
      rescue Mochilo::PackError => boom
        raise GitRPC::EncodingError, boom
      rescue RuntimeError => boom
        if boom.to_s.include?("Cannot encode to erlang external format")
          raise GitRPC::EncodingError, boom
        else
          raise
        end
      rescue ::BERTRPC::BERTRPCError
        raise self.class.map_error($!)
      end

      def spokesd_host_from_url(url)
        if (ENV["RAILS_ENV"] == "development" || ENV["RAILS_ENV"] == "test") &&
            (url.host == "127.0.0.1" || url.host == "localhost")
          # In development and test, spokesd knows how to map these host
          # names to the correct gitrpcd port numbers.
          case url.port
          when 8149
            return "dgit1."
          when 8150
            return "dgit2."
          when 8151
            return "dgit3."
          when 8152
            return "dgit4."
          when 8153
            return "dgit5."
          end
        end

        url.host
      end
      private :spokesd_host_from_url

      def send_message_through_spokesd(message, *args, **kwargs)
        GitRPC.instrument(:bertrpc_send_message_through_spokesd, name: message, args: args, url: @url) do |instrument_payload|
          resp = begin
            encoded_request = encode_bert_request(options, args, kwargs)
            @spokesd_client.bertrpc(
              spokesd_host_from_url(url),
              @path,
              client_timeout,
              encoded_request[:options],
              message,
              encoded_request[:args],
              encoded_request[:kwargs])
          rescue Faraday::TimeoutError
            raise GitRPC::Timeout.new("Faraday timed out")
          end
          if resp.respond_to?(:data) && resp.data.respond_to?(:ernicorn_response)
            response = decode_bert_payload(resp.data.ernicorn_response.response)
          else
            fail "invalid resp: #{resp.inspect}"
          end

          fail "not a reply: #{response[0].inspect}" if response[0] != :reply
          status, res = response[1]
          if status == :ok
            res
          elsif status == :boom
            GitRPC::Failure.raise(res)
          else
            raise GitRPC::NetworkError, "invalid bertrpc status: #{status.inspect}"
          end
        end
      rescue Mochilo::PackError => boom
        raise GitRPC::EncodingError, boom
      rescue RuntimeError => boom
        if boom.to_s.include?("Cannot encode to erlang external format")
          raise GitRPC::EncodingError, boom
        else
          raise
        end
      rescue ::BERTRPC::BERTRPCError
        raise self.class.map_error($!)
      end

      def async_send_message(message, *args, **kwargs)
        Promise.resolve.then do
          send_message(message, *args, **kwargs)
        end
      end

      # Default repository scope cache key
      def repository_key
        Digest::SHA256.hexdigest(@path)
      end

      # Send [message, args] to the specified route via BERTRPC
      # This interface is different than protocol method `send_message` in that
      # exceptions are not squashed into GitRPC::Errors for callers that need to
      # full detail such as the DGIT protocol.
      def self.send_single(route, message, args, kwargs, options = {})
        proto = from_route(route, options)

        GitRPC.instrument(:bertrpc_send_message, name: message, args: args, route: route, url: proto.url, async: false) do |instrument_payload|
          status, res = proto.remote.send_message(route.path, options, message, args, kwargs)

          # [:boom, exception] is for errors that happen on the GitRPC server
          if status == :boom
            GitRPC::Failure.raise res
          else
            return res
          end
        end
      end

      def self.async_send_single(route, message, args, kwargs, options = {})
        if route.respond_to? :remote
          bert_mod = route.remote
          url = route.url
        else
          proto = from_route(route, options)
          url = proto.url
          bert_mod = proto.remote
        end

        queued_cb, begin_cb, end_cb = GitRPC.instrument_callbacks(:bertrpc_send_message, name: message, args: args, route: route, url: url, async: true)

        queued_cb.call

        promise = ::IOPromise::BERTRPC.async_call(bert_mod, :send_message, route.path, options, message, args, kwargs)
        promise.instrument(begin_cb, end_cb)
        promise
      end

      # Send [message, args] to all of the routes via BERTRPC. Return
      # the resulting answers and errors. This method does no error or
      # consistency checking except to verify that we got *some* kind
      # of result (which might be a timeout or connection error or
      # whatever) for every route.
      #
      # Each item in routes may be a Route-like object (that responds
      # to resolved_host, port, and path) or a GitRPC::Protcol::BERTRPC
      # object (that responds to remote and path).
      def self.send_multiple(routes, message, args, kwargs, options = {})
        answers = {}
        errors = {}

        # Fill in timeout values, if they're missing.
        options = {
          :timeout => GitRPC.timeout,
          :connect_timeout => GitRPC.connect_timeout,
        }.merge(options)

        rpc_start = Time.now
        notify_base = {
          name: message,
          args: args
        }

        handler = ::BERTRPC::MuxHandler.new
        routes.each do |route|
          notify_payload = notify_base.dup
          if route.respond_to? :remote
            rpc = route.remote
            notify_payload[:url] = route.url
          else
            proto = from_route(route, options)
            notify_payload[:route] = route
            notify_payload[:url] = proto.url
            rpc = proto.remote
          end

          cs = handler.queue(rpc)
          cs.on_complete do |result|
            answers[route] = result

            GitRPC.publish(:bertrpc_send_message, rpc_start, Time.now, SecureRandom.hex(10), notify_payload)
          end
          cs.on_error do |error|
            errors[route] = error.is_a?(Array) ? GitRPC::Failure.decode(error) : error
            notify_payload[:exception] = [errors[route].class.name, errors[route].message]

            GitRPC.publish(:bertrpc_send_message, rpc_start, Time.now, SecureRandom.hex(10), notify_payload)
          end
          rpc.send_message(route.path, options, message, args, kwargs)
        end
        handler.run(options[:timeout], options[:connect_timeout])
        errors.each do |route, error|
          errors[route] = unify_bert_timeouts(error)
        end

        # Make sure we got the right number of answers + errors.
        unless answers.length + errors.length == routes.length
          raise DGit::ResponseError.new(
              "Expected #{routes.length} responses, got #{answers.length} + #{errors.length}",
                  answers: answers, errors: errors, rpc_operation: message)
        end

        [answers, errors]
      end

      # Similar to send_multiple above, except uses async_send_single to do all
      # the work and instrumentation. Still happens in parallel, because of
      # IOPromise.
      def self.async_send_multiple(routes, message, args, kwargs, options = {})
        # Fill in timeout values, if they're missing.
        options = {
          :timeout => GitRPC.timeout,
          :connect_timeout => GitRPC.connect_timeout,
        }.merge(options)

        promises = routes.to_h { |route| [route, async_send_single(route, message, args, kwargs, options)] }

        # wrap every result promise in a new promise that always succeeds
        # this avoids any early erroring on rejections.
        always_succeed = promises.values.map { |p| p.rescue { nil } }

        # wait on all of those to complete, by which point our original promises will resolve either way
        Promise.all(always_succeed).then do
          answers = promises.select { |k, v| v.fulfilled? }.map { |k, v| [k, v.value] }.to_h
          errors = promises.select { |k, v| v.rejected? }.map { |k, v| [k, unify_bert_timeouts(v.reason)] }.to_h
          [answers, errors]
        end
      end

      def self.from_route(route, options = {})
        # Determination around "local" access (See BERTLocalFileWrapper) is
        # based on hostname.  If we know this route will be used for local
        # access here, we can avoid getting confused by resolving to an ip
        # address and then failing to detect that local access.
        if GitRPC.local_access?(route.host)
          url = URI.parse("bertrpc://#{route.host}:#{route.port}#{route.path}")
        else
          url = URI.parse("bertrpc://#{route.resolved_host}:#{route.port}#{route.path}")
        end
        self.new(url, options)
      end

      def self.map_error(err)
        boom = case err
        when ::BERTRPC::ConnectionError
          GitRPC::ConnectionError.new(err)
        when ::BERTRPC::ReadTimeoutError
          GitRPC::Timeout.new(err)
        when ::BERTRPC::ReadError
          GitRPC::NetworkError.new(err)
        when ::BERTRPC::ProtocolError
          GitRPC::NoDataError.new(err)
        else
          GitRPC::Failure.wrap(err)
        end
        if !boom.backtrace || boom.backtrace.empty?
          boom.set_backtrace(caller)
        end
        boom
      end

      def self.unify_bert_timeouts(error)
        if error.is_a?(::BERTRPC::ReadTimeoutError)
          boom = GitRPC::Timeout.new(error)
          boom.set_backtrace(error.backtrace)
          boom
        else
          error
        end
      end
    end

    class BERTLocalFileWrapper
      attr_accessor :rpc, :path, :mux_handler, :call_state
      def initialize(route, options)
        @rpc = GitRPC::Backend.new(route.path, options)
        @path = route.path
        @call_state = BERTLocalCallState.new
      end

      def send_message(path, opts, message, args, kwargs)
        # In case we need to run in parallel, we queue up
        # the message so it's read later and other remote
        # rpc calls can be set up in parallel.
        if mux_handler
          call_state.queue_message(@rpc, message, args, kwargs)
        else
          res = @rpc.send_message(message, *args, **kwargs)
          [:ok, res]
        end
      end
    end

    class BERTLocalCallState < ::BERTRPC::MuxHandler::CallState
      def queue_message(rpc, message, args, kwargs)
        @rpc = rpc
        @message = message
        @args = args
        @kwargs = kwargs
      end

      def read_result
        res = @rpc.send_message(@message, *@args, **@kwargs)
        [:ok, res]
      rescue => boom
        failure = GitRPC::Failure.new(boom)
        [:boom, failure.encode]
      end

      def to_s
        "<local=true error=#{@error.inspect} result=#{@result.inspect}>"
      end

      def connected?
        true
      end

      def finished?
        true
      end

      def run
      end

      def select_fds
        [nil, nil]
      end
    end

    # Ernie server-side handler for the BERTRPC protocol. This runs on the
    # remote side and receives the #send_message call made by the protocol
    # implementation.
    module BERTRPCServer
      def send_message(path, options, message, args, kwargs)
        return [:ok, true] if message == :_ping

        backend = GitRPC::Backend.new(path, options)
        res = backend.send_message(message, *args, **kwargs)
        [:ok, res]
      rescue => boom
        Ernicorn.filter_backtrace(boom)
        failure = GitRPC::Failure.new(boom)
        [:boom, failure.encode]
      ensure
        backend.cleanup if backend
      end

      # Register the server module with Ernicorn.
      def self.expose
        Ernicorn.expose(:gitrpc, self)
      end
    end
  end
end
