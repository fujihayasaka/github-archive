# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Risk
    class ListDataQuery
      include GitHub::Memoizer
      include GitHub::SecurityCenter::TenantFilteringHelper

      RiskQueryParser = ::Search::Queries::SecurityCenter::RiskQueryParser

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
      sig { returns(T.any(Organization, Business)) }; attr_reader :scope
      sig { returns(RiskQueryParser) }; attr_reader :parser
      sig { returns(Integer) }; attr_reader :page_size
      sig { returns(T::Array[Organization]) }; attr_reader :organizations
      sig { returns(T.nilable(T::Hash[Symbol, T::Array[Integer]])) }; attr_reader :repo_ids_by_feature
      sig { returns(T.nilable(UserSession)) }; attr_reader :user_session

      sig do
        params(
          business: Business,
          organizations: T::Array[Organization],
          user: User,
          parser: RiskQueryParser,
          page_size: Integer,
          user_session: T.nilable(UserSession)
        ).returns(T.attached_class)
      end
      def self.for_organizations(business:, organizations:, user:, parser:, page_size:, user_session: nil)
        new(user: user, scope: business, parser: parser, organizations: organizations, page_size: page_size, user_session: user_session, repo_ids_by_feature: nil)
      end

      sig do
        params(
          organization: Organization,
          user: User,
          parser: RiskQueryParser,
          page_size: Integer,
          user_session: T.nilable(UserSession),
          repo_ids_by_feature: T.nilable(T::Hash[Symbol, T::Array[Integer]])
        ).returns(T.attached_class)
      end
      def self.for_organization(organization:, user:, parser:, page_size:, user_session: nil, repo_ids_by_feature: nil)
        new(user: user, scope: organization, organizations: ([organization]), parser: parser, page_size: page_size, user_session: user_session, repo_ids_by_feature: repo_ids_by_feature)
      end

      private_class_method :new

      sig do
        params(
          user: User,
          scope: T.any(Organization, Business),
          parser: RiskQueryParser,
          page_size: Integer,
          organizations: T::Array[Organization],
          user_session: T.nilable(UserSession),
          repo_ids_by_feature: T.nilable(T::Hash[Symbol, T::Array[Integer]])
        )
        .void
      end
      def initialize(user:, scope:, parser:, page_size:, organizations:, user_session: nil, repo_ids_by_feature: nil)
        @user = user
        @scope = scope
        @parser = parser
        @page_size = page_size
        @organizations = organizations
        @user_session = user_session
        @repo_ids_by_feature = repo_ids_by_feature
      end

      sig { params(page: Integer).returns(Result) }
      def run(page: 1)
        GitHub.dogstats.distribution_time("security_center.risk_list_data_query.run.dist", tags: datadog_tags) do
          return Result.new(
            list_items: [],
            current_page: 0,
          ) if visible_features.empty?

          list_items = base_rel
            .then { |rel| sort.apply(rel, page:) }
            .then { |rel| rel.select("#{default_configs_table_name}.*") }
            .then { |rel| emus_in_scope? ? rel.preload(repository: [:internal_repository]) : rel }
            .then { |rel| rel.preload(:repository_security_center_statuses) } # for alert counts
            .then { |rel| rel.preload(repository: [:parent_advisory, :owner]) } # For 'repo' and 'repo.advisory_workspace?'
            .then do |rel|
              # total_entries=-1 - sentinel value to keep `WillPaginate` from running its `count` query
              rel.paginate(page: page, per_page: page_size, total_entries: -1).to_a
            end
            .then { |rel| next apply_tenant_filter(rel), rel.total_entries }
            .then { |results, total| next view_model_for(results), total }
            .then { |results, total| paginate_results(results, page: page, total: total) }

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
          ).first
        active_count = repo_counts&.total_active_repos&.to_i || 0
        archived_count = repo_counts&.total_archived_repos&.to_i || 0

        archived_filters, _ = parser.values_for_qualifier(RiskQueryParser::ARCHIVED) # archived has no negative qualifier
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

      private

      sig { returns(ActiveRecord::Relation) }
      memoize def base_rel
        base_where = if scope.is_a?(Business)
          RepositorySecurityCenterConfig
            .with_owners_under_business(scope, organizations, include_emus: emus_in_scope?)
        else
          RepositorySecurityCenterConfig.where(owner_id: organizations)
        end

        base_where
          .then { |rel| ByAccessibleRepos.new(repo_ids_by_feature: repo_ids_by_feature, parser: parser).apply(rel) }
          .then { |rel| filters.reduce(rel) { |r, filter| filter.apply(r) } }
      end

      sig { returns(T::Array[T.untyped]) }
      memoize def filters
        filters_list = T.let([
          ::SecurityCenter::Filters::ByRepository.new(*parser.values_without_qualifiers, substring_match: true, scope: scope),
          ::SecurityCenter::Filters::ByRepository.new(*parser.values_for_qualifier(RiskQueryParser::REPOSITORY), scope: scope),
          ::SecurityCenter::Filters::ByVisibility.new(*parser.values_for_qualifier(RiskQueryParser::VISIBILITY)),
          ::SecurityCenter::Filters::ByArchived.new(*parser.values_for_qualifier(RiskQueryParser::ARCHIVED)),
          ::SecurityCenter::Filters::ByTeam.new(*parser.values_for_qualifier(RiskQueryParser::TEAM), organizations: organizations, user: user),
          ::SecurityCenter::Filters::ByTopic.new(*parser.values_for_qualifier(RiskQueryParser::TOPIC), organizations: organizations),
          ::SecurityCenter::Filters::ByFeature.new(*parser.values_for_qualifier(RiskQueryParser::CODE_SCANNING), feature: :code_scanning, scope: scope),
          ::SecurityCenter::Filters::ByFeature.new(*parser.values_for_qualifier(RiskQueryParser::DEPENDABOT_ALERTS), feature: :dependabot_alerts, scope: scope),
          ::SecurityCenter::Filters::ByFeature.new(*parser.values_for_qualifier(RiskQueryParser::SECRET_SCANNING), feature: :secret_scanning, scope: scope),
          ::SecurityCenter::Filters::ByHasSeverity.new(*parser.values_for_qualifier(RiskQueryParser::HAS_SEVERITY)),
        ], T::Array[T.untyped])

        additional_filters_list =
          if scope.is_a?(Business)
            [
              ::SecurityCenter::Filters::ByOwner.new(*parser.values_for_qualifier(RiskQueryParser::OWNER), T.cast(scope, Business)),
              ::SecurityCenter::Filters::ByOwnerType.new(*parser.values_for_qualifier(RiskQueryParser::OWNER_TYPE), T.cast(scope, Business))
            ]
          else
            [
              ::SecurityCenter::Filters::ByCustomProperty.new(
                allowed_repo_ids: repo_ids_by_feature&.values&.flatten&.uniq,
                query: parser.custom_properties_query_string,
                org: T.cast(scope, ::Organization),
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
        parser.sort_by.then { |sort_option, _| SortBy.new(sort_option, organizations:, page_size:) }
      end

      sig { params(rel: WillPaginate::Collection).returns(T::Array[RepositorySecurityCenterConfig]) }
      def apply_tenant_filter(rel)
        request_scope = scope.is_a?(Organization) ? :organization : :business
        filter_tenant_rows(
          RequestScope.new(request_scope, scope, "risk"),
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

        if emus_in_scope?
          repos = rel.map(&:repository).compact
          fgp = SecretScanning::AccessControl::FineGrainedPermissions
          locked_repos = fgp.get_unlockable_user_repos(user, repos)
        end

        rel.map do |info|
          repo = T.must(info.repository)
          name = scope.is_a?(Business) ? repo.name_with_display_owner : info.name

          repo_locked = locked_repos&.include?(repo.id) || false

          metadata = ::SecurityCenter::Coverage::RepositoryMetadataComponent::Data.new(
            id: info.repository_id,
            name: name,
            href: repo_link(repo),
            visibility: T.must(info.visibility),
            visibility_href: generate_visibility_href(visibility: info.visibility),
            repo_locked:,
            archived: info.archived,
            ghas_enabled: info.ghas_enabled,
            updated_at: info.last_push,
          )

          not_enrolled_features = Set.new
          alert_counts_by_feature = info.repository_security_center_statuses.each_with_object({}) do |status, h|
            this_feature = status.feature_type.to_sym
            not_enrolled_features.add(this_feature) if status.scanning_status == "not_enrolled"
            h[this_feature] = status.scanning_count
          end

          repo_alert_count_map = visible_features.each_with_object({}) do |feature, h|
            # If nil, the user can see all features.
            # Otherwise they need specific access to this repo/feature.
            next unless repo_ids_by_feature.nil? || T.must(repo_ids_by_feature)[feature]&.include?(info.repository_id)
            next if not_enrolled_features.include?(feature)
            next unless eligible_for_alerts?(feature, repo)

            h[feature] = RepositoryAlertCountComponent::Data.new(
              alert_count: alert_counts_by_feature.fetch(feature, 0),
              feature: RepositorySecurityCenterStatus.feature_display_name_for(feature),
              href: repo_feature_path(repo, feature),
              repo_id: T.must(repo.id),
              repo_locked: repo_locked,
            )
          end

          RepositoryListComponent::ListItemData.new(
            repo_metadata: metadata,
            owner: T.must(repo.owner),
            repo_alert_count_map: repo_alert_count_map,
          )
        end
      end

      sig { params(visibility: T.nilable(String)).returns(String) }
      def generate_visibility_href(visibility:)
        if scope.is_a?(Organization)
          return UrlHelpers.security_center_risk_path(scope, { query: parser }) if visibility.nil?
          UrlHelpers.security_center_risk_path(scope, { query: parser.add_or_replace(RiskQueryParser::VISIBILITY, visibility) })
        else
          return UrlHelpers.security_center_risk_enterprise_path(scope, { query: parser }) if visibility.nil?
          UrlHelpers.security_center_risk_enterprise_path(scope, { query: parser.add_or_replace(RiskQueryParser::VISIBILITY, visibility) })
        end
      end

      sig { params(repo: Repository, feature: Symbol).returns(String) }
      def repo_feature_path(repo, feature)
        case feature
        when :dependabot_alerts
          UrlHelpers.repository_alerts_path(repo.owner_display_login, repo)
        when :code_scanning
          UrlHelpers.repository_code_scanning_results_path(repo.owner_display_login, repo)
        when :secret_scanning
          UrlHelpers.repository_token_scanning_results_path(repo.owner_display_login, repo)
        else
          "#"
        end
      end

      sig { params(repo: Repository).returns(String) }
      def repo_link(repo)
        return UrlHelpers.repository_path(repo.owner_display_login, repo) if repo.advisory_workspace?
        UrlHelpers.repository_security_overview_path(repo.owner_display_login, repo)
      end

      sig { params(repo: Repository).returns(T::Boolean) }
      def repo_locked?(repo)
        owner = T.must(repo.owner)
        return false unless owner.user?
        return false unless owner.is_enterprise_managed? || GitHub.enterprise?
        !repo.can_view_secret_scanning_alerts?(user)
      end

      sig { params(feature: Symbol, repo: Repository).returns(T::Boolean) }
      def eligible_for_alerts?(feature, repo)
        return true unless repo.owner&.user?
        case feature
        when :dependabot_alerts
          false
        when :code_scanning
          false
        else
          true
        end
      end

      sig { returns(T::Boolean) }
      memoize def emus_in_scope?
        scope.is_a?(Business) &&
          ::SecurityCenter::FeatureFlagHelper.allows_emu_owned_repositories?(scope) &&
          SecurityProduct::Permissions::BusinessAuthz.new(T.cast(scope, Business), actor: user).can_view_user_owned_repository_alerts?
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
