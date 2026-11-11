# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module Export
    class DataQuery
      extend T::Helpers
      include GitHub::Memoizer
      include GitHub::SecurityCenter::LoggingHelper

      abstract!

      PAGE_SIZE = 1000

      sig { params(repo_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[String]]) }
      def self.get_topics_by_repository_id(repo_ids)
        # Try w/o batching:
        topic_names_by_repository_id = RepositoryTopic.names_for(
          repository_ids: repo_ids,
          limit_per_repo: RepositoryTopic::LIMIT_PER_REPOSITORY,
        )

        return topic_names_by_repository_id if topic_names_by_repository_id&.values.flatten.size < RepositoryTopic::DEFAULT_APPLIED_TO_LIMIT

        # Batch if necessary:
        batch_size = (RepositoryTopic::DEFAULT_APPLIED_TO_LIMIT / RepositoryTopic::LIMIT_PER_REPOSITORY).floor

        topic_names_by_repository_id = {}
        repo_ids.each_slice(batch_size) do |batch|
          topic_names = RepositoryTopic.names_for(
            repository_ids: batch,
            limit_per_repo: RepositoryTopic::LIMIT_PER_REPOSITORY,
          )
          topic_names_by_repository_id.merge!(topic_names || {})
        end

        topic_names_by_repository_id
      end

      sig { params(repo_ids: T::Array[Integer], team_id_to_slug: T::Hash[Integer, String], scope: T.any(Organization, Business), page: Integer).returns(T::Hash[Integer, T::Array[String]]) }
      def self.get_teams_by_repository_id(repo_ids, team_id_to_slug, scope, page)
        team_by_repo_id = {}

        # This query is at risk of out-of-memory errors, so we're doing everything we can to limit memory usage
        batch = 1
        Ability.uncached do
          Ability
            .where(
              actor_type: "Team",
              subject_type: "Repository",
              subject_id: repo_ids,
              action: [:admin, :write]
            )
            .in_batches do |batch_abilities|
              batch_abilities.pluck(:actor_id, :subject_id).each do |actor_id, subject_id|
                team_by_repo_id[subject_id] ||= []
                if team_id_to_slug[actor_id]
                  team_by_repo_id[subject_id] << team_id_to_slug[actor_id]
                  team_by_repo_id[subject_id] = team_by_repo_id[subject_id].sort.first(SecurityCenter::Risk::ExportCsvGenerator::ELEMENT_COUNT_CAP)
                end
              end
              batch += 1
            end
        end

        team_by_repo_id
      rescue StandardError => e # rubocop:todo Lint/RescueException
        log_info(
          "Failed to query teams data",
          "gh.security_center.export.teams_query_batch": batch,
          "gh.security_center.export.team_by_repo_id_size": team_by_repo_id&.size,
          "gh.security_center.export.listdataquery_page": page,
        )
        raise e
      end
    end
  end
end
