# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Coverage
    class ExportQuery < AbstractQuery
      include GitHub::Memoizer
      include GitHub::SecurityCenter::TenantFilteringHelper

      PAGE_SIZE = 1000

      class ListItem < T::Struct
        const :name_with_display_owner, String
        const :owner_type, T.nilable(String)
        const :archived, T::Boolean
        const :updated_at, String
        const :visibility, String
        const :dependabot_alerts_status, T.nilable(String)
        const :dependabot_security_updates_status, T.nilable(String)
        const :code_scanning_alerts_status, T.nilable(String)
        const :code_scanning_pull_request_alerts_status, T.nilable(String)
        const :code_scanning_default_setup, T.nilable(String)
        const :secret_scanning_alerts_status, T.nilable(String)
        const :secret_scanning_push_protection_status, T.nilable(String)
        const :advanced_security_status, T.nilable(String)
        const :topics, T::Array[String]
        const :teams, T::Array[String]
        const :repository_properties, T::Hash[String, T.nilable(T.any(String, T::Array[String]))]
      end

      class Result < T::Struct
        const :items, T::Array[ListItem]
        const :total_pages, Integer
      end

      sig { params(page: Integer).returns(Result) }
      def perform(page: 1)
        return Result.new(
          items: [],
          total_pages: 0
        ) if visible_features.empty?

        GitHub.dogstats.distribution_time("security_center.coverage_export_data_query.run.dist", tags: datadog_tags) do
          query_data(page:)
        end
      end

      sig { params(page: Integer).returns(Result) }
      def query_data(page: 1)
        query = Repository
          .joins(:feature_status_summary) # inner join
          .eager_load(:feature_status_summary) # include in single query
          .where(repository_id: @repos_filterer.any_feature_repo_metadata_rel.select(:repository_id))
          .then { |rel| @features_filterer.apply(rel) }
          .then { |rel| sort.apply(rel) }
          .then { |rel| rel.preload(repository: [:owner]) } # For 'repo' and and the repo's organization
          .then { |rel| rel.paginate(page:, per_page: PAGE_SIZE) }

        items = query
          .then { |rel| rel.to_a }
          .then { |rows| next apply_tenant_filter(rows), rows.total_entries }
          .then { |rows, total| next to_list_view_models(rows), total }
          .then { |view_models, total| WillPaginate::Collection.create(page, PAGE_SIZE, total) { |pager| pager.replace view_models } }

        items = T.let(items, WillPaginate::Collection)

        Result.new(
          items:,
          total_pages: items.total_pages,
        )
      end

      private

      sig { returns(Filters::FeatureStatusSummary::SortBy) }
      memoize def sort
        # export should always sort by repository name
        Filters::FeatureStatusSummary::SortBy.new("repos")
      end

      sig { params(rel: T.any(WillPaginate::Collection, ActiveRecord::Relation)).returns(T::Array[Repository]) }
      def apply_tenant_filter(rel)
        request_scope = @scope.is_a?(::Business) ? :business : :organization
        filter_tenant_rows(
          RequestScope.new(request_scope, @scope, "coverage"),
          rel,
          -> (r) { r.repository_id }
        ).first
      end

      sig { params(rows: T::Array[Repository]).returns(T::Array[ListItem]) }
      def to_list_view_models(rows)
        repo_ids = rows.map { |row| T.must(row.repository_id) }.uniq
        repos = rows.map { |row| T.must(row.repository) }

        teams_by_id = rows.map { |row| T.must(row.repository).owner }.uniq
          .flat_map do |owner|
            next [] unless owner.is_a? Organization
            owner
              .visible_teams_for(@user, fields: [:id, :slug])
              .pluck(:id, :slug)
          end
          .to_h

        teams_by_repo_id = ::SecurityCenter::Export::DataQuery.get_teams_by_repository_id(repo_ids, teams_by_id, @scope, 1)
        topics_by_repo_id = ::SecurityCenter::Export::DataQuery.get_topics_by_repository_id(repo_ids)
        props_by_repo_id = \
          if ::SecurityCenter::FeatureFlagHelper.coverage_export_include_repo_properties?(@scope)
            ::CustomProperties::Public.repo_properties(repos.select { |r| r.owner&.organization? }, :effective).transform_keys(&:id)
          else
            {}
          end

        items = rows.map do |row|
          ListItem.new(
            name_with_display_owner: row.repository&.name_with_display_owner,
            owner_type: row.repository&.owner_type&.upcase,
            archived: row.archived,
            updated_at: row.pushed_at&.utc.to_s,
            visibility: row.visibility,
            advanced_security_status: status_display_name(row.feature_status_summary&.advanced_security_status),
            dependabot_alerts_status: status_display_name(row.feature_status_summary&.dependabot_alerts_status),
            dependabot_security_updates_status: status_display_name(row.feature_status_summary&.dependabot_security_updates_status),
            code_scanning_alerts_status: status_display_name(row.feature_status_summary&.code_scanning_alerts_status),
            code_scanning_pull_request_alerts_status: status_display_name(row.feature_status_summary&.code_scanning_pr_reviews_status),
            code_scanning_default_setup: status_display_name(row.feature_status_summary&.code_scanning_auto_codeql_status),
            secret_scanning_alerts_status: status_display_name(row.feature_status_summary&.secret_scanning_alerts_status),
            secret_scanning_push_protection_status: status_display_name(row.feature_status_summary&.secret_scanning_push_protection_status),
            topics: topics_by_repo_id[T.must(row.repository_id)] || [],
            teams: teams_by_repo_id[T.must(row.repository_id)] || [],
            repository_properties: props_by_repo_id[row.repository_id] || {},
          )
        end
      end

      sig { params(feature_status: T.nilable(String)).returns(T.nilable(String)) }
      def status_display_name(feature_status)
        return if feature_status.nil?

        case feature_status
        when "ENABLED"
          "enabled"
        when "NOT_ELIGIBLE"
          "ineligible"
        else
          "not-enabled"
        end
      end
    end
  end
end
