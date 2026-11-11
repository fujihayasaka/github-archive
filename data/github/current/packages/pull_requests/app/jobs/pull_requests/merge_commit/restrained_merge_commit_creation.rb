# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module RestrainedMergeCommitCreation
      extend ActiveSupport::Concern

      private

      # Max concurrency of merge commit creation jobs, per Repository.
      MAX_CONCURRENT = 50

      # The lifespan of the rate limit count. If not queried within this span, we restart
      # the rate limit count from 0 concurrent processes.
      #
      # This should be kept at a value greater than the wait for the `UnableToLock` retry
      # plus the max sum of the time for all the related git operations inside the. As we
      # don't have a known firm value for this, we will go with something we believe should
      # be large enough in most cases.
      RATE_LIMITER_TTL = T.let(30.seconds.to_i, Integer)

      sig { params(repository: Repository, block: T.proc.void).void }
      def with_restraint(repository, &block)
        restraint = GitHub::Restraint.new

        lock_key = "pull-requests-create-commits-job:#{repository.id}"

        concurrency = if repository.feature_flag_enabled_or_raise?(:cprmc_half_concurrency) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          (MAX_CONCURRENT / 2).to_i
        else
          MAX_CONCURRENT
        end

        restraint.lock!(lock_key, concurrency, RATE_LIMITER_TTL) { yield }
      end
    end
  end
end
