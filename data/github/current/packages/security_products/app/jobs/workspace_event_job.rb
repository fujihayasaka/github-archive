# typed: strict
# frozen_string_literal: true

# Base class for workspace event jobs
class WorkspaceEventJob < Repositories::RepositoryHydroMessageJob
  extend T::Sig

  retry_on_dirty_exit

  private

  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def admin_frontend_accessible?(actor)
    actor&.site_admin? || actor&.biztools_user? || actor&.github_developer?
  end

  sig do
    params(
      parent_repo: Repository,
      actor: T.nilable(User)
    ).returns(T::Boolean)
  end
  def can_manage_advisories?(parent_repo, actor)
    return false unless actor

    parent_repo.advisory_management_authorized_for?(actor)
  end

  sig do
    params(
      parent_advisory: RepositoryAdvisory,
      actor: T.nilable(User)
    ).returns(T::Boolean)
  end
  def pvr_author?(parent_advisory, actor)
    return false unless actor

    parent_advisory.external? && parent_advisory.author == actor
  end
end
