# typed: strict
# frozen_string_literal: true

module Marketplace
  module Serializers
    class Repository
      include T::Helpers
      include UrlHelper
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
          name: repository.name,
          owner: repository.owner_display_login,
          isDiscussionsActive: repository.discussions_active?,
          hasIssues: repository.has_issues?,
          hasSecurityPolicy: has_security_policy?,
          mitLicensePath: mit_license_path,
          isThirdParty: is_third_party?,
          isOrganization: is_organization?,
          contributorsCount: contributors.total_count,
          topContributorsData: contributors.top_contributors_data,
        }
      end

      private

      sig { returns(T::Boolean) }
      def has_security_policy?
        security_policy_path = repository.preferred_files.fetch(:security)&.permalink(use_oid: false)
        security_policy_path.present?
      end

      sig { returns(T.nilable(String)) }
      def mit_license_path
        repo_license = repository.repository_licenses.find_by(license_id: License::LICENSES_TO_IDS["mit"])
        return unless repo_license.present?

        # If a repo has multiple licenses, it should have a filepath, so we can reliably use the filepath to link to
        # the MIT license. Legacy repos that have a single license may not have a filepath, so we can use the default
        # LICENSE file in that case.
        if repo_license.filepath.present?
          blob_view_path(repo_license.filepath, repository.default_branch, repository)
        else
          preferred_file_path(type: :license, repository: repository)
        end
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
