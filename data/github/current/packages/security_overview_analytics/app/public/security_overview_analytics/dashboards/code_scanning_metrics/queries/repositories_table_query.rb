# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class RepositoriesTableQuery < AbstractQuery
          extend T::Helpers
          include GitHub::SecurityCenter::TenantFilteringHelper

          class ListItem < T::Struct
            const :id, String
            const :display_name, String
            const :href, String
            const :count_unresolved, Integer
            const :count_dismissed, Integer
            const :count_fixed_without_autofix, Integer
            const :count_fixed_with_autofix, Integer
          end

          class Result < T::Struct
            const :items, T::Array[ListItem]
            const :previous, T.nilable(String)
            const :next, T.nilable(String)
          end

          class SortField < T::Enum
            enums do
              UNRESOLVED = new("countUnresolved")
              DISMISSED = new("countDismissed")
              FIXED_WO_AUTOFIX = new("countFixedWithoutAutofix")
              FIXED_AUTOFIX = new("countFixedWithAutofix")
            end
          end

          class SortDirection < T::Enum
            enums do
              ASC = new("asc")
              DESC = new("desc")
            end
          end

          sig do
            override
              .params(
                scope: T.any(::Business, ::Organization),
                user: ::User,
                repos_filterer: ReposFilterer,
                alerts_filterer: PullRequestAlertsFilterer,
                start_date: ::Date,
                end_date: ::Date,
              )
              .void
          end
          def initialize(scope:, user:, repos_filterer:, alerts_filterer:, start_date:, end_date:)
            super
            @scope = scope

            # not controllable from client
            @page_size = T.let(10, Integer)
          end

          sig do
            params(
              cursor: String,
              sort_field: T.nilable(SortField),
              sort_direction: T.nilable(SortDirection),
            ).returns(Result)
          end
          def perform(cursor:, sort_field:, sort_direction:)
            sort_field = sort_field || SortField::UNRESOLVED
            sort_direction = sort_direction || SortDirection::DESC

            offset = T.let(Integer(cursor, exception: false), T.nilable(Integer))
            raise ArgumentError, "Unexpected `cursor` input." if offset.nil? || offset < 0

            query = CodeScanningPullRequestAlert
              .where(repository_id: @repos_filterer.cs_repo_metadata_rel.select(:repository_id))
              .where(date_id: Date.id_from_date(@start_date)..Date.id_from_date(@end_date))
              .then { |rel| @alerts_filterer.apply(rel) }
              .select(
                Arel.sql("`#{CodeScanningPullRequestAlert.table_name}`.`repository_id`"),
                Arel.sql(%{
                  SUM(IF(
                    `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 0
                  , 1, 0)) as `count_unresolved`
                }.squish),
                Arel.sql(%{
                  SUM(IF(
                    `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 1
                    AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolution` IS NOT NULL
                  , 1, 0)) AS `count_dismissed`
                }.squish),
                Arel.sql(%{
                  SUM(IF(
                    `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 1
                    AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolution` IS NULL
                    AND `#{CodeScanningPullRequestAlert.table_name}`.`autofix_accepted` = 0
                  , 1, 0)) AS `count_fixed_without_autofix`
                }.squish),
                Arel.sql(%{
                  SUM(IF(
                    `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolved` = 1
                    AND `#{CodeScanningPullRequestAlert.table_name}`.`alert_resolution` IS NULL
                    AND `#{CodeScanningPullRequestAlert.table_name}`.`autofix_accepted` = 1
                  , 1, 0)) AS `count_fixed_with_autofix`
                }.squish),
              )
              .group(:repository_id)
              .limit(@page_size + 1) # to know if there's more
              .offset(offset)

            # Dynamic sorting
            # Include repository as secondary sort for stability
            sort_field_sym = sort_field.serialize.underscore.to_sym
            sort_dir_sym = sort_direction == SortDirection::ASC ? :asc : :desc
            query = query.order(sort_field_sym => sort_dir_sym, :repository_id => sort_dir_sym)

            db_results = ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(query)
              .map { |row| row.to_hash.symbolize_keys }

            repository_ids = db_results.map { |row| row[:repository_id] }.uniq
            repos_by_id = Repositories::Public.load_repositories(repository_ids)
              .preload(:owner, :parent_advisory)
              .then { |rel| apply_tenant_filter(rel) }
              .index_by(&:id)

            items = T.let([], T::Array[ListItem])
            is_last_page = T.let(true, T::Boolean)

            db_results.each_with_index do |row, index|
              if index >= @page_size
                is_last_page = false
                next # stop once we hit the page limit
              end

              repository = repos_by_id[row[:repository_id]]
              # If we can't link the repository, it may have been deleted or
              # otherwise removed by tenant filtering.
              next if repository.nil?

              items << ListItem.new(
                id: row[:repository_id]&.to_s,
                display_name: repository_display_name(repository),
                href: repository_href(repository),
                count_unresolved: row[:count_unresolved]&.to_i || 0,
                count_dismissed: row[:count_dismissed]&.to_i || 0,
                count_fixed_without_autofix: row[:count_fixed_without_autofix]&.to_i || 0,
                count_fixed_with_autofix: row[:count_fixed_with_autofix]&.to_i || 0,
              )
            end

            previous_page = offset <= @page_size ? 0 : offset - @page_size unless offset.zero?
            next_page = is_last_page ? nil : offset + @page_size
            Result.new(
              items:,
              previous: previous_page&.to_s,
              next: next_page&.to_s
            )
          end

          private

          sig { params(repository: ::Repository).returns(String) }
          def repository_display_name(repository)
            return repository.name_with_display_owner if @scope.is_a?(::Business)
            T.must(repository.name)
          end

          sig { params(repository: ::Repository).returns(String) }
          def repository_href(repository)
            return UrlHelpers.repository_path(repository.owner_display_login, repository) if repository.advisory_workspace?
            UrlHelpers.repository_security_overview_path(repository.owner_display_login, repository)
          end

          sig { params(items: ActiveRecord::Relation).returns(T::Array[::Repository]) }
          def apply_tenant_filter(items)
            request_scope = @scope.is_a?(::Business) ? :business : :organization
            filter_tenant_rows(
              RequestScope.new(request_scope, @scope, "codeql-report"),
              items,
              -> (r) { r.id }
            ).first
          end
        end
      end
    end
  end
end
