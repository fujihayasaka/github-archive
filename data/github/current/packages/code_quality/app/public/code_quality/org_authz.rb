# typed: strict
# frozen_string_literal: true

class CodeQuality::OrgAuthz
  REPO_LIMIT_FOR_ORG_MEMBERS = 3000

  class AllowedRepos < T::Struct
    const :repository_ids, T.nilable(T::Array[Integer])
    const :limit_exceeded, T::Boolean, default: false
  end

  # Returns a list of repo IDs and a boolean indicating if the limit was exceeded.
  # If the user is an org admin, returns repository_ids: nil, limit_exceeded: false to indicate all repos are allowed.
  # Otherwise returns the list of repo IDs the user has :read_code_quality permission for,
  # limited to REPO_LIMIT_FOR_ORG_MEMBERS, and a boolean indicating if the limit was exceeded.
  # Specifically if the user cannot see any repos then we return an empty array.
  sig { params(user: User, organization: Organization).returns(AllowedRepos) }
  def self.allowed_repo_ids(user:, organization:)
    # If the user has org-level permission to code quality, then they can see all repos
    return AllowedRepos.new(repository_ids: nil) if Authz.domain.check_allowed(user, :read_code_quality, organization)

    # Find all repos in the org with the :read_code_quality permission
    candidate_repo_ids = Repositories.domain.repo_ids_by_owners(owner_ids: [organization.id], active_only: true)
    options = {
      organization: organization,
      repository_ids: candidate_repo_ids,
      include_oauth_restriction: false,
      include_indirect_forks: false,
      include_oopfs: false,
    }
    auth_enumerator = SecurityProduct::AuthorizationEnumerator.new(
      user: user,
      actions: [:read_code_quality],
      options:
    )
    allowed_repo_ids = auth_enumerator.authorized_repository_ids
    # We only allow a limited number of repos to be queried at once
    repo_limit_exceeded = allowed_repo_ids.size > REPO_LIMIT_FOR_ORG_MEMBERS
    allowed_repo_ids = allowed_repo_ids.take(REPO_LIMIT_FOR_ORG_MEMBERS) if repo_limit_exceeded
    AllowedRepos.new(repository_ids: allowed_repo_ids, limit_exceeded: repo_limit_exceeded)
  end
end
