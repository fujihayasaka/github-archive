# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module Export
    class DataQuery
      extend T::Helpers
      extend T::Sig
      include GitHub::Memoizer
      include GitHub::SecurityCenter::LoggingHelper
      abstract!

      class DataLimitExceededError < StandardError; end

      sig { returns(User) }; attr_reader :user
      sig { returns(T.any(Organization, Business)) }; attr_reader :scope

      PAGE_SIZE = 1000
      REPO_LIMIT = 50_000

      sig do
        params(
          user: User,
          scope: T.any(Organization, Business),
        )
        .void
      end
      def initialize(user:, scope:)
        @user = user
        @scope = scope
      end

      sig do
        params(list_data_query: T.any(Coverage::ListDataQuery, Risk::ListDataQuery)).
        returns(T::Array[T.any(SecurityCenter::Coverage::ExportDataQuery::RepositoryRowResult, SecurityCenter::Risk::ExportDataQuery::RepositoryRowResult)])
      end
      def run(list_data_query:)
        repository_data = T.let([], T::Array[T.any(SecurityCenter::Coverage::ExportDataQuery::RepositoryRowResult, SecurityCenter::Risk::ExportDataQuery::RepositoryRowResult)])

        team_id_to_slug = T.cast(scope, Organization)
          .visible_teams_for(user, fields: [:id, :slug])
          .pluck(:id, :slug)
          .to_h

        # Get the total item/page counts once before the loop starts
        paging_counts = list_data_query.counts
        total_entries = paging_counts.total_entries
        total_pages = paging_counts.total_pages

        page = 1
        loop do
          list_items = list_data_query.run(page: page).list_items

          if (page == 1 && total_entries > REPO_LIMIT) || repository_data.size > REPO_LIMIT
            raise DataLimitExceededError,
              "Your export request includes too many repositories. Please filter to fewer than #{ActiveSupport::NumberHelper.number_to_delimited(REPO_LIMIT)} and try again."
          end

          repo_ids = list_items.map { |list_item| list_item.repo_metadata.id }

          topic_names_by_repository_id = {}
          if list_items.present?
            topic_names_by_repository_id = self.class.get_topics_by_repository_id(repo_ids)
          end

          team_slugs_by_repository_id = {}
          if list_items.present?
            team_slugs_by_repository_id = self.class.get_teams_by_repository_id(repo_ids, team_id_to_slug, scope, page)
          end

          list_items.each do |list_item|
            name_with_display_owner = scope.is_a?(Organization) ? "#{scope.display_login}/#{list_item.repo_metadata.name}" : list_item.repo_metadata.name
            topics = topic_names_by_repository_id[list_item.repo_metadata.id] || []
            teams = team_slugs_by_repository_id[list_item.repo_metadata.id]&.compact || []

            GitHub.dogstats.distribution("security_center.export.topics_per_repo", topics.size)

            repository_data << create_repo_row_result(name_with_display_owner, list_item, topics, teams)
          end

          break if page >= total_pages

          page += 1
        end

        log_info(
          "Queried data",
          "gh.security_center.export.pages": page - 1,
          "gh.security_center.export.page_size": Export::DataQuery::PAGE_SIZE,
          "gh.security_center.export.rows": repository_data.size,
        )

        repository_data
      end

      sig do
        abstract
        .params(name_with_display_owner: String, list_item: T.untyped, topics: T::Array[String], teams: T::Array[String])
        .returns(T.any(SecurityCenter::Coverage::ExportDataQuery::RepositoryRowResult, SecurityCenter::Risk::ExportDataQuery::RepositoryRowResult))
      end
      def create_repo_row_result(name_with_display_owner, list_item, topics, teams); end

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
                  team_by_repo_id[subject_id] = team_by_repo_id[subject_id].sort.first(SecurityCenter::Risk::ExportCsvGenerator::TEAM_COUNT_CAP)
                end
              end
              batch += 1
            end
        end

        team_by_repo_id
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
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
