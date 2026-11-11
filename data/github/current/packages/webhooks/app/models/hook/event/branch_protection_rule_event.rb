# typed: true
# frozen_string_literal: true

class Hook::Event::BranchProtectionRuleEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  description "Branch protection rule created, deleted or edited."

  event_attr :action, :actor_id, :protected_branch_id, required: true
  event_attr :authorized_actor_names, :previous_authorized_actors_only, :previous_authorized_actor_names, :previous_changes, :previous_status_checks_contexts, :previous_authorized_dismissal_actors_only

  # The user who performed the action.
  def actor
    @actor ||= User.find_by(id: actor_id)
  end

  # The protected branch rule entity (if it still exists).
  def protected_branch
    @protected_branch ||= ProtectedBranch.includes(:repository).find_by(id: protected_branch_id)
  end

  # The repository to which the branch belongs
  def target_repository
    protected_branch&.repository
  end

  def deliverable?
    protected_branch.present? && target_repository.present?
  end
end
