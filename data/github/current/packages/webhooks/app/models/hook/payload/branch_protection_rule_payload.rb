# typed: true
# frozen_string_literal: true

class Hook::Payload::BranchProtectionRulePayload < Hook::Payload
  def to_payload_hash
    {
      action: hook_event.action,
      rule: rule,
      changes: changes
    }.compact
  end

  private

  # Builds the "rule" hash with the serialized values
  def rule
    @rule ||= serialize(
      hook_event.protected_branch,
      required_status_checks: hook_event.protected_branch.required_status_checks.pluck(:context),
      authorized_actors_only: hook_event.protected_branch.authorized_actors_only,
      authorized_actor_names: hook_event.authorized_actor_names,
      authorized_dismissal_actors_only: hook_event.protected_branch.authorized_dismissal_actors_only)
  end

  # Builds the "changes" hash with all values that changed
  #
  # Returns a Hash in the format below
  #  { field1: {from: "old value"}, field2: {from: "old value"}, ... }
  #  (nil if `previous_changes` was not supplied to the event, or no changes are reported)
  def changes
    return nil unless hook_event.previous_changes

    # Reconstruct the previous record from Rails' previous_changes (with
    # special handling for association-based properties and a pesky one that is
    # AR-assignable *only* when false; see ProtectedBranch#authorized_actors_only=
    # and ModifyBranchProtectionRule mutation)
    previous_record = hook_event.protected_branch.dup
    changed_attributes = hook_event.previous_changes.transform_values(&:first)
    previous_record.assign_attributes(changed_attributes.except("authorized_actors_only", "authorized_dismissal_actors_only"))

    serialized_previous_record = serialize(
      previous_record,
      required_status_checks: hook_event.previous_status_checks_contexts,
      authorized_actors_only: hook_event.previous_authorized_actors_only.nil? ? changed_attributes["authorized_actors_only"] : hook_event.previous_authorized_actors_only,
      authorized_actor_names: hook_event.previous_authorized_actor_names,
      authorized_dismissal_actors_only: hook_event.previous_authorized_dismissal_actors_only.nil? ? changed_attributes["authorized_dismissal_actors_only"] : hook_event.previous_authorized_dismissal_actors_only,
    )

    serialized_previous_record
      .except(:id, :created_at, :updated_at)
      .reject { |k, v| rule[k] == v }
      .transform_values { |v| { from: (v.is_a?(Symbol) ? v.to_s : v) } }
      .presence
  end

  # Serializes a protected branch rule
  #
  # (existing serializers either operate on the rules applied to an individual
  # branch, or do not have all the fields we need; fields that can't be directly
  # set on the entity are passed separately)
  #
  # entity: the ProtectedBranch entity to be serialized
  # required_status_checks: Array with names ("contexts") of mandatory
  #                         status checks
  # authorzied_actors_only: Whether the branch restricts who can merge
  # authorized_actor_names: Array with names (login, name or slug) of actors
  #                         (users, teams, or apps) that can merge the branch
  # authorized_dismissal_actors_only: Whether the branch restricts who can dismiss reviews
  def serialize(entity, required_status_checks:, authorized_actors_only:, authorized_actor_names:, authorized_dismissal_actors_only:)
    serialized = {
      id: entity.id,
      repository_id: entity.repository_id,
      name: entity.name,
      created_at: entity.created_at,
      updated_at: entity.updated_at,
      pull_request_reviews_enforcement_level: entity.pull_request_reviews_enforcement_level,
      required_approving_review_count: entity.required_approving_review_count,
      dismiss_stale_reviews_on_push: entity.dismiss_stale_reviews_on_push,
      require_code_owner_review: entity.require_code_owner_review,
      authorized_dismissal_actors_only: authorized_dismissal_actors_only,
      ignore_approvals_from_contributors: entity.ignore_approvals_from_contributors,
      required_status_checks: required_status_checks || [],
      required_status_checks_enforcement_level: entity.required_status_checks_enforcement_level,
      strict_required_status_checks_policy: entity.strict_required_status_checks_policy,
      signature_requirement_enforcement_level: entity.signature_requirement_enforcement_level,
      linear_history_requirement_enforcement_level: entity.linear_history_requirement_enforcement_level,
      admin_enforced: entity.admin_enforced,
      create_protected: entity.create_protected_enabled?,
      allow_force_pushes_enforcement_level: entity.allow_force_pushes_enforcement_level,
      allow_deletions_enforcement_level: entity.allow_deletions_enforcement_level,
      merge_queue_enforcement_level: entity.merge_queue_enforcement_level,
      required_deployments_enforcement_level: entity.required_deployments_enforcement_level,
      required_conversation_resolution_level: entity.required_review_thread_resolution_enforcement_level,
      authorized_actors_only: authorized_actors_only,
      authorized_actor_names: authorized_actor_names || [],
      require_last_push_approval: entity.require_last_push_approval,
      lock_branch_enforcement_level: entity.lock_branch_enforcement_level,
    }
    entity.async_repository.then do |repo|
      serialized = serialized.merge(lock_allows_fork_syncing: entity.lock_allows_fetch_and_merge?) if repo&.fork?
    end
    serialized
  end
end
