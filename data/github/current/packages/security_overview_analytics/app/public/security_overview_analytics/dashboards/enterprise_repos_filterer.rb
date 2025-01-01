# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    class EnterpriseReposFilterer
      include ReposFilterer
      include GitHub::Memoizer

      Organizations = T.type_alias { T.any(T::Array[::Organization], T::Hash[Symbol, T::Array[::Organization]]) }

      sig { returns(::Business) }
      attr_reader :business

      sig { returns(T::Hash[Symbol, T::Array[::Organization]]) }
      attr_reader :allowed_organizations_by_feature

      sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
      attr_reader :query

      sig { returns(::User) }
      attr_reader :user

      sig do
        params(
          business: ::Business,
          organizations: Organizations,
          query: ::Search::Queries::SecurityCenter::QueryParser,
          user: ::User
        ).void
      end
      def initialize(business:, organizations:, query:, user:)
        @business = business
        @query = query
        @user = user

        organizations = organizations.dup.freeze
        @allowed_organizations_by_feature = T.let(
          if organizations.is_a?(Hash)
            organizations
          else
            {
              code_scanning: organizations,
              dependabot_alerts: organizations,
              secret_scanning: organizations,
            }.freeze
          end,
          T::Hash[Symbol, T::Array[::Organization]],
        )
      end

      sig { override.params(repos_slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def cs_repo_metadata_rel(repos_slice4: nil)
        organizations = T.must(allowed_organizations_by_feature[:code_scanning])
        any_feature_repo_metadata_rel_impl(organizations:, repos_slice4:)
      end

      sig { override.params(repos_slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def dbot_repo_metadata_rel(repos_slice4: nil)
        organizations = T.must(allowed_organizations_by_feature[:dependabot_alerts])
        any_feature_repo_metadata_rel_impl(organizations:, repos_slice4:)
      end

      sig { override.params(repos_slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def ss_repo_metadata_rel(repos_slice4: nil)
        organizations = T.must(allowed_organizations_by_feature[:secret_scanning])
        any_feature_repo_metadata_rel_impl(organizations:, repos_slice4:)
      end

      sig { override.params(repos_slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def any_feature_repo_metadata_rel(repos_slice4: nil)
        organizations = allowed_organizations_by_feature.values.flatten
        any_feature_repo_metadata_rel_impl(organizations:, repos_slice4:)
      end

      sig { override.returns(T::Array[String]) }
      def applied_filters
        repo_metadata_filters(allowed_organizations_by_feature.values.flatten)
          .select { |f| !f.is_empty? }
          .map { |f| f.class.name.demodulize.underscore }
      end

      sig { returns(T::Boolean) }
      memoize def include_user_repos?
        SecurityProduct::Permissions::BusinessAuthz.new(business, actor: user).can_view_user_owned_repository_alerts? &&
        ::AdvancedSecurity::Features::Business::AdvancedSecurity.new(business).security_center_for_emus_enabled?
      end

      private

      sig do
        params(organizations: T::Array[::Organization]).
        returns(
          T::Array[T.any(::SecurityOverviewAnalytics::Filters::Filter, ::SecurityCenter::Filters::ByCustomProperty)]
        )
      end
      def repo_metadata_filters(organizations)
        [
          ::SecurityOverviewAnalytics::Filters::ByArchived.new(*query.get_positive_and_negative_qualified_values("archived")),
          ::SecurityOverviewAnalytics::Filters::ByRepository.new(query.get_unqualified_values, [], substring_match: true, scope: business),
          ::SecurityOverviewAnalytics::Filters::ByRepository.new(*query.get_positive_and_negative_qualified_values("repo"), substring_match: false, scope: business),
          ::SecurityOverviewAnalytics::Filters::ByOrganization.new(*query.get_positive_and_negative_qualified_values("org"), authorized_orgs: organizations),
          ::SecurityOverviewAnalytics::Filters::ByTeam.new(*query.get_positive_and_negative_qualified_values("team"), organizations:, user:),
          ::SecurityOverviewAnalytics::Filters::ByTopic.new(*query.get_positive_and_negative_qualified_values("topic"), organizations:),
          ::SecurityOverviewAnalytics::Filters::ByVisibility.new(*query.get_positive_and_negative_qualified_values("visibility", qualifier_alias: "is")),
          ::SecurityOverviewAnalytics::Filters::ByOwner.new(*query.get_positive_and_negative_qualified_values("owner"), business, organizations),
          ::SecurityOverviewAnalytics::Filters::ByOwnerType.new(*query.get_positive_and_negative_qualified_values("owner-type"), business, organizations),
        ]
      end

      sig { params(organizations: T::Array[::Organization], repos_slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def any_feature_repo_metadata_rel_impl(organizations:, repos_slice4: nil)
        baserel = ::SecurityOverviewAnalytics::Repository
        owner_type_rel = baserel.where(owner_id: organizations.map(&:id), owner_type: "Organization")
        if include_user_repos?
          owner_type_rel = owner_type_rel.or(baserel.where(owner_type: "User"))
        end

        baserel = baserel
          .where(business_id: business.id)
          .and(owner_type_rel)
          .then do |rel|
            repo_metadata_filters(organizations).reduce(rel) { |r, filter| filter.apply(r) }
          end

        if repos_slice4.present?
          baserel = baserel.where("mod(`soa_repositories`.`repository_id`, 4) = ?", repos_slice4)
        end

        baserel
      end
    end
  end
end
