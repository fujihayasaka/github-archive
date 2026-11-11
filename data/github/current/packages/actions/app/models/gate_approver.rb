# typed: false
# frozen_string_literal: true

# A gate approver is a user or team who has been designated as an approver for
# a given gate on a specific environment in a repository.
class GateApprover < ApplicationRecord::ActionsEnvironments
  belongs_to :gate
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  belongs_to :approver, polymorphic: true

  validate :ensure_user_is_collaborator
  validates_uniqueness_of :approver_id, scope: [:approver_type, :gate_id], message: "is already an approver"

  # Override the default polymorphic reader for BusinessTeam approvers.
  # Rails' polymorphic `belongs_to` resolves `approver_type.constantize`,
  # but the query goes through Team's default_scope which filters
  # `WHERE organization_id IS NOT NULL`. BusinessTeam records have
  # `organization_id: nil`, so `super` returns nil / raises RecordNotFound.
  # Using `Team.with_business_teams` unscopes that filter.
  #
  # The result is memoized because the approver is accessed multiple times
  # per request (ensure_user_is_collaborator, can_approve?, serializers).
  #
  # Feature-flag-gated so that when the FF is off we fall through to the
  # standard polymorphic `super`.
  def approver
    if approver_type == "BusinessTeam" && business_team_support_enabled?
      @business_team_approver ||= Team.with_business_teams.find_by(id: approver_id)
    else
      super
    end
  end

  def ensure_user_is_collaborator
    # NOTE: This is borrowed from https://github.com/github/github/blob/22162eeac46f169dc78c3caad61d5e2f3607de80/app/models/review_request.rb,
    # and I'm not sure if it's necessary.
    return if approver.is_a?(User) && approver.ghost?

    unless can_approve?
      errors.add :approver, "must be a collaborator"
    end
  end

  private def can_approve?
    if approver.is_a?(User)
      # Any user with read access on the repository.
      repository.user_ids_with_privileged_access(min_action: :read, actor_ids_filter: [approver.id]).include?(approver.id)
    else
      # All closed (non-secret) teams with repo access, including nested.
      teams_scope = repository.
        teams(immediate_only: false, include_all_repo_roles: true).
        closed.
        where(id: approver.id)

      # BusinessTeams belong to a Business, not an Organization, so they
      # have a nil organization_id. Skip the organization_id filter for them.
      if business_team_support_enabled? && approver.is_a?(BusinessTeam)
        # no org filter — BusinessTeams have nil organization_id
      else
        teams_scope = teams_scope.where(organization_id: repository.organization.id)
      end

      teams_scope.
        map { |team| team.id }.
        include?(approver.id)
    end
  end

  private def business_team_support_enabled?
    repository&.feature_flag_enabled?(:environment_reviewers_all_repo_roles, default: false)
  end
end
