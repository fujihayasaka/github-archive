# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    class ListDataQuery
      include GitHub::Memoizer
      include GitHub::SecurityCenter::TenantFilteringHelper

      CoverageQueryParser = ::Search::Queries::SecurityCenter::CoverageQueryParser

      class Result < T::Struct
        const :list_items, T::Array[RepositoryListComponent::ListItemData]
        const :current_page, Integer
      end

      class CountsResult < T::Struct
        const :active_count, Integer
        const :archived_count, Integer
        const :total_entries, Integer
        const :total_pages, Integer
      end

      sig { returns(User) }; attr_reader :user
      sig { returns(T.nilable(UserSession)) }; attr_reader :user_session
      sig { returns(T.any(Organization, Business)) }; attr_reader :scope
      sig { returns(Integer) }; attr_reader :page_size
      sig { returns(CoverageQueryParser) }; attr_reader :parser
      sig { returns(T::Array[Organization]) }; attr_reader :organizations
      sig { returns(T.nilable(T::Array[Integer])) }; attr_reader :repo_ids

      sig do
        params(
          business: Business,
          organizations: T::Array[Organization],
          user: User,
          parser: CoverageQueryParser,
          page_size: Integer,
          user_session: T.nilable(UserSession)
        ).returns(T.attached_class)
      end
      def self.for_organizations(business:, organizations:, user:, parser:, page_size:, user_session: nil)
        new(user: user, scope: business, parser: parser, organizations: organizations, page_size: page_size, user_session: user_session)
      end

      sig do
        params(
          organization: Organization,
          user: User,
          parser: CoverageQueryParser,
          page_size: Integer,
          repo_ids: T.nilable(T::Array[Integer]),
          user_session: T.nilable(UserSession)
        ).returns(T.attached_class)
      end
      def self.for_organization(organization:, user:, parser:, page_size:, repo_ids: nil, user_session: nil)
        new(user: user, scope: organization, organizations: ([organization]), parser: parser, page_size: page_size, repo_ids: repo_ids, user_session: user_session)
      end

      private_class_method :new

      sig do
        params(
          user: User,
          scope: T.any(Organization, Business),
          page_size: Integer,
          parser: CoverageQueryParser,
          organizations: T.nilable(T::Array[Organization]),
          repo_ids: T.nilable(T::Array[Integer]),
          user_session: T.nilable(UserSession)
        )
        .void
      end
      def initialize(user:, scope:, page_size:, parser:, organizations: nil, repo_ids: nil, user_session: nil)
        @user = user
        @scope = scope
        @page_size = page_size
        @parser = parser
        @organizations = T.let(organizations || [], T::Array[Organization])
        @repo_ids = repo_ids
        @user_session = user_session
      end

      sig { params(page: Integer).returns(Result) }
      def run(page: 1)
        GitHub.dogstats.distribution_time("security_center.coverage_list_data_query.run.dist", tags: datadog_tags) do
          return Result.new(
            list_items: [],
            current_page: 0,
          ) if visible_features.empty?

          list_items = base_rel
            .then { |rel| sort.apply(rel) }
            .then { |rel| rel.select("#{default_configs_table_name}.*") }
            .then { |rel| emus_in_scope? ? rel.preload(repository: [:internal_repository]) : rel }
            .then { |rel| rel.preload(:repository_security_center_statuses) } # For coverages list
            .then { |rel| rel.preload(repository: [:parent_advisory, :owner]) } # For 'repo' and 'repo.advisory_workspace?' and the repo's organization
            .then do |rel|
              # total_entries=-1 - sentinel value to keep `WillPaginate` from running its `count` query
              rel.paginate(page: page, per_page: page_size, total_entries: -1).to_a
            end
            .then { |rows| next apply_tenant_filter(rows), rows.total_entries }
            .then { |rows, total| next view_model_for(rows), total }
            .then { |view_models, total| paginate_results(view_models, page: page, total: total) }

          Result.new(
            list_items:,
            current_page: page,
          )
        end
      end

      sig { returns(CountsResult) }
      def counts
        return CountsResult.new(
          active_count: 0,
          archived_count: 0,
          total_entries: 0,
          total_pages: 0,
        ) if visible_features.empty?

        repo_counts = base_rel.unscope(where: :archived)
          .select(
            Arel.sql("SUM(IF(#{default_configs_table_name}.archived = 1, 1, 0)) as total_archived_repos"),
            Arel.sql("SUM(IF(#{default_configs_table_name}.archived = 0, 1, 0)) as total_active_repos")
          )
          .first
        active_count = repo_counts&.total_active_repos&.to_i || 0
        archived_count = repo_counts&.total_archived_repos&.to_i || 0

        archived_filters, _ = parser.values_for_qualifier(CoverageQueryParser::ARCHIVED) # archived has no negative qualifier
        total_entries = if archived_filters.empty? || (archived_filters.include?("true") && archived_filters.include?("false"))
          archived_count + active_count
        elsif archived_filters.include?("true")
          archived_count
        else
          active_count
        end

        CountsResult.new(
          active_count:,
          archived_count:,
          total_entries:,
          total_pages: WillPaginate::Collection.new(1, page_size, total_entries).total_pages,
        )
      end

      # Return the Relation with filters applied, but without pagination or view model projection.
      sig { returns(ActiveRecord::Relation) }
      def all
        base_rel
      end

      private

      sig { returns(ActiveRecord::Relation) }
      memoize def base_rel
        base_where = if scope.is_a?(Business)
          RepositorySecurityCenterConfig
            .with_owners_under_business(scope, organizations, include_emus: emus_in_scope?)
        else
          RepositorySecurityCenterConfig.where(owner_id: organizations)
        end

        base_where.then do |rel|
          next rel if repo_ids.nil?
          rel.where(repository_id: repo_ids)
        end
        .then { |rel| filters.reduce(rel) { |r, filter| filter.apply(r) } }
      end

      sig { returns(T::Array[T.untyped]) }
      memoize def filters
        filters_list = T.let([
          Filters::ByRepository.new(*parser.values_without_qualifiers, substring_match: true, scope: scope),
          Filters::ByRepository.new(*parser.values_for_qualifier(CoverageQueryParser::REPOSITORY), scope: scope),
          Filters::ByVisibility.new(*parser.values_for_qualifier(CoverageQueryParser::VISIBILITY)),
          Filters::ByArchived.new(*parser.values_for_qualifier(CoverageQueryParser::ARCHIVED)),
          Filters::ByTeam.new(*parser.values_for_qualifier(CoverageQueryParser::TEAM), organizations: organizations, user: user),
          Filters::ByTopic.new(*parser.values_for_qualifier(CoverageQueryParser::TOPIC), organizations: organizations),
          Filters::ByGhas.new(*parser.values_for_qualifier(CoverageQueryParser::ADVANCED_SECURITY)),
          Filters::ByFeature.new(*parser.values_for_qualifier(CoverageQueryParser::CODE_SCANNING), feature: :code_scanning, scope: scope),
          Filters::ByFeature.new(*parser.values_for_qualifier(CoverageQueryParser::CODE_SCANNING_DEFAULT_SETUP), feature: :code_scanning_auto_codeql, scope: scope),
          Filters::ByFeature.new(*parser.values_for_qualifier(CoverageQueryParser::CODE_SCANNING_PR_ALERTS), feature: :code_scanning_pr_reviews, scope: scope),
          Filters::ByFeature.new(*parser.values_for_qualifier(CoverageQueryParser::DEPENDABOT_ALERTS), feature: :dependabot_alerts, scope: scope),
          Filters::ByFeature.new(*parser.values_for_qualifier(CoverageQueryParser::DEPENDABOT_SECURITY_UPDATES), feature: :dependabot_security_updates, scope: scope),
          Filters::ByFeature.new(*parser.values_for_qualifier(CoverageQueryParser::SECRET_SCANNING), feature: :secret_scanning, scope: scope),
          Filters::ByFeature.new(*parser.values_for_qualifier(CoverageQueryParser::SECRET_SCANNING_PUSH_PROTECTION), feature: :secret_scanning_push_protection, scope: scope),
        ], T::Array[T.untyped])

        additional_filters_list =
          if scope.is_a?(Business)
            [
              Filters::ByOwner.new(*parser.values_for_qualifier(CoverageQueryParser::OWNER), T.cast(scope, Business)),
              Filters::ByOwnerType.new(*parser.values_for_qualifier(CoverageQueryParser::OWNER_TYPE), T.cast(scope, Business))
            ]
          else
            [
              Filters::ByCustomProperty.new(
                allowed_repo_ids: repo_ids,
                org: T.cast(scope, Organization),
                query: parser.custom_properties_query_string,
                user: user,
                user_session: user_session
              )
            ]
          end
        filters_list.concat(additional_filters_list)

        filters_list.compact
      end

      sig { returns(SortBy) }
      memoize def sort
        parser.sort_by.then { |sort_option, _| SortBy.new(sort_option) }
      end

      sig { params(rel: WillPaginate::Collection).returns(T::Array[RepositorySecurityCenterConfig]) }
      def apply_tenant_filter(rel)
        request_scope = scope.is_a?(Organization) ? :organization : :business
        filter_tenant_rows(
          RequestScope.new(request_scope, scope, "coverage"),
          rel,
          -> (r) { r.repository_id }
        ).first
      end

      sig { params(results: T::Array[RepositorySecurityCenterConfig], page: Integer, total: Integer).returns(WillPaginate::Collection) }
      def paginate_results(results, page:, total:)
        WillPaginate::Collection.create(page, page_size, total) { |pager| pager.replace results }
      end

      sig { params(rel: T::Array[RepositorySecurityCenterConfig]).returns(T::Array[RepositoryListComponent::ListItemData]) }
      def view_model_for(rel)
        # preload repo configurations to avoid N+1 later when checking feature states
        repos = rel.map(&:repository).compact
        Configurable.preload_configuration(repos)

        if emus_in_scope?
          fgp = SecretScanning::AccessControl::FineGrainedPermissions
          locked_repos = fgp.get_unlockable_user_repos(user, repos)
        end

        rel.map do |info|
          repo = T.must(info.repository)
          name = scope.is_a?(Business) ? repo.name_with_display_owner : info.name

          repo_locked = locked_repos&.include?(repo.id) || false

          metadata = RepositoryMetadataComponent::Data.new(
            id: info.repository_id,
            name: name,
            href: repo_link(repo),
            visibility: T.must(info.visibility),
            visibility_href: generate_visibility_href(visibility: info.visibility),
            repo_locked:,
            archived: info.archived,
            ghas_enabled: info.ghas_enabled,
            updated_at: info.last_push,
            is_advisory_workspace: !!repo.advisory_workspace?,
          )

          coverages_list = info.repository_security_center_statuses.then do |statuses|
            statuses_by_primary_feature = statuses.group_by do |status|
              RepositorySecurityCenterStatus.primary_feature_for(status.feature_type)
            end

            visible_features.map do |primary_feature|
              statuses_for_primary_feature = statuses_by_primary_feature[primary_feature] || []
              enrolled_feature_types = statuses_for_primary_feature.select(&:enrolled?).map(&:feature_type).map(&:to_sym)
              enrolled_feature_types.reject! do |f|
                f == :dependabot_version_updates # hide subfeature from UI (github/security-center#1547)
              end

              include_pseudo_features!(enrolled_feature_types, primary_feature: primary_feature, repo:)

              coverages = enrolled_feature_types
                .sort_by { |f| ([primary_feature] + RepositorySecurityCenterStatus.subfeatures_for(primary_feature)).index(f) || 0 }
                .map { |f| coverage_display_name_for(f, repo) }

              ::SecurityCenter::Coverage::RepositoryCoveragesComponent::Data.new(
                feature: feature_display_name_for(primary_feature),
                coverages: coverages,
                no_coverages_reason: no_coverages_reason_for(primary_feature, repo),
                feature_statuses: statuses_by_primary_feature[primary_feature]&.pluck(:feature_type, :scanning_status).to_h.symbolize_keys,
              )
            end
          end

          risk_url = if scope.is_a?(Business)
            UrlHelpers.security_center_risk_enterprise_path(scope, { query: "repo:#{info.name}" })
          else
            UrlHelpers.security_center_risk_path(scope, { query: "repo:#{info.name}" })
          end

          RepositoryListComponent::ListItemData.new(
            repo_metadata: metadata,
            owner: T.must(repo.owner),
            repo_coverages_list: coverages_list,
          )
        end
      end

      sig { params(visibility: T.nilable(String)).returns(String) }
      def generate_visibility_href(visibility:)
        if scope.is_a?(Organization)
          return UrlHelpers.security_center_coverage_path(scope, { query: parser }) if visibility.nil?
          UrlHelpers.security_center_coverage_path(scope, { query: parser.add_or_replace(CoverageQueryParser::VISIBILITY, visibility) })
        else
          return UrlHelpers.security_center_coverage_enterprise_path(scope, { query: parser }) if visibility.nil?
          UrlHelpers.security_center_coverage_enterprise_path(scope, { query: parser.add_or_replace(CoverageQueryParser::VISIBILITY, visibility) })
        end
      end

      sig { params(repo: Repository).returns(T::Boolean) }
      def alert_secret_scanning_partners_enabled?(repo)
        return false unless GitHub.dotcom_request?
        repo.public?
      end

      sig { params(features: T::Array[Symbol], primary_feature: Symbol, repo: Repository).void }
      def include_pseudo_features!(features, primary_feature:, repo:)
        case primary_feature
        when :secret_scanning
          return unless alert_secret_scanning_partners_enabled?(repo)
          # Security center used to store secret scanning as enrolled for dotcom public repos where the public secret scanning feature was not available.
          # So we'll replace it with the pseudo feature :secret_scanning_partners.
          features.reject! { |f| f == :secret_scanning } unless SecretScanning::Features::Repo::TokenScanning.new(repo).feature_available?
          features << :secret_scanning_partners if features.exclude?(:secret_scanning)
        end
      end

      sig { params(feature: Symbol).returns(String) }
      def feature_display_name_for(feature)
        RepositorySecurityCenterStatus.feature_display_name_for(feature)
      end

      sig { params(feature: Symbol, repo: Repository).returns(String) }
      def coverage_display_name_for(feature, repo)
        return "Security updates paused" if feature.to_sym == :dependabot_security_updates && repo.dependabot_updates_paused?
        RepositorySecurityCenterStatus.coverage_display_name_for(feature)
      end

      sig { params(feature: Symbol, repo: Repository).returns(String) }
      def no_coverages_reason_for(feature, repo)
        if repo.owner&.user?
          return "Not eligible" if [:code_scanning, :dependabot_alerts].include?(feature.to_sym)
        end
        return "Needs setup" if feature.to_sym == :code_scanning
        "Not enabled"
      end

      sig { params(repo: Repository).returns(String) }
      def repo_link(repo)
        if repo.advisory_workspace?
          UrlHelpers.repository_path(repo.owner_display_login, repo)
        else
          UrlHelpers.repository_security_overview_path(repo.owner_display_login, repo)
        end
      end

      sig { params(repo: Repository).returns(T::Boolean) }
      def repo_locked?(repo)
        owner = T.must(repo.owner)
        return false unless owner.user?
        return false unless owner.is_enterprise_managed? || GitHub.enterprise?
        !repo.can_view_secret_scanning_alerts?(user)
      end

      sig { returns(T::Boolean) }
      memoize def emus_in_scope?
        scope.is_a?(Business) &&
          ::SecurityCenter::FeatureFlagHelper.allows_emu_owned_repositories?(scope) &&
          SecurityProduct::Permissions::BusinessAuthz.new(T.cast(scope, Business), actor: @user).can_view_user_owned_repository_alerts?
      end

      sig { returns(T::Array[Symbol]) }
      memoize def visible_features
        SecurityFeatures.visible_features(scope).map(&:to_sym)
      end

      sig { returns(String) }
      memoize def default_configs_table_name
        RepositorySecurityCenterConfig.table_name
      end

      sig { returns(String) }
      memoize def default_statuses_table_name
        RepositorySecurityCenterStatus.table_name
      end

      sig { returns(T::Array[String]) }
      memoize def datadog_tags
        tags = []
        tags << "scope:#{scope.class.name&.demodulize.underscore}"
        tags << "data_query_ver:2"

        filters.each do |filter|
          next unless filter.respond_to?(:is_empty?)
          next if filter.is_empty?
          tags << "has_filter:#{filter.class.name.demodulize.underscore}"
        end
        tags << "sort_by:#{sort.sort_option}"

        tags
      end
    end
  end
end
