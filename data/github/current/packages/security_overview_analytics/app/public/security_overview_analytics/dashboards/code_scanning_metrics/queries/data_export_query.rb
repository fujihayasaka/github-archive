# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class DataExportQuery < AbstractQuery
          extend T::Helpers
          include GitHub::SecurityCenter::TenantFilteringHelper

          class ListItem < T::Struct
            const :repository_id, Integer
            const :repository_nwo, String
            const :pull_request_id, Integer
            const :pull_request_number, Integer
            const :pull_request_url, T.nilable(String)
            const :alert_number, Integer
            const :severity, T.nilable(String)
            const :rule_sarif_identifier, String
            const :created_at, Time
            const :updated_at, Time
            const :resolved_at, T.nilable(Time)
            const :resolved_reason, T.nilable(String)
            const :has_autofix, T::Boolean
            const :autofix_accepted, T::Boolean
            const :repository_visibility, String
            const :repository_archived, T::Boolean
            const :repository_teams, T::Array[String]
            const :repository_topics, T::Array[String]
            const :repository_properties, T::Hash[String, T.nilable(T.any(String, T::Array[String]))]
          end

          class Result < T::Struct
            const :items, T::Array[ListItem]
            const :next, T.nilable(String)

            delegate :size, to: :items
          end

          class Cursor < T::Struct

            const :repository_id, Integer, default: 0
            const :pull_request_id, Integer, default: 0
            const :alert_number, Integer, default: 0

            sig { returns(String) }
            def to_s
              JSON.dump(self.serialize)
            end

            sig { params(value: String).returns(Cursor) }
            def self.from_string(value)
              hash = JSON.parse(value).symbolize_keys
              new(**hash)
            end
          end

          PAGE_SIZE = 1000

          sig do
            params(
              scope: T.any(::Business, ::Organization),
              user: ::User,
              repos_filterer: ReposFilterer,
              alerts_filterer: PullRequestAlertsFilterer,
              start_date: ::Date,
              end_date: ::Date,
            ).void
          end
          def initialize(scope:, user:, repos_filterer:, alerts_filterer:, start_date:, end_date:)
            super
            @scope = scope
            @user = user
          end

          sig { params(cursor: T.nilable(String)).returns(Result) }
          def perform(cursor: nil)
            query = CodeScanningPullRequestAlert
              .where(repository_id: @repos_filterer.cs_repo_metadata_rel.select(:repository_id))
              .where(date_id: Date.id_from_date(@start_date)..Date.id_from_date(@end_date))
              .then { |rel| @alerts_filterer.apply(rel) }
              .includes(:repository_metadata)
              .order(:repository_id, :pull_request_id, :alert_number)
              .limit(PAGE_SIZE + 1) # to know if there's more

            if cursor
              cursor = Cursor.from_string(cursor)
              query = query
                .where(%{
                  (
                    `#{CodeScanningPullRequestAlert.table_name}`.`repository_id`,
                    `#{CodeScanningPullRequestAlert.table_name}`.`pull_request_id`,
                    `#{CodeScanningPullRequestAlert.table_name}`.`alert_number`
                  ) > (?, ?, ?)}.squish,
                  cursor.repository_id,
                  cursor.pull_request_id,
                  cursor.alert_number
                )
            end

            db_results = query.to_a
            return Result.new(items: []) if db_results.empty?

            repo_ids = db_results.map { |row| row[:repository_id] }.uniq
            repos = Repositories::Public.load_repositories(repo_ids)
              .preload(:owner)
              .then { |rel| apply_tenant_filter(rel) }
            repos_by_id = repos.index_by(&:id)

            teams_by_id = repos.map(&:owner).uniq
              .flat_map do |organization|
                organization
                  .visible_teams_for(@user, fields: [:id, :slug])
                  .pluck(:id, :slug)
              end
              .to_h

            teams_by_repo_id = ::SecurityCenter::Export::DataQuery.get_teams_by_repository_id(repo_ids, teams_by_id, @scope, 1)
            topics_by_repo_id = ::SecurityCenter::Export::DataQuery.get_topics_by_repository_id(repo_ids)
            props_by_repo_id = Repositories.domain.custom_properties.repo_properties(repos, :effective).transform_keys(&:id)

            pull_requests_by_id = ::PullRequest
              .where(id: db_results.map(&:pull_request_id).uniq)
              .index_by(&:id)

            items = T.let([], T::Array[ListItem])
            is_last_page = T.let(true, T::Boolean)

            query.each_with_index do |alert, index|
              if index >= PAGE_SIZE
                is_last_page = false
                next # stop once we hit the page limit
              end

              alert = T.cast(alert, CodeScanningPullRequestAlert)
              repository_metadata = T.must(alert.repository_metadata)

              repository = repos_by_id[alert.repository_id]
              # If we can't link the repository, it may have been deleted or
              # otherwise removed by tenant filtering.
              next if repository.nil?

              alert_resolution = if alert.alert_resolved?
                CodeScanningAlertRevision::RESOLUTIONS_MAPPING
                  .find do |_, values|
                    values.include?(alert.alert_resolution)
                  end
                  &.first
                  &.to_s
              end

              pull_request = T.cast(pull_requests_by_id[alert.pull_request_id], ::PullRequest)

              items << ListItem.new(
                repository_id: alert.repository_id,
                repository_nwo: repository.name_with_display_owner,
                pull_request_id: alert.pull_request_id,
                pull_request_number: pull_request.number,
                pull_request_url: pull_request.permalink,
                alert_number: alert.alert_number,
                severity: alert.alert_severity&.downcase,
                rule_sarif_identifier: alert.rule_sarif_identifier,
                created_at: alert.alert_created_at.to_time,
                updated_at: alert.alert_updated_at.to_time,
                resolved_at: alert.alert_resolved_at&.to_time,
                resolved_reason: alert_resolution,
                has_autofix: alert.has_autofix || false,
                autofix_accepted: alert.autofix_accepted || false,
                repository_visibility: repository_metadata.visibility,
                repository_archived: repository_metadata.archived?,
                repository_teams: teams_by_repo_id[alert.repository_id] || [],
                repository_topics: topics_by_repo_id[alert.repository_id] || [],
                repository_properties: props_by_repo_id[alert.repository_id] || {},
              )
            end

            next_cursor = unless is_last_page
              last_item = T.must(items.last) # the last one we're going to return
              Cursor.new(
                repository_id: last_item.repository_id,
                pull_request_id: last_item.pull_request_id,
                alert_number: last_item.alert_number,
              )
            end

            Result.new(
              items: items,
              next: next_cursor&.to_s,
            )
          end

          private

          sig { params(items: ActiveRecord::Relation).returns(T::Array[::Repository]) }
          def apply_tenant_filter(items)
            request_scope = @scope.is_a?(::Business) ? :business : :organization
            filter_tenant_rows(
              RequestScope.new(request_scope, @scope, "codeql-report-export"),
              items,
              -> (r) { r.id }
            ).first
          end
        end
      end
    end
  end
end
