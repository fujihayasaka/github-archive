# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Initialization
    module Repositories
      class RepoMetadataJob < BaseJob
        queue_as :security_overview_analytics_repository_initialization

        # Don't enqueue if metadata already exists for the repository
        around_enqueue do |_, block|
          if SecurityOverviewAnalytics::Repository.where(repository_id: repository_id).exists?
            GitHub.logger.info("RepoMetadata already exists for repository")
            GitHub.dogstats.increment(
              "security_overview_analytics.initialization.repo_metadata.skipped",
              tags: all_stats_tags + ["reason:metadata_already_exists"]
            )
            clear_lock
            next
          end

          block.call
        end

        sig { override.params(repository_id: Integer).void }
        def perform(repository_id:)
          upsert_payload = repository_payload
          SecurityOverviewAnalytics::Repository.throttle_writes_with_retry(max_retry_count: 5, err_msg: "Upserting SecurityOverviewAnalytics::Repository in #{self.class}.") do
            SecurityOverviewAnalytics::Repository.upsert(upsert_payload, on_duplicate: :skip)
          end
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        memoize def repository_payload
          {
            archived: repository.archived?,
            event_time: now,
            name: repository.name,
            organization_id: owner.id,
            owner_type: repository.owner_type,
            pushed_at: repository.pushed_at,
            repository_id:,
            visibility: repository.visibility,
          }.tap do |payload|
            # The column is currently required, so we're recording 0 for users
            payload[:organization_id] = 0 if repository.owner_type.downcase == "user"

            payload[:business_id] = BusinessResolver.resolve_for(repository)&.id
            payload[:owner_id] = owner.id
          end
        end
      end
    end
  end
end
