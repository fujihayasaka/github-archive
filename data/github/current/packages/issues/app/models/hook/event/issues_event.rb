# typed: true
# frozen_string_literal: true

class Hook::Event::IssuesEvent < Hook::Event
  include GitHub::Memoizer

  supports_targets *DEFAULT_TARGETS

  # we also gate it with `issue_types` FF checks on org in the feature_flag_enabled method below
  feature_flag :issue_types, actions: [:typed, :untyped]

  def self.description(desc = nil)
    actions = [
      :opened,
      :edited,
      :deleted,
      :transferred,
      :pinned,
      :unpinned,
      :closed,
      :reopened,
      :assigned,
      :unassigned,
      :labeled,
      :unlabeled,
      :milestoned,
      :demilestoned,
      :locked,
      :unlocked,
    ]

    @description = "Issue #{actions.to_sentence(last_word_connector: ", or ")}."
  end

  event_attr :action, :issue_id, :actor_id, required: true
  event_attr :label_id, :assignee_id, :changes, :milestone_id, :issue_type_id

  # Use find instead of find_by to raise RecordNotFound when the issue doesn't exist.
  # This allows DeliverHookEventJob to handle the race condition via HookDeliveryRaceConditionCheckJob
  # when the issue hasn't been committed to the database yet.
  # See https://github.com/github/issues/issues/19214
  memoize def issue
    Issue.find(issue_id)
  end

  def target_repository
    issue&.repository
  end

  def feature_flag_enabled?
    return true unless feature_flagged?
    return true unless flagged_actions.include?(self.try(:action)) if flagged_actions.present?
    # We feature flag the new typed & untyped actions as specified in the feature_flag `issue_types`
    # We also gate the specified actions payload further with `issue_types` FF check for the org
    self.issue_types_enabled
  end

  # For the issue.opened action we also want to include the issue_type in the payload if FF is enabled
  # so we make this method available on the hook_event and check it in issues_payload
  def issue_types_enabled
    target_organization&.issue_types_enabled?
  end

  memoize def actor
    User.find(actor_id)
  end

  # The label which was labeled/unlabeled
  memoize def label
    Label.find_by(id: label_id)
  end

  # The milestone which was milestoned/demilestoned
  memoize def milestone
    Milestone.find_by(id: milestone_id)
  end

  # The issue_type which was typed/untyped
  memoize def type
    IssueType.find_by(id: issue_type_id)
  end

  # The user which was assigned/unassigned
  memoize def assignee
    User.find_by(id: assignee_id)
  end

  def changes
    return unless changes_attr

    GitHub.dogstats.increment("hooks.stale", tags: ["hook_event:issues"]) if stale_changes?

    {}.tap do |changes_hash|
      changes_hash[:body] = { from: changes_attr[:old_body] || "" } if body_changes?
      changes_hash[:title] = { from: changes_attr[:old_title] } if title_changes?
    end
  end

  def deliverable?
    # Issue accessor raises RecordNotFound if the issue doesn't exist,
    # which allows HookDeliveryRaceConditionCheckJob to retry.
    target_repository.present?
  end

  memoize def source_issue_transfer
    IssueTransfer.includes(:old_issue, :old_repository).find_by(old_issue_id: issue_id)
  end

  memoize def target_issue_transfer
    IssueTransfer.includes(:new_issue, :new_repository).find_by(new_issue_id: issue_id)
  end

  private

  def stale_changes?
    return unless body_changes? || title_changes?

    (body_changes? && changes_attr[:old_body] == issue.body) || (title_changes? && changes_attr[:old_title] == issue.title)
  end

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def body_changes?
    changes_attr[:old_body] || issue.body
  end

  def title_changes?
    changes_attr[:old_title] && changes_attr[:title]
  end
end
