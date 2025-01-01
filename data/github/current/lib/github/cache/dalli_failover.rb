# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "dalli"
require "failbot"

class Dalli::DalliError
  attr_accessor :memcached_key
end

class Dalli::ValueOverMaxSize < Dalli::DalliError
  def needs_redacting?
    true
  end
end

module GitHub
  module Cache
    # The DalliFailover module is supposed to be a close copy of the GitHub::Cache::Failover.
    # It uses the same logic, but replaces the set of expected errors with the ones returned by
    # the Dalli gem.
    module DalliFailover
      extend T::Helpers
      requires_ancestor { ICacheConfig }
      include Kernel

      # These errors are ignored and not retried.
      IGNORABLE = [
        Dalli::ValueOverMaxSize,
        Dalli::NotPermittedMultiOpError,
        Dalli::MarshalError,
        Dalli::UnmarshalError
      ]

      # These errors trigger the retry and failover logic.
      RETRYABLE = [
        Dalli::NetworkError,
      ]

      MAX_VALUE_SIZE = 1024 * 1023

      # Main retry, ejection, and error swallowing logic. The retriable
      # argument determines whether the operation should be retried after
      # a server has been evicted.
      def failover(retriable = true)
        retries ||= 0
        yield
      rescue Dalli::RingError
        retries ||= 0
        if retries < 100
          retries = 100
          record_error $!, "memcached dead: #{$!.to_s[0..1023]}. failing over.", retried: true
          retry if retriable
        else
          record_error $!, "memcached dead: #{$!.to_s[0..1023]} and was not evicted. bailing."
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

      def perform_failover_async(key = nil, retriable = true, retries = 0, &block)
        # run the block, capturing exceptions as rejections
        result = block.call

        # handle errors the same way as above. rather than 'retry', we return
        # another promise that does the same thing with a higher retries value.
        result.rescue do |ex|
          case ex
          when Dalli::RingError
            if retries < 100
              retries = 100
              record_error ex, "memcached dead: #{ex.to_s[0..1023]}. failing over.", retried: true
              next perform_failover_async(key, retriable, retries, &block) if retriable
              next nil if key.nil?
              next ::GitHub::Cache::FakeResponse.new(key: key, value: nil, exists: false)
            else
              record_error ex, "memcached dead: #{ex.to_s[0..1023]} and was not evicted. bailing."
              next nil if key.nil?
              next ::GitHub::Cache::FakeResponse.new(key: key, value: nil, exists: false)
            end
          when *RETRYABLE
            if retries < options[:server_failure_limit]
              retries += 1
              record_error ex, "memcached error: #{ex.class} #{ex.to_s[0..1023]} (retry ##{retries})", retried: true
              next perform_failover_async(key, retriable, retries, &block)
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
      rescue => boom # rubocop:todo Lint/GenericRescue
        raise if raw
        delete(key)
        nil
      end

      def async_get(key, raw = false)
        p = perform_failover_async(key) { super }
        p.rescue do |err|
          raise err if raw
          async_delete(key).then do
            ::GitHub::Cache::FakeResponse.new(key: key, value: nil, exists: false)
          end
        end
      end

      def set(key, value, ttl = 0, raw = false)
        ttl ||= 0 # for GitRPC::Cache
        failover do
          raise augment_error(Dalli::ValueOverMaxSize.new("#{key} size is #{value.size}"), key) if value_to_big?(value)
          super
        end
      end

      def async_set(key, value, ttl = 0, raw = false)
        ttl ||= 0 # for GitRPC::Cache
        perform_failover_async(key) do
          raise augment_error(Dalli::ValueOverMaxSize.new("#{key} size is #{value.size}"), key) if value_to_big?(value)
          super
        end
      end

      def add(key, value, ttl = 0, raw = false)
        failover do
          raise augment_error(Dalli::ValueOverMaxSize.new("#{key} size is #{value.size}"), key) if value_to_big?(value)
          super
        end
      end

      def async_add(key, value, ttl = 0, raw = false)
        perform_failover_async(key) do
          raise augment_error(Dalli::ValueOverMaxSize.new("#{key} size is #{value.size}"), key) if value_to_big?(value)
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
        rescue => boom # rubocop:todo Lint/GenericRescue
          raise if raw
        end

        # If we did get here, we failed loading all keys in one batch,
        # either due to some memcache error or due to an unmarshal error.
        #
        # Let's retry loading each key individually, and clean up any
        # broken data along they way.
        keys.each_with_object({}) do |key, hash|
          hash.update(failover { super([key], raw) } || {})
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
              raise err
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

      def record_error(error, message, retried: false)
        catalog_service = GitHub.context[:catalog_service] || "unknown"
        if !retried
          logger.error({
            :exception => error,
            "db.system" => "memcached",
            "gh.client" => "dalli",
            "Body" => message,
            "gh.catalog_service" => catalog_service,
          }) if logger
        end

        # increment stats instead of sending a haystack exception in some
        # non-fatal warning / noise cases
        case error
        when Dalli::ValueOverMaxSize
          GitHub.dogstats.increment("rpc.memcached.error.value-too-big")
        when Dalli::RingError
          GitHub.dogstats.increment("rpc.memcached.error.server-evicted")
        when *RETRYABLE
          GitHub.dogstats.increment("rpc.memcached.error.retry")
        when *IGNORABLE
          GitHub.dogstats.increment("rpc.memcached.error.ignored")
        else
          Failbot.report(error, note: message)
        end

      rescue => boom # rubocop:todo Lint/GenericRescue
        begin
          GitHub.dogstats.increment("rpc.memcached.error.unexpected")
        rescue # rubocop:todo Lint/GenericRescue
          # never fail
        end
      end

      def value_to_big?(value)
        value.respond_to?(:to_str) && value.bytesize > MAX_VALUE_SIZE
      end

      private

      # Override check_return_code so we can store the key on the error.
      def check_return_code(ret, key = nil)
        super
      rescue Dalli::DalliError => e
        raise augment_error(e, key)
      end

      def augment_error(error, key)
        error.memcached_key = key if error.respond_to?(:memcached_key=)
        error
      end
    end
  end
end
