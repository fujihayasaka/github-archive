# typed: false
# frozen_string_literal: true

# A gate approver is a user or team who has been designated as an approver for
# a given gate on a specific environment in a repository.
class GateApprover < ApplicationRecord::ActionsEnvironments
  belongs_to :gate
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain return_type: T.nilable(Repositories::IRepository)
  belongs_to :approver, polymorphic: true

  validate :ensure_user_is_collaborator
  validates_uniqueness_of :approver_id, scope: [:approver_type, :gate_id], message: "is already an approver"

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
      repository.
        teams(immediate_only: false).
        closed.
        where(organization_id: repository.organization.id, id: approver.id).
        map { |team| team.id }.
        include?(approver.id)
    end
  end
end
