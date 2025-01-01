# rubocop:disable Style/FrozenStringLiteralComment

require "gitrpc"
require "bertrpc"
require "bert"
require "scientist"

module GitRPC
  class GitrpcProxyDelegate < SimpleDelegator
    def initialize(target, routes=[])
      @routes = routes
      super(target)
    end

    def write_quorum
      GitHub.dgit_quorum(@routes.count(&:voting?))
    end

    def unanimous_quorum
      GitHub.dgit_quorum(@routes.count(&:voting?))
    end
  end

  class Protocol
    # The DGit protocol is a front-end to BERTRPC.  It looks up replicas
    # in MySQL, routes writes to all replicas, and routes reads to a
    # single, best replica.  Writes proceed in parallel, and GitRPC is
    # responsible for resolving disagreeing responses among replicas.
    #
    # DGit URLs look like this:
    #
    #     dgit:/
    #
    # Other information is taken from the delegate.
    class DGit < Protocol
      include Scientist
      DEFAULT_READ_TIMEOUT = nil
      DEFAULT_CONNECT_TIMEOUT = 1.5

      # Format the host part of route for output to a human, including
      # an annotation telling whether it is nonvoting.
      def self.format_route(route)
        voting = route.voting? ? "" : " (nonvoting)"
        "#{route.original_host}#{voting}"
      end

      class ResponseError < GitRPC::Error
        attr_reader :answers, :errors
        def initialize(message, answers: {}, errors: {}, rpc_operation: nil)
          @answers = answers
          @errors = errors
          @rpc_operation = rpc_operation
          if ENV["RAILS_ENV"] == "test"
            str = message.dup
            if @answers.any?
              str << "\nanswers:\n#{format_results(@answers)}"
            end
            if @errors.any?
              str << "\nerrors:\n#{format_results(@errors)}"
            end
            super(str)
          else
            super(message)
          end
        end

        def format_results(results)
          results.map { |route, obj| "    #{format_result(route, obj)}" }.join("\n")
        end
        private :format_results

        def failbot_context
          a = @answers.map { |route, obj| format_result(route, obj) }.join(", ")
          e = @errors.map { |route, obj| format_result(route, obj) }.join(", ")
          {
            :rpc_operation => @rpc_operation,
            :answers       => a,
            :errors        => e,
          }
        end

        def format_result(route, obj)
          "#{::GitRPC::Protocol::DGit.format_route(route)} => #{obj.inspect}"
        end
        private :format_result
      end

      NAMESPACES = %w{repository wiki network gist gist-creation}

      # The URI object representing this object. This is hopefully not
      # used for anything serious...
      attr_reader :url

      # The repository ID to look up.
      attr_reader :repo_id

      # Create a new DGit protocol object for the given repository.  No
      # lookups are performed and no connection is established until the
      # send_message method is called so no exception.
      #
      # url     - A URI object whose scheme is "dgit". The rest is not used
      #           (the other information we need is taken from delegate).
      # delegate - A DGit::Delegate object for interacting with MySQL.
      # options - The options hash to pass to the backend.
      #
      def initialize(url, options = {})
        @delegate = options.delete(:delegate)
        @options = options

        if @options[:timeout].nil? && GitRPC.timeout
          @options[:timeout] = GitRPC.timeout
        end

        raise GitRPC::Error, "delegate is required" unless @delegate
        raise GitRPC::Error, "invalid dgit namespace: #{@delegate.namespace}" unless NAMESPACES.include?(@delegate.namespace)
        raise GitRPC::Error, "invalid dgit database ID: #{@delegate.id}" unless (@delegate.id && @delegate.id > 0) || @delegate.namespace == "gist-creation"
        raise GitRPC::Error, "invalid dgit path: #{@delegate.shard_path}" unless @delegate.shard_path =~ %r{^/.}

        # We don't use the url that was passed in; all the information
        # we need is in delegate:
        @url = URI.parse(
          if @delegate.id
            "dgit://#{@delegate.namespace}:#{@delegate.id}#{@delegate.shard_path}"
          else
            "dgit://#{@delegate.namespace}#{@delegate.shard_path}"
          end
        )
      end

      def path
        @delegate.shard_path
      end

      def write_routes
        @write_routes ||= @delegate.get_write_routes
      end

      def read_routes
        @read_routes ||= @delegate.get_read_routes
      end

      def all_routes
        @all_routes ||= @delegate.get_all_routes(live_only: false)
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
        options.has_key?(:timeout) ? options[:timeout] : DEFAULT_READ_TIMEOUT
      end

      def connect_timeout
        options.has_key?(:connect_timeout) ? options[:connect_timeout] : DEFAULT_CONNECT_TIMEOUT
      end

      # Protocol implementations must expose the provided options hash.
      attr_reader :options

      # Access to the internal Delegate is exposed for 'gist-creation' handles.
      attr_reader :delegate

      # Make the remote call and translate exceptions if necessary.
      #
      # Essentially all of the complexity in this function is dealing with
      # the possibility of replicas returning different answers to the
      # same question.  Some classes of calls are OK to differ -- for
      # example, calls that return output related to timing, server
      # status, or the maintenance state of the repo.  But in practice,
      # most disagreements are programming errors.  Report them by
      # throwing them to Failbot, so we can fix the errors.  That is,
      # don't try to pick one by consensus or some other metric.
      def send_message(message, *args, **kwargs)
        begin
          # Decide where the message has to be executed, and do so.
          start = Time.now
          case
          when GitRPC::Backend.rpc_writer?(message)
            if @delegate.proxy_gitrpc_through_spokesd?
              send_message_multiple_through_spokesd(message, args, kwargs)
            else
              send_message_multiple(message, :write_routes, args, kwargs)
            end
          when GitRPC::Backend.rpc_cache_writer?(message)
            send_message_multiple(message, :all_routes, args, kwargs)
          when GitRPC::Backend.rpc_reader?(message)
            if @delegate.proxy_gitrpc_through_spokesd?
              send_message_single_through_spokesd(message, args, kwargs)
            else
              send_message_single(message, args, kwargs)
            end
          else
            raise "rpc call #{message} is neither reader nor writer"
          end
        rescue GitRPC::RequestTooLarge => e
          e.gitrpc_name = message
          raise e
        end
      end

      def async_send_message(message, *args, **kwargs)
        Failbot.push("gh.gitrpc.name": message) if defined?(::Failbot)
        case
        when GitRPC::Backend.rpc_writer?(message)
          if @delegate.proxy_gitrpc_through_spokesd?
            async_send_message_multiple_through_spokesd(message, args, kwargs)
          else
            async_send_message_multiple(message, :write_routes, args, kwargs)
          end
        when GitRPC::Backend.rpc_cache_writer?(message)
          async_send_message_multiple(message, :all_routes, args, kwargs)
        when GitRPC::Backend.rpc_reader?(message)
          if @delegate.proxy_gitrpc_through_spokesd?
            async_send_message_single_through_spokesd(message, args, kwargs)
          else
            async_send_message_single(message, args, kwargs)
          end
        else
          raise "rpc call #{message} is neither reader nor writer"
        end
      end

      def send_demux(message, *args, **kwargs)
        if @delegate.proxy_gitrpc_send_demux?
          answers, errors, all_routes = send_multiple_through_spokesd(message, args, kwargs)
          result_collator = ResultCollator.new(GitrpcProxyDelegate.new(@delegate, all_routes), message, answers, errors)
        else
          answers, errors = send_multiple(message, :write_routes, args, kwargs)
          result_collator = ResultCollator.new(@delegate, message, answers, errors)
        end

        result_collator.check_consensus_plausible
        answers
      end

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

      class LegacyRoute
        attr_reader :original_host, :healthy

        def initialize(host, voting, healthy)
          @original_host = host
          @voting = voting
          @healthy = healthy
        end

        def voting?
          @voting
        end

        def hash
          @original_host.hash
        end

        # The LegacyGitrpc::V1::DataServer does not have this information,
        # but it's used when logging app errors which GitRPC suppresses.
        def datacenter
          'unknown'
        end

        def ==(other)
          self.class === other &&
            other.original_host == @original_host
        end
        alias eql? ==
      end

      def decode_bert_multiple_resp(resp)
        answers = {}
        errors = {}
        all_routes = []
        if resp.respond_to?(:data) && resp.data.respond_to?(:responses)
          resp.data.responses.each do |r|
            route = LegacyRoute.new(r.data_server.name, r.data_server.voting, r.data_server.healthy)
            all_routes << route
            if @delegate.is_error(r)
              errors[route] = GitRPC::Error.new(r.ernicorn_response.status.message)
              next
            end
            # Here we need to check the actual BERT protocol and check if the response is an error
            ernicornResp = decode_bert_payload(r.ernicorn_response.response)
            if ernicornResp[0] != :reply
              errors[route] = GitRPC::Error.new("unexpected ernicorn response")
              next
            end
            status, res = ernicornResp[1]
            if status == :ok
              answers[route] = res
            elsif status == :boom
              errors[route] = GitRPC::Failure.decode(res)
            else
              raise GitRPC::Error, "invalid response status #{status.inspect}"
            end
          end
        else
          raise GitRPC::NetworkError, "invalid multiple resp: #{resp.inspect}"
        end
        [answers, errors, all_routes]
      end

      def send_message_single_through_spokesd(message, args, kwargs)
        GitRPC.instrument(:spokesd_send_message, name: message, args: args) do
          encoded_request = encode_bert_request(options, args, kwargs)
          resp = begin
            @delegate.legacy_gitrpc_reader(
              client_timeout,
              encoded_request[:options],
              message,
              encoded_request[:args],
              encoded_request[:kwargs],
              @delegate.map_routes(@read_routes))
          rescue Faraday::TimeoutError
            raise GitRPC::Timeout.new("Faraday timed out")
          end

          if resp.respond_to?(:data) && resp.data.respond_to?(:response)
            response = decode_bert_payload(resp.data.response)
          else
            raise GitRPC::NetworkError, "invalid resp: #{resp.inspect}"
          end

          raise GitRPC::Error, "not a reply" if response[0] != :reply
          status, res = response[1]
          if status == :ok
            res
          elsif status == :boom
            GitRPC::Failure.raise(res)
          else
            raise GitRPC::Error, "invalid bertrpc status: #{status.inspect}"
          end
        end
      end

      def async_send_message_single_through_spokesd(message, args, kwargs)
        GitRPC.instrument(:spokesd_send_message, name: message, args: args, async: true) do
          encoded_request = encode_bert_request(options, args, kwargs)
          p = @delegate.async_legacy_gitrpc_reader(
            client_timeout,
            encoded_request[:options],
            message,
            encoded_request[:args],
            encoded_request[:kwargs],
            @delegate.map_routes(@read_routes))

          p.then do |resp|
            if resp.respond_to?(:data) && resp.data.respond_to?(:response)
              response = decode_bert_payload(resp.data.response)
            else
              raise GitRPC::NetworkError, "invalid resp: #{resp.inspect}"
            end

            raise GitRPC::Error, "not a reply" if response[0] != :reply
            status, res = response[1]
            if status == :ok
              res
            elsif status == :boom
              GitRPC::Failure.raise(res)
            else
              raise GitRPC::Error, "invalid bertrpc status: #{status.inspect}"
            end
          end
        end
      end
      private :async_send_message_single_through_spokesd

      def send_message_single(message, args, kwargs)
        routes = read_routes
        fail if routes.empty?
        error = nil
        if @delegate.use_fakerpc?
          route = routes.first
          begin
            backend = ::GitRPC::Protocol.resolve("fakerpc:#{route.path}", options)
            answer = backend.send_message(message, *args, **kwargs)
            return answer
          rescue => e
            raise ::GitRPC::Protocol::DGit.map_bert_error(e)
          end
        else
          routes.each do |route|
            begin
              return BERTRPC.send_single(route, message, args, kwargs, options)
            rescue => e
              # this error happened on our end
              error = e.is_a?(Array) ? GitRPC::Failure.decode(e) : e
            end

            fail unless error
            case error
            when ::BERTRPC::ReadTimeoutError
              @delegate.on_route_error(route, ::GitRPC::Protocol::DGit.map_bert_error(error))
              # This exception probably indicates that the operation
              # itself (as opposed to the connection to the
              # fileserver) timed out, so we don't continue trying it
              # on other replicas:
              break
            when ::BERTRPC::BERTRPCError
              @delegate.on_route_error(route, ::GitRPC::Protocol::DGit.map_bert_error(error))
              # This was likely a problem with the single replica, so
              # continue trying on others.

              # Put the failed replica at the end of the route list, for
              # the sake of any future read operations on this rpc object.
              @read_routes = (@read_routes - [route]) + [route]
            else
              # This error was at the application level; raise it to
              # the caller.
              break
            end
          end
          raise ::GitRPC::Protocol::DGit.map_bert_error(error)
        end
        fail "This line should not be reached"
      end
      private :send_message_single

      def async_send_message_single(message, args, kwargs)
        routes = read_routes
        fail if routes.empty?
        error = nil
        if @delegate.use_fakerpc?
          route = routes.first
          return Promise.resolve.then do
            begin
              backend = ::GitRPC::Protocol.resolve("fakerpc:#{route.path}", options)
              backend.send_message(message, *args, **kwargs)
            rescue => e
              raise ::GitRPC::Protocol::DGit.map_bert_error(e)
            end
          end
        else
          # note: above we ensure there is at least 1 route here
          routes_remaining = routes.dup

          # try the next route in the list
          do_retry = proc do
            route = routes_remaining.shift

            BERTRPC.async_send_single(route, message, args, kwargs, options).rescue do |e|
              # this error happened on our end
              error = e.is_a?(Array) ? GitRPC::Failure.decode(e) : e

              fail unless error
              case error
              when ::BERTRPC::ReadTimeoutError
                @delegate.on_route_error(route, ::GitRPC::Protocol::DGit.map_bert_error(error))
                # This exception probably indicates that the operation
                # itself (as opposed to the connection to the
                # fileserver) timed out, so we don't continue trying it
                # on other replicas:
                raise ::GitRPC::Protocol::DGit.map_bert_error(error)
              when ::BERTRPC::BERTRPCError
                @delegate.on_route_error(route, ::GitRPC::Protocol::DGit.map_bert_error(error))
                # This was likely a problem with the single replica, so
                # continue trying on others.

                # Put the failed replica at the end of the route list, for
                # the sake of any future read operations on this rpc object.
                @read_routes = (@read_routes - [route]) + [route]

                if routes_remaining.empty?
                  # nothing more we can do here, so raise the error again:
                  raise error
                else
                  # since this was a comms error, we'll retry:
                  do_retry.call
                end
              else
                # This error was at the application level; raise it to
                # the caller without retrying:
                raise ::GitRPC::Protocol::DGit.map_bert_error(error)
              end
            end
          end

          do_retry.call # run the first "retry" to send to the first route
        end
      rescue => e
        p = Promise.new
        p.reject(e)
        p
      end
      private :async_send_message_single

      def send_message_multiple(message, type, args, kwargs)
        # answers is a hash from Route to answer; errors is a hash
        # from Route to exception.
        answers, errors = send_multiple(message, type, args, kwargs)

        result_collator = ResultCollator.new(@delegate, message, answers, errors)
        result_collator.decide_consensus.tap do
          if result_collator.unwritable_routes
            # Any route that was unreachable or had disagreeing errors
            # should be made unavailable for reads for the life of this
            # GitRPC object.  That helps provide "read your writes"
            # semantics: a read won't go to a route that previously missed
            # a write.
            new_read_routes = read_routes - result_collator.unwritable_routes

            # If we removed all the routes (that's a lot of failures),
            # keep the previous set.  We prefer to read from the replica
            # with the first N-1 writes and the last one dropped, rather
            # than one with a disjoint sequence.  Mostly arbitrary, but
            # it's usually better than throwing `UnroutedError`s here.
            unless new_read_routes.empty?
              @read_routes = new_read_routes
            end
          end
        end
      end
      private :send_message_multiple

      def async_send_message_multiple(message, type, args, kwargs)
        # answers is a hash from Route to answer; errors is a hash
        # from Route to exception.
        async_send_multiple(message, type, args, kwargs).then do |answers, errors|
          result_collator = ResultCollator.new(@delegate, message, answers, errors)
          result_collator.decide_consensus.tap do
            if result_collator.unwritable_routes
              # Any route that was unreachable or had disagreeing errors
              # should be made unavailable for reads for the life of this
              # GitRPC object.  That helps provide "read your writes"
              # semantics: a read won't go to a route that previously missed
              # a write.
              new_read_routes = read_routes - result_collator.unwritable_routes

              # If we removed all the routes (that's a lot of failures),
              # keep the previous set.  We prefer to read from the replica
              # with the first N-1 writes and the last one dropped, rather
              # than one with a disjoint sequence.  Mostly arbitrary, but
              # it's usually better than throwing `UnroutedError`s here.
              unless new_read_routes.empty?
                @read_routes = new_read_routes
              end
            end
          end
        end
      end
      private :async_send_message_multiple

      def send_message_multiple_through_spokesd(message, args, kwargs)
        resp = begin
          encoded_request = encode_bert_request(
            options.merge(timeout: timeout, connect_timeout: connect_timeout), args, kwargs
          )
          @delegate.legacy_gitrpc_writer(
            client_timeout,
            encoded_request[:options],
            message,
            encoded_request[:args],
            encoded_request[:kwargs],)
        rescue Faraday::TimeoutError
            raise GitRPC::Timeout.new("Faraday timed out")
        end
        answers, errors, all_routes = decode_bert_multiple_resp(resp)
        # let's make our results flow through the existing ResultCollator path
        result_collator = ResultCollator.new(GitrpcProxyDelegate.new(@delegate,all_routes), message, answers, errors)
        result_collator.decide_consensus.tap do
          if result_collator.unwritable_routes
            # Any route that was unreachable or had disagreeing errors
            # should be made unavailable for reads for the life of this
            # GitRPC object.  That helps provide "read your writes"
            # semantics: a read won't go to a route that previously missed
            # a write.
            new_read_routes = all_routes - result_collator.unwritable_routes

            # If we removed all the routes (that's a lot of failures),
            # keep the previous set.  We prefer to read from the replica
            # with the first N-1 writes and the last one dropped, rather
            # than one with a disjoint sequence.  Mostly arbitrary, but
            # it's usually better than throwing `UnroutedError`s here.
            unless new_read_routes.empty?
              @read_routes = new_read_routes
            end
          end
        end
      end
      private :send_message_multiple_through_spokesd

      def async_send_message_multiple_through_spokesd(message, args, kwargs)
        encoded_request = encode_bert_request(
          options.merge(timeout: timeout, connect_timeout: connect_timeout), args, kwargs
        )
        p = @delegate.async_legacy_gitrpc_writer(
          client_timeout,
          encoded_request[:options],
          message,
          encoded_request[:args],
          encoded_request[:kwargs],)

        p.then do |resp|
          answers, errors, all_routes = decode_bert_multiple_resp(resp)
          # let's make our results flow through the existing ResultCollator path
          result_collator = ResultCollator.new(GitrpcProxyDelegate.new(@delegate,all_routes), message, answers, errors)
          result_collator.decide_consensus.tap do
            if result_collator.unwritable_routes
              # Any route that was unreachable or had disagreeing errors
              # should be made unavailable for reads for the life of this
              # GitRPC object.  That helps provide "read your writes"
              # semantics: a read won't go to a route that previously missed
              # a write.
              new_read_routes = all_routes - result_collator.unwritable_routes

              # If we removed all the routes (that's a lot of failures),
              # keep the previous set.  We prefer to read from the replica
              # with the first N-1 writes and the last one dropped, rather
              # than one with a disjoint sequence.  Mostly arbitrary, but
              # it's usually better than throwing `UnroutedError`s here.
              unless new_read_routes.empty?
                @read_routes = new_read_routes
              end
            end
          end
        end
      end
      private :async_send_message_multiple_through_spokesd

      def send_multiple(message, type, args, kwargs)
        # Note that `write_routes` already ensures that its return
        # value includes at least a quorum of voters.
        if type == :write_routes
          routes = write_routes
        else
          routes = all_routes
        end

        if @delegate.use_fakerpc?
          fakerpc_send_multiple(routes, message, *args, **kwargs)
        else
          ::GitRPC::Protocol::BERTRPC.send_multiple(routes, message, args, kwargs,
                                                    options.merge(timeout: timeout, connect_timeout: connect_timeout))
        end
      end
      private :send_multiple

      def send_multiple_through_spokesd(message, args, kwargs)
        resp = begin
          encoded_request = encode_bert_request(
            options.merge(timeout: timeout, connect_timeout: connect_timeout), args, kwargs
          )
          @delegate.legacy_gitrpc_writer(
            client_timeout,
            encoded_request[:options],
            message,
            encoded_request[:args],
            encoded_request[:kwargs],)
        rescue Faraday::TimeoutError
          raise GitRPC::Timeout.new("Faraday timed out")
        end

        decode_bert_multiple_resp(resp)
      end
      private :send_multiple_through_spokesd

      def async_send_multiple(message, type, args, kwargs)
        # Note that `write_routes` already ensures that its return
        # value includes at least a quorum of voters.
        # `Promise.resolve.then` wraps so that the promise rejects if write_routes raises an exception,
        # and early exits by rejecting the promise chain, to match the sync version above.
        async_routes = Promise.resolve.then { type == :write_routes ? write_routes : all_routes }

        async_routes.then do |routes|
          if @delegate.use_fakerpc?
            kwargs = args.last.class == Hash ? args.pop : {}
            fakerpc_send_multiple(routes, message, *args, **kwargs)
          else
            ::GitRPC::Protocol::BERTRPC.async_send_multiple(routes, message, args, kwargs,
                                                            options.merge(timeout: timeout, connect_timeout: connect_timeout))
          end
        end
      end
      private :async_send_multiple

      # Send [message, args] to all of the routes via fakerpc. Return
      # the resulting answers and errors. This method does no error or
      # consistency checking.
      def fakerpc_send_multiple(routes, message, *args, **kwargs)
        answers = {}
        errors = {}

        routes.map do |route|
          Thread.new do # rubocop:disable GitHub/ThreadUse
            begin
              backend = ::GitRPC::Protocol.resolve("fakerpc:#{route.path}", options)
              answer = backend.send_message(message, *args, **kwargs)
              [route, answer, nil]
            rescue => e
              error = ::GitRPC::Protocol::BERTRPC.unify_bert_timeouts(e)
              [route, nil, error]
            end
          end
        end.map(&:value).each do |(route, answer, error)|
          if error
            errors[route] = error
          else
            answers[route] = answer
          end
        end

        [answers, errors]
      end
      private :fakerpc_send_multiple

      def self.map_bert_error(err)
        BERTRPC.map_error(err)
      end

      # Default repository scope cache key
      def repository_key
        Digest::SHA256.hexdigest(@delegate.shard_path)
      end

      # Use spokes checksum as part of reference cache key
      def repository_reference_key
        delegate.repository_reference_key
      end

      def disagreement_possible?
        true
      end

      # Route is private implementation of what we expect our DGit delgate to provide to us.
      # It should really only be used in tests where we don't want to introduce a dependency on
      # GitHub::DGit
      class Route
        attr_accessor :host, :port, :path
        attr_reader :original_host, :healthy

        def initialize(host, path, port: 8149, voting: true, healthy: true)
          @host, @path, @port, @voting, @healthy = host, path, port, voting, healthy
          @original_host = @host
        end

        # Return the most specific thing possible that we can connect to.
        #
        # Order of preference goes like this:
        # * IP address
        # * Full hostname
        # * Short hostname
        #
        # This type of route only knows the hostname, so return that.
        def resolved_host
          host
        end

        def fqdn
          "#{@host}.localdomain"
        end

        # This type of route doesn't know anything about datacenters
        def datacenter
          nil
        end

        def to_s
          "#{host}:#{port}"
        end

        def voting?
          @voting
        end

        def <=>(other)
          # Sort voting copies before nonvoting copies:
          [@voting ? 0 : 1, @host, @port] <=> [other.voting? ? 0 : 1, other.host, other.port]
        end
      end

      class ResultCollator
        attr_reader :unwritable_routes

        def initialize(delegate, message, answers, errors)
          @delegate = delegate
          @message = message
          @answers = answers
          @all_errors = errors
        end

        # Return the number of agreeing results that are needed for
        # success.
        def quorum
          @quorum ||= ::GitRPC::Backend.require_unanimous?(@message) ? @delegate.unanimous_quorum : @delegate.write_quorum
        end

        # Report then filter out any errors that strongly indicate
        # that the replica was offline. Store the result to @errors.
        def discard_offline_errors
          @errors = Hash[
            @all_errors.select { |route, error|
              if indicates_offline?(error)
                report_server_suspect(route, error)
                false
              else
                true
              end
            }
          ]

          # If *no* voting replicas remain, we're doomed; raise an
          # exception immediately:
          routes_remaining = @answers.keys + @errors.keys
          voter_count = routes_remaining.count(&:voting?)
          if voter_count == 0
            _, boom = @all_errors.find { |route, error| route.voting? }
            raise ::GitRPC::Protocol::DGit.map_bert_error(boom)
          end
        end

        # Return true iff error likely means that the corresponding
        # replica is offline.
        def indicates_offline?(error)
          error.is_a? ::BERTRPC::ConnectionError
        end

        # Check the raw (answers, errors) from the replicas to see
        # whether it is plausible that there is a consensus answer. If
        # not, call @delegate.on_disagreement if indicated and raise
        # either map_bert_error(error) or a ResponseError. Also, call
        # @delegate.on_error as necessary for any replicas that
        # returned errors.
        def check_consensus_plausible
          discard_offline_errors

          # We send write RPCs to unhealthy replicas on a best-effort basis.
          # There's no guarantee that a write which succeeded on an unhealthy
          # replica will stick around (since the repair process may end up
          # undoing it) so we don't want to include such replicas in the
          # quorum.
          answers = discard_unhealthy(@answers)
          errors = discard_unhealthy(@errors)

          voter_answers, nonvoter_answers = partition_results(answers)
          voter_errors, nonvoter_errors = partition_results(errors)

          # First consider only voters, to determine the consensus
          # answer/error and whether it is unanimous. Then report
          # dissenters, whether they be voting or non-voting.

          if voter_answers.empty?
            # All the voting replicas failed.
            num_error_types = voter_errors.values.map(&:class).uniq.length

            if num_error_types == 0
              # This can happen if all of the voters are unhealthy.
              raise response_error("No healthy voters")
            elsif num_error_types > 1
              # All voters returned errors, but the errors don't
              # agree. We don't do majority voting for errors, so
              # we're going to throw up our hands by raising a
              # ResponseError.

              report_disagreement

              # Report certain error-returning replicas as possibly
              # offline based on their error types:
              errors.each do |route, error|
                @delegate.on_app_error(route, ::GitRPC::Protocol::DGit.map_bert_error(error))
                (@unwritable_routes ||= []) << route
              end

              raise response_error("Disagreeing backend errors")
            elsif voter_errors.length < quorum
              # All voters returned matching errors, but they don't
              # amount to a quorum.

              unless nonvoter_answers.empty? &&
                     errors.values.map(&:class).uniq.length == 1
                report_disagreement
              end

              # Report certain error-returning replicas as possibly
              # offline based on their error types:
              errors.each do |route, error|
                @delegate.on_app_error(route, ::GitRPC::Protocol::DGit.map_bert_error(error))
                (@unwritable_routes ||= []) << route
              end

              raise response_error("Backend errors (no quorum)")
            else
              # All voters (constituting at least a quorum) returned
              # the same error. Raise that error (wrapped).
              boom = voter_errors.values.first

              unless nonvoter_answers.empty? &&
                     errors.values.map(&:class).uniq.length == 1
                report_disagreement
              end

              raise ::GitRPC::Protocol::DGit.map_bert_error(boom)
            end
          else
            # Someone succeeded, but not necessarily everyone. There's
            # no general way to roll anybody back, but most RPC
            # writers should be idempotent.

            # For the special case of `RebaseTimeout`, we have a
            # strict policy: if any replica times out, then we report
            # the timeout as the overall result of the RPC call. This
            # is because such a timeout can legitimately occur, but if
            # it does we don't want to try to update the corresponding
            # reference, because that will fail on the replicas that
            # weren't able to compute the rebase.
            errors.values.each do |error|
              if error.is_a?(::GitRPC::Backend::RebaseTimeout)
                raise ::GitRPC::Protocol::DGit.map_bert_error(error)
              end
            end

            # Other errors commonly indicate unreachable servers, so
            # report any error-emitting servers as suspect.
            errors.each do |route, error|
              @delegate.on_app_error(route, ::GitRPC::Protocol::DGit.map_bert_error(error))
              (@unwritable_routes ||= []) << route
            end

            # If answers don't constitute a quorum, we have a serious
            # problem:
            if voter_answers.length < quorum
              # Also report a disagreement if necessary:
              if !errors.empty?
                report_disagreement
              else
                simplifier = get_simplifier
                output = answers.values.map { |a| simplifier.call(a) }
                report_disagreement if output.uniq.length != 1
              end

              raise response_error("Backend insufficient quorum")
            end

            # We got a quorum of answers. That's all we require at
            # this stage, even though the answers might not agree with
            # each other.
          end
        end

        def report_server_suspect(route, error)
          @delegate.on_route_error(route, ::GitRPC::Protocol::DGit.map_bert_error(error))
          (@unwritable_routes ||= []) << route
        end

        def decide_consensus
          check_consensus_plausible

          answers = discard_unhealthy(@answers)
          errors = discard_unhealthy(@errors)

          voter_answers, nonvoter_answers = partition_results(answers)

          # answers are sometimes an array of just answer objects, like
          # [true, true] But sometimes they're spawn_git result hashes,
          # like {env=>..., pid=>..., out=>... }. In those cases, we
          # only want to compare the standard output, because pid and
          # environment are likely to differ. So grab the actual output
          # if it's a hash, before calling uniq.
          #
          # Even the output may differ in inconsequential ways, which we
          # handle here with `.gsub(...)`.
          simplifier = get_simplifier

          voter_output = voter_answers.values.map { |a| simplifier.call(a) }
          nonvoter_output = nonvoter_answers.values.map { |a| simplifier.call(a) }

          # Experiment time!  We should be stricter about our disagreement
          # checks, and include stderr in addition to exit code (status) and
          # stdout.  But we'll just trigger a warning to Failbot, instead
          # of raising a ResponseError, for now.
          strict_simplifier = get_simplifier(true)
          strict_voter_output = voter_answers.values.map { |a| strict_simplifier.call(a) }
          if voter_output.uniq.length != strict_voter_output.uniq.length
            @delegate.on_warning(response_error("Backend strict disagreement"))
          end

          # If there's an agreed-upon answer, return it.
          if voter_output.uniq.length == 1
            result = voter_answers.values.first

            unless nonvoter_output.all? { |o| o == voter_output.first } && errors.empty?
              report_disagreement
            end

            # If it's a call that's supposed to vary, concatenate the output.
            if ::GitRPC::Backend.output_varies?(@message)
              fail unless result.is_a?(Hash)
              result["out"] = combine_output(@answers, "out")
              result["err"] = combine_output(@answers, "err")
            end

            return result
          end

          # There's definitely disagreement, even among voting replicas.
          report_disagreement

          # If we get here, we had no automated way to deal with the variant
          # answers.  So throw a ResponseError.
          raise response_error("Backends disagreed")
        end

        def discard_unhealthy(results)
          results.reject { |route, v| !route.healthy }
        end

        # Partition `results`, a Hash {route => result}, into two
        # hashes, one for voting routes and one for nonvoting routes.
        # Return [voting_results, nonvoter_results].
        def partition_results(results)
          results.partition { |route, v| route.voting? }.map { |l| Hash[l] }
        end

        def get_simplifier(strict = false)
          if GitRPC::Backend.output_varies?(@message)
            return proc { |a| a["status"] }
          end

          case @message
          when :fetch
            proc { |a|
              out = a["out"].gsub(/\s+/, " ")	# collapse whitespace
              err = a["err"].gsub(/\s+/, " ")	# collapse whitespace
              { "out" => out, "err" => err }
            }
          when :create_merge_commit
            # Fileservers might not all have the same version of libicu. Differing
            # versions of libicu sometimes disagree about whether a file is binary
            # or text.
            #
            # Here, we disregard the ":binary" flag for each conflicted file when
            # checking answers for agreement. The fundamental difference is whether
            # there's a merge conflict, not whether the conflicted file is binary or
            # text.
            proc { |a|
              oid, result, conflicts = a
              if !strict && oid.nil? && result == "merge_conflict" && conflicts
                # Transform the :conflicted_files Hash from something that looks like this:
                #  {
                #    "any/file" => {
                #      :base => nil,
                #      :head => {:oid => "9ead9ead9ead9ead9ead9ead9ead9ead9ead9ead", :file_size => 123, :binary => true},
                #      :type => :regular_conflict
                #    }
                #  }
                # to something that looks like this:
                #  [
                #    ["any/file",
                #      [:base, nil],
                #      [:head, [ [:oid, "9ead9ead9ead9ead9ead9ead9ead9ead9ead9ead"], [:file_size, 123], [:binary, :ignore] ],
                #      [:type, :regular_conflict],
                #    ]
                #  ]
                conflict_summary = conflicts[:conflicted_files].map do |fn, conflict_data|
                  [fn, conflict_data.map { |side, info|
                    scrubbed_info = info.respond_to?(:map) ? info.map { |k, v| [k, k == :binary ? :ignore : v] } : info
                    [side, scrubbed_info]
                  }]
                end
                [oid, result, conflicts.merge(:conflicted_files => conflict_summary)]
              else
                # Ignore the DataDog stats, if any
                a = a[0, 4] if a.length > 4
                a
              end
            }
          when :stage_signed_merge_commit
            proc { |a|
              # Ignore the DataDog stats, if any
              a = a[0, 4] if a.length > 4
              a
            }
          when :persist_signed_merge_commit
            proc { |a|
              # Ignore the DataDog stats, if any
              a = a[0, 4] if a.length > 4
              a
            }
          when :rebase_tmp_objdir_experiment
            proc { |a|
              # Ignore the DataDog stats, if any
              a = a[0, 1] if a.length > 1
              a
            }
          else
            # No simplification:
            proc { |a| a }
          end
        end

        def combine_output(answers, key)
          if answers.values.map { |hash| hash[key] }.uniq.size == 1
            return answers.values.first[key]
          end

          answers.map { |route, hash|
            if hash[key]
              "[#{::GitRPC::Protocol::DGit.format_route(route)}]\n#{hash[key]}"
            else
              nil
            end
          }.compact.join("\n\n")
        end

        def report_disagreement
          @delegate.on_disagreement(@answers, @all_errors)
        end

        def response_error(msg)
          ::GitRPC::Protocol::DGit::ResponseError.new(msg, answers: @answers, errors: @all_errors, rpc_operation: @message)
        end
      end
    end
  end
end
