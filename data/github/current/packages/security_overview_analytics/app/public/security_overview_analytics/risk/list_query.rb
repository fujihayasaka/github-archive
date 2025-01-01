# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Risk
    class ListQuery < AbstractQuery
      include GitHub::Memoizer

      Item = ::SecurityCenter::Risk::RepositoryListComponent::ListItemData
      RepoMetadata = ::SecurityCenter::Coverage::RepositoryMetadataComponent::Data
      AlertCountData = ::SecurityCenter::Risk::RepositoryAlertCountComponent::Data

      class Result < T::Struct
        const :items, T::Array[Item]

        # temporary alias to ease switching over
        sig { returns(T::Array[Item]) }
        def list_items; items end
      end

      sig { params(page: Integer, page_size: Integer).returns(Result) }
      def perform(page: 1, page_size: 25)
        return Result.new(
          items: [],
        ) if visible_features.empty?

        GitHub.dogstats.distribution_time("security_center.risk_list_data_query.run.dist", tags: datadog_tags) do
          query_data(page:, page_size:)
        end
      end

      sig { params(page: Integer, page_size: Integer).returns(Result) }
      def query_data(page: 1, page_size: 25)
        query = Repository
          .joins(:feature_status_summary) # inner join
          .eager_load(:feature_status_summary) # include in single query
          .where(repository_id: @repos_filterer.any_feature_repo_metadata_rel.select(:repository_id))
          .then { |rel| @features_filterer.apply(rel) }
          .then { |rel| sort.apply(rel) }
          .then { |rel| include_user_repos? ? rel.preload(repository: [:internal_repository]) : rel }
          .then { |rel| rel.preload(repository: [:parent_advisory, :owner]) } # For 'repo' and 'repo.advisory_workspace?' and the repo's organization
          .then do |rel|
            # total_entries=-1 - sentinel value to keep `WillPaginate` from running its `count` query
            rel.paginate(page:, per_page: page_size, total_entries: -1)
          end

        items = query
          .then { |rel| rel.to_a }
          .then { |rows| next apply_tenant_filter(rows), rows.total_entries }
          .then { |rows, total| next to_list_view_models(rows), total }
          # Wrap in a WillPaginate; some downstream things expect total_pages/total_entries properties
          .then { |view_models, total| WillPaginate::Collection.create(page, page_size, total) { |pager| pager.replace view_models } }

        Result.new(
          items:,
        )
      end

      private

      sig { returns(Filters::FeatureStatusSummary::SortBy) }
      memoize def sort
        @parser.sort_by.then { |sort_option, _| Filters::FeatureStatusSummary::SortBy.new(sort_option) }
      end

      sig { params(rows: T::Array[Repository]).returns(T::Array[Item]) }
      def to_list_view_models(rows)
        if include_user_repos?
          repos = rows.map(&:repository).compact
          fgp = SecretScanning::AccessControl::FineGrainedPermissions
          locked_repos = fgp.get_unlockable_user_repos(@user, repos)
        end

        items = rows.map do |row|
          display_name = \
            if @scope.is_a?(Business)
              row.repository&.name_with_display_owner
            else
              row.repository&.name
            end

          repository_href = \
            if row.repository&.advisory_workspace?
              UrlHelpers.repository_path(row.repository&.owner_display_login, row.repository)
            else
              UrlHelpers.repository_security_overview_path(row.repository&.owner_display_login, row.repository)
            end

          visibility_href = \
            if @scope.is_a?(::Business)
              UrlHelpers.security_center_coverage_enterprise_path(@scope, { query: @parser.add_or_replace(RiskQueryParser::VISIBILITY, row.visibility) })
            else
              UrlHelpers.security_center_coverage_path(@scope, { query: @parser.add_or_replace(RiskQueryParser::VISIBILITY, row.visibility) })
            end

          repo_locked = locked_repos&.include?(row.repository_id) || false

          repo_metadata = RepoMetadata.new(
            id: T.must(row.repository_id),
            name: display_name,
            href: repository_href,
            visibility: row.visibility,
            visibility_href:,
            repo_locked:,
            archived: row.archived,
            ghas_enabled: row.feature_status_summary&.advanced_security_status == "ENABLED",
            updated_at: row.pushed_at,
            is_advisory_workspace: !!row.repository&.advisory_workspace?,
          )

          feature_summaries = {
            dependabot_alerts: {
              status: row.feature_status_summary&.dependabot_alerts_status,
              alert_count: row.feature_status_summary&.dependabot_alerts_total_count,
              href: UrlHelpers.repository_alerts_path(row.repository&.owner_display_login, row.repository),
            },
            code_scanning: {
              status: row.feature_status_summary&.code_scanning_alerts_status,
              alert_count: row.feature_status_summary&.code_scanning_alerts_total_count,
              href: UrlHelpers.repository_code_scanning_results_path(row.repository&.owner_display_login, row.repository),
            },
            secret_scanning: {
              status: row.feature_status_summary&.secret_scanning_alerts_status,
              alert_count: row.feature_status_summary&.secret_scanning_alerts_total_count,
              href: UrlHelpers.repository_token_scanning_results_path(row.repository&.owner_display_login, row.repository),
            }
          }

          repo_alert_count_map = visible_features.each_with_object({}) do |feature, h|
            # Is the user allowed to see these alerts for this repository?
            next unless can_see_alerts?(row, feature)
            # Does Security Overview support this feature for this repository?
            next unless eligible_for_alerts?(row, feature)
            # We only show alerts when the feature is enabled
            next if feature_summaries.dig(feature, :status) == "NOT_ENABLED"

            h[feature] = AlertCountData.new(
              feature: feature_display_name_for(feature),
              alert_count: feature_summaries.dig(feature, :alert_count),
              href: feature_summaries.dig(feature, :href),
              repo_id: T.must(row.repository_id),
              repo_locked:,
            )
          end

          Item.new(
            repo_metadata:,
            repo_alert_count_map:,

            # TODO: remove this AR model from DTO once export has a separate query
            owner: T.must(row.repository&.owner),
          )
        end
      end

      sig { override.returns(T::Array[String]) }
      memoize def datadog_tags
        tags = super
        tags << "sort_by:#{sort.sort_option}"
        tags
      end
    end
  end
end
