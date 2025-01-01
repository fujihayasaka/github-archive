# typed: true
# frozen_string_literal: true

# Check if a repository is still unpushable. If it is, then delete authorization.
class Codespaces::CleanUpStaleGpgAuthorizationJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(gpg_authorization:)
    repository = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      T.cast(Repositories.domain.by_id(gpg_authorization.repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: gpg_authorization.repository_id)
    end

    # If after the waiting peiord, the repository exists and is now pushable by the user
    # then we don't need to do anything
    if repository && repository.pushable_by?(gpg_authorization.user)
      GitHub.dogstats.increment("gpg_authorizations.clean_up_stale_noop")
      return
    end

    GitHub.dogstats.increment("gpg_authorizations.clean_up_stale")
    with_write do
      Codespaces::TrustedRepositoryAuthorization.throttle_with_retry { gpg_authorization.destroy! }
    end
  end
end
