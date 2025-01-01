# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module Helpers
      module ModelDelay
        include Kernel

        CAN_WRITE_CACHE_TTL = 1.second

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
        def check_model_replication_delay!(model, role = :writing)
          # This is a quick and clumsy approach at utilizing Freno#check? in order to allow DB migrations to
          # remove throttling without having to increase the replication delay threshold from github/github#378520
          # and should be removed once github/octoshift#10714 ships. Downstream metrics, reports, code paths will
          # report 9999ms as the replication delay when the cluster is not in a state to be written to.
          if FeatureFlag.vexi.enabled?(:octoshift_freno_check_hack, default: false)
            can_write = GitHub.cache.fetch(can_write_cache_key(model), ttl: CAN_WRITE_CACHE_TTL) do
              can_write?(model)
            end

            raise Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay.new(9999, role) unless can_write
          else
            delay = model_replication_delay(model)
            if delay
              raise Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay.new(delay, role)
            end
          end
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
          3.times.any? do |attempt|
            Kernel.sleep(attempt * 2 / 10.0)

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
          return 1250 if FeatureFlag.vexi.enabled?(:octoshift_1250_max_replication_delay, default: false)
          return 1500 if FeatureFlag.vexi.enabled?(:octoshift_1500_max_replication_delay, default: false)
          return 2000 if FeatureFlag.vexi.enabled?(:octoshift_2000_max_replication_delay, default: false)
          return 3000 if FeatureFlag.vexi.enabled?(:octoshift_3000_max_replication_delay, default: false)
          return 4000 if FeatureFlag.vexi.enabled?(:octoshift_4000_max_replication_delay, default: false)
          GitHub.octoshift_freno_max_replication_delay_ms
        end
      end
    end
  end
end
