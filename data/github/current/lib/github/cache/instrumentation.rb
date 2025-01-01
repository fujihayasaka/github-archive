# typed: true
# frozen_string_literal: true

class GitHub::Cache::Client
  class << self
    delegate :query_time, :query_time=, :query_count, :query_count=,
             :query_tracing, :query_tracing=, :query_sets, :query_sets=,
             :query_hits, :query_hits=, :query_misses, :query_misses=,
             :query_events, :query_events=, :track_events, :track_events=,
             :distributed_tracing_enabled, :distributed_tracing_enabled=,
      to: :collector
  end

  def self.query_keys
    [query_sets.keys, query_hits.keys, query_misses.keys].flatten.uniq.sort
  end

  def self.collector
    GitHub::DataCollector::CacheInstrumenterCollector.get_instance
  end
end

module GitHub
  module Cache
    module Instrumentation
      module QueryKey
        [:set, :async_set, :add, :async_add].each do |op|
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{op}(key, *args, &block)
              super(key, *args, &block)
            ensure
              GitHub::Cache::Client.query_sets[key] += 1
            end
          RUBY
        end

        def get(key, *args, &block)
          val = super
        ensure
          if val
            GitHub::Cache::Client.query_hits[key] += 1
          else
            GitHub::Cache::Client.query_misses[key] += 1
          end if $!.nil?
        end

        def async_get(key, *args, &block)
          super.then do |response|
            if response.exist?
              GitHub::Cache::Client.query_hits[response.key] += 1
            else
              GitHub::Cache::Client.query_misses[response.key] += 1
            end
            response
          end
        end

        def get_multi(keys, *args, &block)
          val = super
        ensure
          keys.each do |key|
            if val[key]
              GitHub::Cache::Client.query_hits[key] += 1
            else
              GitHub::Cache::Client.query_misses[key] += 1
            end
          end unless val.nil?
        end

        def async_get_multi(keys, *args, &block)
          super.then do |result|
            keys.each do |key|
              if result[key]
                GitHub::Cache::Client.query_hits[key] += 1
              else
                GitHub::Cache::Client.query_misses[key] += 1
              end
            end
            result
          end
        end
      end

      module Aggregate

        # skip storing stack traces when operation takes less than 1 ms
        MINIMUM_INSTRUMENTATION_LATENCY = 1 / 1_000

        [:decr, :incr, :get, :get_multi, :set, :add, :replace, :delete, :prepend, :append].each do |op|
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{op}(*args, &block)
              if (prev = GitHub::Cache::Client.query_tracing) == false
                GitHub::Cache::Client.query_tracing = true
                start = Time.now
              end

              super(*args, &block)
            ensure
              if prev == false
                latency = Time.now - start
                key = args.first.to_s

                if GitHub::Cache::Client.track_events
                  event = {
                    operation: "#{op}",
                    key: key,
                    latency: latency,
                    locations: latency >= MINIMUM_INSTRUMENTATION_LATENCY ? caller_locations(2) : [],
                  }
                  GitHub::Cache::Client.query_events.push(event)
                end

                GitHub::Cache::Client.query_time += latency
                GitHub::Cache::Client.query_count += 1
                GitHub::Cache::Client.query_tracing = prev
              end
            end
          RUBY
        end

        [:async_decr, :async_incr, :async_get, :async_set, :async_add, :async_replace, :async_delete, :async_prepend, :async_append].each do |op|
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{op}(*args, &block)
              span = nil
              if (prev = GitHub::Cache::Client.query_tracing) == false
                GitHub::Cache::Client.query_tracing = true
                start = Time.now
              end

              on_resolve = -> {
                if prev == false
                  latency = Time.now - start
                  key = args.first.to_s

                  if GitHub::Cache::Client.track_events
                    event = {
                      operation: "#{op}",
                      key: key,
                      latency: latency,
                      locations: latency >= MINIMUM_INSTRUMENTATION_LATENCY ? caller_locations(2) : [],
                    }
                    GitHub::Cache::Client.query_events.push(event)
                  end

                  GitHub::Cache::Client.query_time += latency
                  GitHub::Cache::Client.query_count += 1
                  GitHub::Cache::Client.query_tracing = prev

                  span&.finish
                end
              }

              on_fulfill = ->(resolution) {
                on_resolve.call
                resolution
              }

              on_reject = ->(ex) {
                on_resolve.call
                raise ex
              }

              super(*args, &block).then(on_fulfill, on_reject)
            end
          RUBY
        end
      end

      module Tracing
        [:decr, :incr, :get, :get_multi, :set, :add, :replace, :delete, :prepend, :append,
         :async_decr, :async_incr, :async_get, :async_set, :async_add, :async_replace, :async_delete, :async_prepend, :async_append,
         :reset].each do |op|
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{op}(*args, &block)
              catalog_service = GitHub.context[:catalog_service] || "unknown"
              if GitHub::Cache::Client.distributed_tracing_enabled
                span = GitHub.tracer.start_span("#{op}", kind: :client, attributes: {
                  "db.system" => "memcached",
                  GitHub::TaggingHelper::CATALOG_SERVICE_TAG => catalog_service
                  })
              end
              super(*args, &block)
            ensure
              span&.finish
            end
          RUBY
        end

      end

      include QueryKey
      include Aggregate
      include Tracing
    end
  end
end
