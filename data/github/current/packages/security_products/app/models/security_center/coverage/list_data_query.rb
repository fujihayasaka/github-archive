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

      sig { returns(User) }; attr_reader :user
      sig { returns(T.nilable(UserSession)) }; attr_reader :user_session
      sig { returns(T.any(Organization, Business)) }; attr_reader :scope
      sig { returns(CoverageQueryParser) }; attr_reader :parser
      sig { returns(T::Array[Organization]) }; attr_reader :organizations
      sig { returns(T.nilable(T::Array[Integer])) }; attr_reader :repo_ids

      sig do
        params(
          business: Business,
          organizations: T::Array[Organization],
          user: User,
          parser: CoverageQueryParser,
          user_session: T.nilable(UserSession)
        ).returns(T.attached_class)
      end
      def self.for_organizations(business:, organizations:, user:, parser:, user_session: nil)
        new(user: user, scope: business, parser: parser, organizations: organizations, user_session: user_session)
      end

      sig do
        params(
          organization: Organization,
          user: User,
          parser: CoverageQueryParser,
          repo_ids: T.nilable(T::Array[Integer]),
          user_session: T.nilable(UserSession)
        ).returns(T.attached_class)
      end
      def self.for_organization(organization:, user:, parser:, repo_ids: nil, user_session: nil)
        new(user: user, scope: organization, organizations: ([organization]), parser: parser, repo_ids: repo_ids, user_session: user_session)
      end

      private_class_method :new

      sig do
        params(
          user: User,
          scope: T.any(Organization, Business),
          parser: CoverageQueryParser,
          organizations: T.nilable(T::Array[Organization]),
          repo_ids: T.nilable(T::Array[Integer]),
          user_session: T.nilable(UserSession)
        )
        .void
      end
      def initialize(user:, scope:, parser:, organizations: nil, repo_ids: nil, user_session: nil)
        @user = user
        @scope = scope
        @parser = parser
        @organizations = T.let(organizations || [], T::Array[Organization])
        @repo_ids = repo_ids
        @user_session = user_session
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

        filters_list.compact
      end

      sig { returns(T::Boolean) }
      memoize def emus_in_scope?
        scope.is_a?(Business) &&
          ::SecurityCenter::FeatureFlagHelper.allows_emu_owned_repositories?(scope) &&
          SecurityProduct::Permissions::BusinessAuthz.new(T.cast(scope, Business), actor: @user).can_view_user_owned_repository_alerts?
      end
    end
  end
end
