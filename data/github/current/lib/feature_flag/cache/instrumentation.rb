# typed: true
# frozen_string_literal: true

module FeatureFlag
  module Cache
    module Instrumentation
      module QueryKey
        [:set, :add].each do |op|
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{op}(key, *args, &block)
              super(key, *args, &block)
            ensure
              FeatureFlag::Cache::MemcachedClient.query_sets[key] += 1
            end
          RUBY
        end

        def get(key, *args, &block)
          val = super
        ensure
          if val
            FeatureFlag::Cache::MemcachedClient.query_hits[key] += 1
          else
            FeatureFlag::Cache::MemcachedClient.query_misses[key] += 1
          end if $!.nil?
        end

        def get_multi(keys, *args, &block)
          val = super
        ensure
          keys.each do |key|
            if val[key]
              FeatureFlag::Cache::MemcachedClient.query_hits[key] += 1
            else
              FeatureFlag::Cache::MemcachedClient.query_misses[key] += 1
            end
          end unless val.nil?
        end
      end

      module Aggregate

        # skip storing stack traces when operation takes less than 1 ms
        MINIMUM_INSTRUMENTATION_LATENCY = 1 / 1_000

        [:decr, :incr, :get, :get_multi, :set, :add, :replace, :delete, :prepend, :append].each do |op|
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{op}(*args, &block)
              if (prev = FeatureFlag::Cache::MemcachedClient.query_tracing) == false
                FeatureFlag::Cache::MemcachedClient.query_tracing = true
                start = Time.now
              end

              super(*args, &block)
            ensure
              if prev == false
                latency = Time.now - start
                key = args.first.to_s

                if FeatureFlag::Cache::MemcachedClient.track_events
                  event = {
                    operation: "#{op}",
                    key: key,
                    latency: latency,
                    locations: latency >= MINIMUM_INSTRUMENTATION_LATENCY ? caller_locations(2) : [],
                  }
                  FeatureFlag::Cache::MemcachedClient.query_events.push(event)
                end

                FeatureFlag::Cache::MemcachedClient.query_time += latency
                FeatureFlag::Cache::MemcachedClient.query_count += 1
                FeatureFlag::Cache::MemcachedClient.query_tracing = prev
              end
            end
          RUBY
        end
      end

      module Tracing
        [:decr, :incr, :get, :get_multi, :set, :add, :replace, :delete, :prepend, :append,
         :reset].each do |op|
          class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{op}(*args, &block)
              catalog_service = GitHub.context[:catalog_service] || "unknown"
              # Note: This is using GitHub::Cache::Client to check if tracing is enabled to match the behavior we
              # are inheriting from GitHub::Cache::Failover so error spans reported from there are associated consistently.
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
