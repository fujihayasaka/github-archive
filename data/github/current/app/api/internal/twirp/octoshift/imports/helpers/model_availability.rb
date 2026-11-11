# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module Helpers
      module ModelAvailability
        include Kernel

        # Public: Helper method check for excessive replication delay.
        #
        # model - An ActiveRecord::Base subclass.
        #
        # Returns nil or delay in milliseconds if excessive replication delay.
        def model_replication_delay(model)
          delay = model.default_replication_wait
          delay > max_replication_delay ? delay : nil
        end

        # Public: Helper method to raise an error if excessive replication delay.
        #
        # model - An ActiveRecord::Base subclass.
        # role  - Indicating :reading or :writing used for reporting.
        #
        # Returns nil.
        # Raises Errors::HighReplicationDelay if excessive replication delay.
        def check_model_replication_delay!(model, role)
          delay = model_replication_delay(model)

          if delay
            raise Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay.new(delay, role)
          end
        end

        def check_datastore_available_for_writes!(model)
          can_write = GitHub.cache.fetch(can_write_cache_key(model), ttl: can_write_cache_ttl) do
            can_write?(model)
          end

          raise Api::Internal::Twirp::Octoshift::Errors::DatastoreUnavailableForWrites.new(:writing) unless can_write
        end

        # Public: Helper method to wrap a new Replica.
        #
        # klass - An ActiveRecord::Base subclass.
        #
        # Returns a new Replica.
        def replica(klass)
          Replica.new(klass)
        end

        private

        def can_write?(model)
          can_write_attempts.times.any? do |attempt|
            Kernel.sleep(can_write_sleep_time(attempt))

            model.throttler_cluster_names.all? do |cluster_name|
              Freno.client.check?(app: :octoshift, store_name: cluster_name)
            end
          end
        rescue Freno::Error
          false
        end

        def can_write_cache_key(model)
          "twirp:octoshift:model_delay:can_write:#{model.name.underscore}"
        end

        # How long to wait for replication delay before requeuing a job to retry
        # later, in miliseconds. This is based on the 95th percentile for indexing job
        # runs (~1sec), and the goal is to balance job throughput when waiting for
        # replication delay.
        #
        # This value is set in vault using the `OCTOSHIFT_MAX_REPLICATION_DELAY_MS` key
        def max_replication_delay
          GitHub.octoshift_freno_max_replication_delay_ms
        end

        def can_write_cache_ttl
          case
          when FeatureFlag.vexi.enabled?(:octoshift_11980_5s_ttl, default: false)
            5.seconds
          when FeatureFlag.vexi.enabled?(:octoshift_11980_10s_ttl, default: false)
            10.seconds
          else
            1.second
          end
        end

        def can_write_attempts
          case
          when FeatureFlag.vexi.enabled?(:octoshift_11980_5_attempts, default: false)
            5
          else
            3
          end
        end

        def can_write_sleep_time(attempt)
          case
          when FeatureFlag.vexi.enabled?(:octoshift_11980_sleep_more, default: false)
            attempt * 4 / 10.0
          when FeatureFlag.vexi.enabled?(:octoshift_11980_sleep_much_more, default: false)
            attempt * 6 / 10.0
          else
            attempt * 2 / 10.0
          end
        end
      end
    end
  end
end
