# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    class EnterpriseReposFilterer
      extend T::Sig
      include ReposFilterer
      include GitHub::Memoizer

      sig { returns(::Business) }
      attr_reader :business

      sig { returns(T::Array[::Organization]) }
      attr_reader :organizations

      sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
      attr_reader :query

      sig { returns(::User) }
      attr_reader :user

      sig do
        params(
          business: ::Business,
          organizations: T::Array[::Organization],
          query: ::Search::Queries::SecurityCenter::QueryParser,
          user: ::User
        ).void
      end
      def initialize(business:, organizations:, query:, user:)
        @business = business
        @organizations = organizations
        @query = query
        @user = user
      end

      sig { override.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def cs_repo_metadata_rel(slice4: nil)
        any_feature_repo_metadata_rel(slice4:)
      end

      sig { override.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def dbot_repo_metadata_rel(slice4: nil)
        any_feature_repo_metadata_rel(slice4:)
      end

      sig { override.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def ss_repo_metadata_rel(slice4: nil)
        any_feature_repo_metadata_rel(slice4:)
      end

      sig { override.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def any_feature_repo_metadata_rel(slice4: nil)
        baserel = ::SecurityOverviewAnalytics::Repository
        owner_type_rel = baserel.where(owner_id: organizations.map(&:id), owner_type: "Organization")
        if include_user_repos?
          owner_type_rel = owner_type_rel.or(baserel.where(owner_type: "User"))
        end

        baserel = baserel
          .where(business_id: business.id)
          .and(owner_type_rel)
          .then do |rel|
            repo_metadata_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end

        if slice4.present?
          baserel = baserel.where("mod(`soa_repositories`.`repository_id`, 4) = ?", slice4)
        end

        baserel
      end

      sig { override.returns(T::Boolean) }
      def filters_applied?
        repo_metadata_filters.any? { |filter| !filter.is_empty? }
      end

      sig do
        override.returns(
          T::Array[T.any(::SecurityOverviewAnalytics::Filters::Filter, ::SecurityCenter::Filters::ByCustomProperty)]
        )
      end
      memoize def repo_metadata_filters
        [
          ::SecurityOverviewAnalytics::Filters::ByArchived.new(*query.get_positive_and_negative_qualified_values("archived")),
          ::SecurityOverviewAnalytics::Filters::ByRepository.new(query.get_unqualified_values, [], substring_match: true, scope: business),
          ::SecurityOverviewAnalytics::Filters::ByRepository.new(*query.get_positive_and_negative_qualified_values("repo"), substring_match: false, scope: business),
          ::SecurityOverviewAnalytics::Filters::ByOrganization.new(*query.get_positive_and_negative_qualified_values("org"), authorized_orgs: organizations),
          ::SecurityOverviewAnalytics::Filters::ByTeam.new(*query.get_positive_and_negative_qualified_values("team"), organizations:, user:),
          ::SecurityOverviewAnalytics::Filters::ByTopic.new(*query.get_positive_and_negative_qualified_values("topic"), organizations:),
          ::SecurityOverviewAnalytics::Filters::ByVisibility.new(*query.get_positive_and_negative_qualified_values("visibility")),
          ::SecurityOverviewAnalytics::Filters::ByOwner.new(*query.get_positive_and_negative_qualified_values("owner"), business, organizations),
          ::SecurityOverviewAnalytics::Filters::ByOwnerType.new(*query.get_positive_and_negative_qualified_values("owner-type"), business, organizations),
        ]
      end

      private

      sig { returns(T::Boolean) }
      def include_user_repos?

        SecurityProduct::Permissions::BusinessAuthz.new(business, actor: user).can_view_user_owned_repository_alerts? &&
        ::AdvancedSecurity::Features::Business::AdvancedSecurity.new(business).security_center_for_emus_enabled?
      end
    end
  end
end
