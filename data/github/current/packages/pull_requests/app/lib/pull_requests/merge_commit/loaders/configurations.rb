# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    # Perform the bulk of the read operations on our dependencies in a single location. Ensure we're performing as many
    # batch operations as possible.
    module Loaders
      module Configurations
        extend T::Sig

        sig { params(repository: Repository).returns(Configuration) }
        def self.build(repository)
          Configuration.new(
            # TODO: This should be a configuration with a default, that can be overrided per Repository.
            batch_size: GitHub.flipper[:size_of_batchable_mcr_jobs].percentage_of_time_value.to_i.clamp(1, 100),

            rebase_timeout: begin
              ENV["REBASE_TIMEOUT_SECONDS"]&.to_i ||
                (GitHub.flipper[:rebase_timeout_1sec].enabled? ? 1 : 7)
            end,

            skip_rebase: begin
              repository.feature_enabled?(:merge_commit_request_skip_rebase_via_api) &&
                !repository.merge_commit_allowed? &&
                !repository.rebase_merge_allowed?
            end
          )
        end
      end
    end
  end
end
