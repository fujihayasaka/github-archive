# typed: strict
# frozen_string_literal: true

module Marketplace
  module Serializers
    class Repository
      include T::Helpers
      include GitHub::Memoizer

      sig { returns(::Repository) }
      attr_reader :repository

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig { params(repository: ::Repository, current_user: T.nilable(User)).void }
      def initialize(repository:, current_user:)
        @repository = repository
        @current_user = current_user
      end

      sig { returns(Marketplace::Types::SerializedRepository) }
      def call
        {
          id: repository.id,
          name: repository.name,
          owner: repository.owner_display_login,
          isDiscussionsActive: repository.discussions_active?,
          hasIssues: repository.has_issues?,
          hasSecurityPolicy: has_security_policy?,
          isThirdParty: is_third_party?,
          isOrganization: is_organization?,
          contributorsCount: contributors.total_count,
          topContributorsData: contributors.top_contributors_data,
          openIssuesCount: Issues.domain.open_issue_count_for_repo(repository, current_user, cached: true),
          openPullRequestsCount: repository.open_pull_request_count_for(current_user) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        }
      end

      private

      sig { returns(T::Boolean) }
      def has_security_policy?
        security_policy_path = repository.preferred_files.fetch(:security)&.permalink(use_oid: false)
        security_policy_path.present?
      end

      sig { returns(T::Boolean) }
      def is_third_party?
        repository.owner_display_login != RepositoryAction::ACTIONS_ORG_NAME
      end

      sig { returns(T::Boolean) }
      def is_organization?
        repository.owner.is_a?(Organization)
      end

      sig { returns(Marketplace::Repositories::Contributors) }
      memoize def contributors
        Marketplace::Repositories::Contributors.new(repository, current_user)
      end
    end
  end
end
