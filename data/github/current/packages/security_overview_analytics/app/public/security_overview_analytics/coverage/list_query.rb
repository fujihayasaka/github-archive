# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Coverage
    class ListQuery < AbstractQuery
      include GitHub::Memoizer
      include GitHub::SecurityCenter::TenantFilteringHelper

      Item = ::SecurityCenter::Coverage::RepositoryListComponent::ListItemData
      RepoMetadata = ::SecurityCenter::Coverage::RepositoryMetadataComponent::Data
      CoverageData = ::SecurityCenter::Coverage::RepositoryCoveragesComponent::Data

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

        GitHub.dogstats.distribution_time("security_center.coverage_list_data_query.run.dist", tags: datadog_tags) do
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

      sig { returns(T::Boolean) }
      def include_user_repos?
        @repos_filterer.is_a?(Dashboards::EnterpriseReposFilterer) && @repos_filterer.include_user_repos?
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

      sig { params(rows: T::Array[Repository]).returns(T::Array[Item]) }
      def to_list_view_models(rows)
        # preload repo configurations to avoid N+1 later when checking feature states
        repos = rows.map(&:repository).compact
        Configurable.preload_configuration(repos)

        if include_user_repos?
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
              UrlHelpers.security_center_coverage_enterprise_path(@scope, { query: @parser.add_or_replace(CoverageQueryParser::VISIBILITY, row.visibility) })
            else
              UrlHelpers.security_center_coverage_path(@scope, { query: @parser.add_or_replace(CoverageQueryParser::VISIBILITY, row.visibility) })
            end

          risk_href = \
            if @scope.is_a?(::Business)
              UrlHelpers.security_center_risk_enterprise_path(@scope, { query: "repo:#{row.name}" })
            else
              UrlHelpers.security_center_risk_path(@scope, { query: "repo:#{row.name}" })
            end

          repo_metadata = RepoMetadata.new(
            id: T.must(row.repository_id),
            name: display_name,
            href: repository_href,
            visibility: row.visibility,
            visibility_href:,
            repo_locked: locked_repos&.include?(row.repository_id) || false,
            archived: row.archived,
            ghas_enabled: row.feature_status_summary&.advanced_security_status == "ENABLED",
            updated_at: row.pushed_at,
            is_advisory_workspace: !!row.repository&.advisory_workspace?,
          )

          repo_coverages_list = [
            to_coverage_view_model(
              row.repository,
              :dependabot_alerts,
              {
                dependabot_alerts: row.feature_status_summary&.dependabot_alerts_status,
                dependabot_security_updates: row.feature_status_summary&.dependabot_security_updates_status,
                dependabot_version_updates: row.feature_status_summary&.dependabot_version_updates_status,
              }
            ),
            to_coverage_view_model(
              row.repository,
              :code_scanning,
              {
                code_scanning: row.feature_status_summary&.code_scanning_alerts_status,
                code_scanning_pr_reviews: row.feature_status_summary&.code_scanning_pr_reviews_status,
                code_scanning_auto_codeql: row.feature_status_summary&.code_scanning_auto_codeql_status,
              }
            ),
            to_coverage_view_model(
              row.repository,
              :secret_scanning,
              {
                secret_scanning: row.feature_status_summary&.secret_scanning_alerts_status,
                secret_scanning_push_protection: row.feature_status_summary&.secret_scanning_push_protection_status,
              }
            ),
          ].compact

          Item.new(
            repo_metadata:,
            repo_coverages_list:,

            # TODO: remove this AR model from DTO once export has a separate query
            owner: T.must(row.repository&.owner),
          )
        end
      end

      sig do
        params(
          repository: T.nilable(::Repository),
          primary_feature: Symbol,
          feature_statuses: T::Hash[Symbol, String]
        )
        .returns(T.nilable(CoverageData))
      end
      def to_coverage_view_model(repository, primary_feature, feature_statuses)
        return unless repository.present?
        return unless visible_features.include?(primary_feature)

        enabled_feature_types = feature_statuses
          .select { |_feature, status| status == "ENABLED" }
          .reject do |feature|
            feature == :dependabot_version_updates # hide subfeature from UI (github/security-center#1547)
          end
          .keys

        include_pseudo_features!(enabled_feature_types, primary_feature:, repository:)

        CoverageData.new(
          feature: feature_display_name_for(primary_feature),
          coverages: enabled_feature_types
            .sort_by { |f| feature_statuses.keys.index(f) || 0 }
            .map do |f|
              next "Security updates paused" if f == :dependabot_security_updates && repository.dependabot_updates_paused?
              coverage_display_name_for(f)
            end,
          no_coverages_reason: no_coverages_reason_for(primary_feature, repository),
          feature_statuses: feature_statuses
            .transform_values do |value|
              case (value)
              when "ENABLED"; "enrolled"
              when "NOT_ENABLED"; "not_enrolled"
              else value.downcase
              end
            end
        )
      end

      sig { params(feature: Symbol, repository: ::Repository).returns(String) }
      def no_coverages_reason_for(feature, repository)
        return "Not eligible" if repository.owner&.user? && [:code_scanning, :dependabot_alerts].include?(feature.to_sym)
        return "Needs setup" if feature == :code_scanning
        "Not enabled"
      end

      sig { params(repository: ::Repository).returns(T::Boolean) }
      def alert_secret_scanning_partners_enabled?(repository)
        return false unless GitHub.dotcom_request?
        repository.public?
      end

      sig { params(features: T::Array[Symbol], primary_feature: Symbol, repository: ::Repository).void }
      def include_pseudo_features!(features, primary_feature:, repository:)
        case primary_feature
        when :secret_scanning
          return unless alert_secret_scanning_partners_enabled?(repository)
          # Security center used to store secret scanning as enrolled for dotcom public repos where the public secret scanning feature was not available.
          # So we'll replace it with the pseudo feature :secret_scanning_partners.
          features.reject! { |f| f == :secret_scanning } unless SecretScanning::Features::Repo::TokenScanning.new(repository).feature_available?
          features << :secret_scanning_partners if features.exclude?(:secret_scanning)
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
