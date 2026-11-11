# typed: true
# frozen_string_literal: true

# This file follows the pattern of the CodeScanningOrgQueriesHelper
# and is used for Secret Scanning Security Campaigns
module Orgs::SecurityCenter::SecretScanningOrgQueriesHelper
  extend T::Helpers

  requires_ancestor { Orgs::SecurityCenter::AbstractSecurityCenterController }

  include GitHub::Memoizer

  abstract!

  sig { returns(T.nilable(T::Array[Integer])) }
  memoize def allowed_repo_ids_for_secret_scanning
    return nil if can_view_all_alerts?
    ids, _ = allowed_repository_ids_by_feature_for_organization_members[SecurityCenter::SecurityFeatures::SECRET_SCANNING]
    ids
  end

  # Returns the repository IDs from the `repository` param. Returns nil if the param is not present or empty.
  # Returns an empty array if the param is invalid or the user does not have access to any of the repositories.
  # This matches the expected format of the allowed_repository_ids param on the alert query service.
  sig { returns(T.nilable(T::Array[Integer])) }
  memoize def repository_ids_from_params_for_secret_scanning
    repository_names = Array(params[:repository])
    return nil if repository_names.empty?
    # Do not allow more than 1000 repositories to be specified in the query params
    return [] if repository_names.size > 1000

    # We can only find repositories by nwo through the public interface, so just add the owner to the name
    repository_nwos = repository_names.map { |name| "#{this_organization.display_login}/#{name}" }

    repository_ids = Repository.with_names_with_owners(repository_nwos).pluck(:id)

    # Check that the user has secret scanning read access to the repositories
    repository_ids = SecurityProduct::AuthorizationEnumerator.new(user: current_user, actions: [:view_secret_scanning_alerts], options: {
      organization: this_organization,
      repository_ids:,
    }).authorized_repository_ids

    repository_ids
  end
end
