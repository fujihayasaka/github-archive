# typed: false
# frozen_string_literal: true

require "memcached"
require "failbot"

class Memcached::Error
  attr_accessor :memcached_key
end

class Memcached::ValueTooBig < Memcached::Error
  def needs_redacting?
    true
  end
end

module GitHub
  module Cache
    # A variety of exceptions may be raised by the memcached library when
    # unmarshalling fails. This method wraps the mess of checking for them.
    #
    # boom - An exception to check.
    #
    # Returns true if the exception is likely due to an unmarshalling error.
    def self.unmarshal_error?(boom)
      ret = case boom
      when ArgumentError
        msg = boom.to_s
        msg.include?("undefined class") ||
          msg.include?("dump format error")
      when TypeError
        msg = boom.to_s
        msg.include?("needs to have method `_load'") ||
          msg.include?("needs to have method `marshal_load'") ||
          msg.include?("exception class/object expected") ||
          msg.include?("instance of IO needed")
      when NameError
        msg = boom.to_s
        msg.include?("uninitialized constant")
      when MessagePack::MalformedFormatError, MessagePack::UnknownExtTypeError
        true
      end

      GitHub.dogstats.increment("cache.unmarshal_error") if ret
      ret
    end

    # Mixin for Memcached::Rails that adds error swallowing and reliable
    # server failover. When a connection, read, or write error occurs,
    # the memcache operations take the following action:
    #
    #   - Retries the operation on the same server up to the configured
    #     server_failure_limit times (2 by default).
    #
    #   - If the retry limit is exceeded and the server was marked dead,
    #     the operation is attempted once more under the new server list.
    #
    #   - If the retry limit was exceeded and the server configuration
    #     did not change (e.g., only one server is available), nil is
    #     returned and the error is swallowed.
    #
    # When no servers are available, or in other rare cases where an
    # error is not retryable, the memcache operations do nothing and
    # return nil. The calling code should continue to function, though
    # without caching.
    #
    # This module must be included in a subclass of Memcached::Rails.
    module Failover
      include GitHub::Memoizer

      # These errors are ignored and not retried.
      IGNORABLE = [
        Memcached::ActionQueued,
        Memcached::NoServersDefined,
        Memcached::NotFound,
        Memcached::NotStored,
        Memcached::ValueTooBig,
        Memcached::ABadKeyWasProvidedOrCharactersOutOfRange,
      ]

      # These errors trigger the retry and failover logic.
      RETRYABLE = [
        # frequently occuring
        Memcached::ATimeoutOccurred,
        Memcached::ReadFailure,
        Memcached::ClientError,
        Memcached::HostnameLookupFailure,
        Memcached::ConnectionFailure,
        Memcached::SystemError,

        # weirdsies
        Memcached::ConnectionBindFailure,
        Memcached::ConnectionDataDoesNotExist,
        Memcached::ConnectionDataExists,
        Memcached::ConnectionSocketCreateFailure,
        Memcached::CouldNotOpenUnixSocket,
        Memcached::Failure,
        Memcached::FetchWasNotCompleted,
        Memcached::PartialRead,
        Memcached::ProtocolError,
        Memcached::ServerDelete,
        Memcached::ServerEnd,
        Memcached::ServerError,
        Memcached::SomeErrorsWereReported,
        Memcached::TheHostTransportProtocolDoesNotMatchThatOfTheClient,
        Memcached::UnknownReadFailure,
        Memcached::WriteFailure,
      ]

      MAX_VALUE_SIZE = 1024 * 1023

      # Main retry, ejection, and error swallowing logic. The overable
      # argument determines whether the operation should be retried after
      # a server has been evicted.
      def failover(overable = true)
        retries ||= 0
        yield
      rescue Memcached::NotFound, Memcached::NotStored
        nil
      rescue Memcached::ServerIsMarkedDead
        retries ||= 0
        if retries < 100
          retries = 100
          record_error $!, "memcached dead: #{$!.to_s[0..1023]}. failing over.", retried: true
          retry if overable
        else
          record_error $!, "memcached dead: #{$!.to_s[0..1023]} and was not evicted. bailing."
          if rand(100) < reset_percentage_value
            # Experiment: try resetting the memcached client struct, which should force it to reconnect to its current list of servers.
            reset
          end
          nil
        end
      rescue *RETRYABLE
        retries ||= 0
        if retries < options[:server_failure_limit]
          retries += 1
          record_error $!, "memcached error: #{$!.class} #{$!.to_s[0..1023]} (retry ##{retries})", retried: true
          retry
        else
          record_error $!, "memcached error: #{$!.class} #{$!.to_s[0..1023]} (swallowing)"
          nil
        end
      rescue *IGNORABLE
        record_error $!, "memcached error: #{$!.class} #{$!.to_s[0..1023]} (swallowing)"
        nil
      end

      def perform_failover_async(key = nil, overable = true, retries = 0, &block)
        # run the block, capturing exceptions as rejections
        result = block.call

        # handle errors the same way as above. rather than 'retry', we return
        # another promise that does the same thing with a higher retries value.
        result.rescue do |ex|
          case ex
          # these 2 errors are handled differently in the async variants
          # because we use response objects.
          when Memcached::NotFound
            next nil if key.nil?
            next ::GitHub::Cache::FakeResponse.new(key: key, value: nil, exists: false)
          when Memcached::NotStored
            next nil if key.nil?
            next ::GitHub::Cache::FakeResponse.new(key: key, value: nil, stored: false)
          when Memcached::ServerIsMarkedDead
            if retries < 100
              retries = 100
              record_error ex, "memcached dead: #{ex.to_s[0..1023]}. failing over.", retried: true
              next perform_failover_async(key, overable, retries, &block) if overable
              next nil if key.nil?
              next ::GitHub::Cache::FakeResponse.new(key: key, value: nil, exists: false)
            else
              record_error ex, "memcached dead: #{ex.to_s[0..1023]} and was not evicted. bailing."
              if rand(100) < reset_percentage_value
                # Experiment: try resetting the memcached client struct, which should force it to reconnect to its current list of servers.
                reset
              end
              next nil if key.nil?
              next ::GitHub::Cache::FakeResponse.new(key: key, value: nil, exists: false)
            end
          when *RETRYABLE
            if retries < options[:server_failure_limit]
              retries += 1
              record_error ex, "memcached error: #{ex.class} #{ex.to_s[0..1023]} (retry ##{retries})", retried: true
              next perform_failover_async(key, overable, retries, &block)
            else
              record_error ex, "memcached error: #{ex.class} #{ex.to_s[0..1023]} (swallowing)"
              next nil if key.nil?
              next ::GitHub::Cache::FakeResponse.new(key: key, value: nil, exists: false)
            end
          when *IGNORABLE
            record_error ex, "memcached error: #{ex.class} #{ex.to_s[0..1023]} (swallowing)"
            next nil if key.nil?
            next ::GitHub::Cache::FakeResponse.new(key: key, value: nil, exists: false)
          end

          # all other exceptions, we re-raise to fail the promise for real.
          raise ex
        end
      end

      # these methods trigger error swallowing and server eviction
      def get(key, raw = false)
        failover { super }
      rescue => boom # rubocop:todo Lint/RescueException
        raise if raw || !GitHub::Cache.unmarshal_error?(boom)
        # value could not be unmarshalled due to a class name change. delete the key
        # and return nil so it will be recached.
        delete(key)
        nil
      end

      def async_get(key, raw = false)
        p = perform_failover_async(key) { super }
        p.rescue do |err|
          raise err if raw || !GitHub::Cache.unmarshal_error?(err)
          # value could not be unmarshalled due to a class name change. delete the key
          # and return nil so it will be recached.
          async_delete(key).then do
            ::GitHub::Cache::FakeResponse.new(key: key, value: nil, exists: false)
          end
        end
      end

      def set(key, value, ttl = 0, raw = false)
        ttl ||= 0 # for GitRPC::Cache
        failover do
          if value_to_big?(value)
            GitHub.dogstats.increment("rpc.memcached.client.error.value-too-big")
            raise augment_error(Memcached::ValueTooBig.new("#{key} size is #{value.size} - #{value.bytesize} bytes"), key)
          end
          super
        end
      end

      def async_set(key, value, ttl = 0, raw = false)
        ttl ||= 0 # for GitRPC::Cache
        perform_failover_async(key) do
          if value_to_big?(value)
            GitHub.dogstats.increment("rpc.memcached.client.error.value-too-big")
            raise augment_error(Memcached::ValueTooBig.new("#{key} size is #{value.size} - #{value.bytesize} bytes"), key)
          end
          super
        end
      end

      def add(key, value, ttl = 0, raw = false)
        failover do
          if value_to_big?(value)
            GitHub.dogstats.increment("rpc.memcached.client.error.value-too-big")
            raise augment_error(Memcached::ValueTooBig.new("#{key} size is #{value.size} - #{value.bytesize} bytes"), key)
          end
          super
        end
      end

      def async_add(key, value, ttl = 0, raw = false)
        perform_failover_async(key) do
          if value_to_big?(value)
            GitHub.dogstats.increment("rpc.memcached.client.error.value-too-big")
            raise augment_error(Memcached::ValueTooBig.new("#{key} size is #{value.size} - #{value.bytesize} bytes"), key)
          end
          super
        end
      end

      # these don't make any sense to retry after the server
      # has been ejected from the list.
      def delete(*args)    failover(false) { super }   end
      def incr(*args)      failover(false) { super }   end
      def decr(*args)      failover(false) { super }   end
      def async_delete(key, *args)    perform_failover_async(key, false) { super }   end
      def async_incr(key, *args)      perform_failover_async(key, false) { super }   end
      def async_decr(key, *args)      perform_failover_async(key, false) { super }   end

      # multigets need special logic. if we get back a nil, fall back to
      # individual `get_multi` calls.
      def get_multi(keys, raw = false)
        begin
          result = failover { super(keys, raw) }
          return result if result
        rescue => boom # rubocop:todo Lint/RescueException
          raise if raw || !GitHub::Cache.unmarshal_error?(boom)
        end

        # If we did get here, we failed loading all keys in one batch,
        # either due to some memcache error or due to an unmarshal error.
        #
        # Let's retry loading each key individually, and clean up any
        # broken data along they way.
        keys.each_with_object({}) do |key, hash|
          begin
            hash.update(failover { super([key], raw) } || {})
          rescue => err # rubocop:todo Lint/RescueException
            raise unless GitHub::Cache.unmarshal_error?(err)
            delete(key)
          end
        end
      end

      def async_get_multi(keys, raw = false)
        p = perform_failover_async { super(keys, raw) }
        p = p.rescue do |err|
          raise err if raw || !GitHub::Cache.unmarshal_error?(err)
          nil
        end

        p.then do |result|
          next result if result

          # If we did get here, we failed loading all keys in one batch,
          # either due to some memcache error or due to an unmarshal error.
          #
          # Let's retry loading each key individually, and clean up any
          # broken data along they way.

          key_results = keys.map do |key|
            promise = async_get(key, raw).rescue do |err|
              raise err unless GitHub::Cache.unmarshal_error?(err)
              async_delete(key)
            end
            [key, promise]
          end.to_h

          Promise.all(key_results.values).then do
            keys.each_with_object({}) do |key, hash|
              # all promises should have succeeded to get here
              response = key_results[key].value
              hash[key] = response.value if response.exist?
            end
          end
        end
      end

      def reset(servers = nil)
        GitHub.dogstats.increment("rpc.memcached.reset", tags: ["cache_class:#{self.class.name.underscore}"])
        super(servers)
      end

      def record_error(error, message, retried: false)
        catalog_service = GitHub.context[:catalog_service] || "unknown"
        if GitHub::Cache::Client.distributed_tracing_enabled
          span = GitHub.tracer.start_span("error", kind: :client, attributes: {
            "db.system" => "memcached",
            "gh.client" => self.class.name.underscore,
            "exception.type" => error&.class&.name,
            GitHub::TaggingHelper::CATALOG_SERVICE_TAG => catalog_service,
            })
          span.add_event("exception", attributes: { "exception.type" => error&.class&.name, "exception.message" => message })
          span.status = OpenTelemetry::Trace::Status.error("memcached error")
        end
        if !retried
          logger.error({
            :exception => error,
            "db.system" => "memcached",
            "error.class" => error&.class&.name,
            "cache.key" => error.memcached_key,
            "Body" => message,
            "gh.catalog_service" => catalog_service,
            "gh.client" => self.class.name.underscore,
          }) if logger
        end

        # This variable is being set in this weird way so that, if we end up
        # with an uncaught error before the actual hostname value is retrieved,
        # we'll be able to output "unknown-hostname" in the method-wide `rescue`.
        hostname = "unknown-host"
        hostname_from_key = if error.respond_to?(:memcached_key)
          begin
            key = error.memcached_key
            if key.is_a? Array
              key = key[0]
            end
            if key.is_a? String
              server = server_by_key(key)

              if server.present?
                hostname_or_ip = server.split(":", 2).first

                # Graphite uses . as a separator, so convert the hostname's
                # separator from . to - so it can be used in a Graphite key
                # without any weirdness.
                hostname_or_ip.tr(".", "-") if hostname_or_ip.present?
              end
            end
          rescue Memcached::Error
            nil
          end
        end
        hostname = hostname_from_key || hostname
        span&.add_attributes({ "server.address" => hostname })

        # increment stats instead of sending a failbot exception in some
        # non-fatal warning / noise cases
        error_tags = error_stats_base_tags(catalog_service)
        case error
        when Memcached::ValueTooBig
          GitHub.stats.increment("memcached.error.value-too-big") if GitHub.enterprise?
          GitHub.dogstats.increment("rpc.memcached.error.value-too-big", tags: error_tags)
        when Memcached::ABadKeyWasProvidedOrCharactersOutOfRange
          Failbot.report(error, "exception.message": message)
        when Memcached::ServerIsMarkedDead
          evicted_server, evicted_server_count = last_evicted_server_and_count
          hostname = evicted_server.hostname if evicted_server
          hostname = hostname.tr(".", "-") if hostname.present?
          GitHub.stats.increment("memcached.#{hostname}.error.server-evicted") if GitHub.enterprise?
          GitHub.dogstats.increment("rpc.memcached.error.server-evicted", tags: ["rpc_host:#{hostname}"] + error_tags)
          log_eviction(error, catalog_service, evicted_server, evicted_server_count)
        when *RETRYABLE
          GitHub.stats.increment("memcached.#{hostname}.error.retry") if GitHub.enterprise?
          GitHub.dogstats.increment("rpc.memcached.error.retry", tags: ["rpc_host:#{hostname}", "exception.class:#{error&.class&.name}", "retried:#{retried}"] + error_tags)
        when *IGNORABLE
          GitHub.stats.increment("memcached.#{hostname}.error.ignored") if GitHub.enterprise?
          GitHub.dogstats.increment("rpc.memcached.error.ignored", tags: ["rpc_host:#{hostname}"] + error_tags)
        else
          Failbot.report(error, "exception.message": message)
        end

      rescue => boom # rubocop:todo Lint/RescueException
        begin
          GitHub.stats.increment("memcached.#{hostname}.error.unexpected") if GitHub.enterprise?
          GitHub.dogstats.increment("rpc.memcached.error.unexpected", tags: ["rpc_host:#{hostname}", "exception.class:#{boom.class}"] + error_stats_base_tags(catalog_service))
          logger.error({
            :exception => boom.exception,
            "db.system" => "memcached",
            "error.class" => boom.class.name,
            "cache.key" => boom.try(:memcached_key),
            "Body" =>  boom.to_s,
            "gh.catalog_service" => catalog_service,
            "gh.client" => self.class.name.underscore,
          }) if logger
        rescue # rubocop:todo Lint/RescueException
          # never fail
        end
      ensure
        span&.finish
      end

      def error_stats_base_tags(catalog_service)
        if !defined?(@_partition)
          @_partition = respond_to?(:current_partition) ? current_partition || "unknown" : "unknown"
        end

        [
          "catalog_service:#{catalog_service}",
          "cache_class:#{self.class.name.underscore}",
          "partition:#{@_partition}"
        ]
      end

      def value_to_big?(value)
        value.respond_to?(:to_str) && value.bytesize > MAX_VALUE_SIZE
      end

      private

      # Override check_return_code so we can store the key on the error.
      def check_return_code(ret, key = nil)
        super
      rescue Memcached::Error => e
        raise augment_error(e, key)
      end

      def augment_error(error, key)
        error.memcached_key = key if error.respond_to?(:memcached_key=)
        error
      end

      # The percentage of time we should try to reset the memcached client struct if it gets into a bad state.
      def reset_percentage_value
        return @reset_percentage_value if defined?(@reset_percentage_value)

        if ENV["STAFF_ENVIRONMENT"] == "review-lab"
          @reset_percentage_value = 100
        else
          @reset_percentage_value = ENV["GITHUB_MEMCACHED_RESET_PERCENTAGE"].to_i
        end
      end

      def log_eviction(error, catalog_service, evicted_server, evicted_server_count)
        return unless logger
        return unless sample_error?
        return unless evicted_server

        logger.error({
          :exception => error,
          "db.system" => "memcached",
          "error.class" => error&.class&.name,
          "Body" => "memcached client: server evicted.",
          "gh.catalog_service" => catalog_service,
          "gh.client" => self.class.name.underscore,
          "cache.client.id" => object_id,
          "cache.key" => error.memcached_key,
          "cache.eviction.count" => evicted_server_count,
          "cache.eviction.server" => "#{evicted_server.hostname}:#{evicted_server.port}",
        })
      end

      def last_evicted_server_and_count
        # count the evicted servers and find the most recent eviction
        evicted_server_count = 0
        evicted_server = nil
        now = Time.now
        servers.each do |server|
          next unless server.next_retry > now
          evicted_server_count += 1
          evicted_server = server if evicted_server.nil? || server.next_retry > evicted_server.next_retry
        end

        [evicted_server, evicted_server_count]
      end

      memoize def sample_error?
        # sample at a ~1/256 rate, since we see ~500 events/s and that would represent ~0.1% of total log traffic
        # the goal is to log all events for the lifetime of a subset of workers, with the expectation that we'll
        # end up with ~2 logs/s.
        client_identity = Digest::SHA256.hexdigest(object_id.to_s)
        client_identity.slice(0, 2) == "aa"
      end
    end
  end
end
