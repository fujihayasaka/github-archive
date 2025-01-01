# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    class OrgReposFilterer
      extend T::Sig
      include ReposFilterer
      include GitHub::Memoizer

      sig { returns(::Organization) }
      attr_reader :organization

      sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
      attr_reader :query

      sig { returns(::User) }
      attr_reader :user

      sig { returns(::UserSession) }
      attr_reader :user_session

      sig { returns(T.nilable(T::Hash[String, T::Array[Integer]])) }
      attr_reader :allowed_repo_ids_by_feature

      sig do
        params(
          organization: ::Organization,
          query: ::Search::Queries::SecurityCenter::QueryParser,
          user: ::User,
          user_session: ::UserSession,
          allowed_repo_ids_by_feature: T.nilable(T::Hash[String, T::Array[Integer]])
        ).void
      end
      def initialize(organization:, query:, user:, user_session:, allowed_repo_ids_by_feature: nil)
        @organization = organization
        @query = query
        @user = user
        @user_session = user_session
        @allowed_repo_ids_by_feature = allowed_repo_ids_by_feature
      end

      sig { override.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def cs_repo_metadata_rel(slice4: nil)
        repo_metadata_rel(CodeScanningAlertRevision.feature_type, slice4:)
      end

      sig { override.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def dbot_repo_metadata_rel(slice4: nil)
        repo_metadata_rel(DependabotAlertRevision.feature_type, slice4:)
      end

      sig { override.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def ss_repo_metadata_rel(slice4: nil)
        repo_metadata_rel(SecretScanningAlertRevision.feature_type, slice4:)
      end

      sig { override.params(slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def any_feature_repo_metadata_rel(slice4: nil)
        rel = ::SecurityOverviewAnalytics::Repository
          .where(organization_id: organization.id)
          .then do |rel|
            next rel if @allowed_repo_ids_by_feature.nil? # admin
            # Find all repos that user can access for at least one feature
            rel.where(repository_id: @allowed_repo_ids_by_feature.values.flatten.uniq) # non-admin
          end
          .then do |rel|
            repo_metadata_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end

        if slice4.present?
          rel = rel.where("mod(`soa_repositories`.`repository_id`, 4) = ?", slice4)
        end

        rel
      end

      sig { override.returns(T::Boolean) }
      def filters_applied?
        return true if @allowed_repo_ids_by_feature.present?
        repo_metadata_filters.any? { |filter| !filter.is_empty? }
      end

      sig do
        override.returns(
          T::Array[T.any(::SecurityOverviewAnalytics::Filters::Filter, ::SecurityCenter::Filters::ByCustomProperty)]
        )
      end
      memoize def repo_metadata_filters
        allowed_repo_ids = @allowed_repo_ids_by_feature&.values&.flatten&.uniq

        [
          ::SecurityOverviewAnalytics::Filters::ByArchived.new(*query.get_positive_and_negative_qualified_values("archived")),
          ::SecurityCenter::Filters::ByCustomProperty.new(allowed_repo_ids:, query: query.custom_properties_string, org: organization, user:, user_session:),
          ::SecurityOverviewAnalytics::Filters::ByRepository.new(query.get_unqualified_values, [], substring_match: true, scope: organization),
          ::SecurityOverviewAnalytics::Filters::ByRepository.new(*query.get_positive_and_negative_qualified_values("repo"), substring_match: false, scope: organization),
          ::SecurityOverviewAnalytics::Filters::ByTeam.new(*query.get_positive_and_negative_qualified_values("team"), organizations: [organization], user:),
          ::SecurityOverviewAnalytics::Filters::ByTopic.new(*query.get_positive_and_negative_qualified_values("topic"), organizations: [organization]),
          ::SecurityOverviewAnalytics::Filters::ByVisibility.new(*query.get_positive_and_negative_qualified_values("visibility")),
        ]
      end

      private

      sig { params(feature_type: String, slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def repo_metadata_rel(feature_type, slice4: nil)
        rel = ::SecurityOverviewAnalytics::Repository
          .where(organization_id: organization.id)
          .then do |rel|
            next rel if @allowed_repo_ids_by_feature.nil? || @allowed_repo_ids_by_feature[feature_type].nil? # admin
            rel.where(repository_id: @allowed_repo_ids_by_feature[feature_type]) # non-admin
          end
          .then do |rel|
            repo_metadata_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end

        if slice4.present?
          rel = rel.where("mod(`soa_repositories`.`repository_id`, 4) = ?", slice4)
        end

        rel
      end
    end
  end
end
