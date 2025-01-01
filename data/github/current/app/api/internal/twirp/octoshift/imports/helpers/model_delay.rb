# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Octoshift
  module Imports
    module Helpers
      module ModelDelay
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
        def check_model_replication_delay!(model, role = :writing)
          delay = model_replication_delay(model)
          if delay
            raise Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay.new(delay, role)
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

        # How long to wait for replication delay before requeuing a job to retry
        # later, in miliseconds. This is based on the 95th percentile for indexing job
        # runs (~1sec), and the goal is to balance job throughput when waiting for
        # replication delay.
        #
        # This value is set in vault using the `OCTOSHIFT_MAX_REPLICATION_DELAY_MS` key
        def max_replication_delay
          GitHub.octoshift_freno_max_replication_delay_ms
        end
      end
    end
  end
end
