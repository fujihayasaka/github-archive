# typed: strict
# frozen_string_literal: true

module Issue::IssueTypeDependency
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { Issue }

  included do
    T.bind(self, T.class_of(Issue))
    after_save :trigger_issue_type_change_events, if: :saved_change_to_issue_type_id? # rubocop:todo GitHub/AvoidActiveRecordCallbacks

    validate :ensure_owner_has_issue_types_enabled,
      on: [:create, :update],
      if: :should_validate?

    validate :ensure_valid_issue_type,
      on: [:create, :update],
      if: :should_validate?
  end

  sig { params(new_issue_type: IssueType, old_issue_type: T.nilable(IssueType)).void }
  def trigger_typed_event(new_issue_type, old_issue_type)
    return if new_issue_type.blank?

    instrument :typed, { issue: self, actor: modifying_user, issue_type_id: new_issue_type.id }

    GlobalInstrumenter.instrument "issue.typed", {
      actor: modifying_user,
      repository: repository,
      issue: self,
      issue_type: new_issue_type,
      prev_issue_type: old_issue_type
    }
  end

  sig { params(old_issue_type: IssueType).void }
  def trigger_untyped_event(old_issue_type)
    return if old_issue_type.blank?

    instrument :untyped, { issue: self, actor: modifying_user, issue_type_id: old_issue_type.id  }

    GlobalInstrumenter.instrument "issue.untyped", {
      actor: modifying_user,
      repository: repository,
      issue: self,
      issue_type: old_issue_type,
    }
  end

  sig { void }
  def trigger_issue_type_change_events
    old_issue_type_id, new_issue_type_id = saved_change_to_issue_type_id
    if old_issue_type_id.present? && !new_issue_type_id.present?
      old_issue_type = IssueType.find_by(id: old_issue_type_id)
      trigger_untyped_event(old_issue_type) if old_issue_type
    elsif new_issue_type_id.present?
      new_issue_type = IssueType.find_by(id: new_issue_type_id)
      # When a new issue type is present -AND- an old issue type is present, include the old issue type in the event
      # to support changed events in the issue timeline
      old_issue_type = IssueType.find_by(id: old_issue_type_id) if old_issue_type_id.present?
      trigger_typed_event(new_issue_type, old_issue_type) if new_issue_type
    end
  end

  sig { void }
  def ensure_owner_has_issue_types_enabled
    repo_owner = T.must(repository).owner
    return if T.must(repo_owner).issue_types_enabled?

    errors.add(:base, :issue_type_is_not_a_valid_attribute)
  end

  sig { void }
  def ensure_valid_issue_type
    T.bind(self, Issue)
    return unless self.issue_type_id_changed?

    repo_owner = T.must(repository).owner

    found_issue_type = T.must(repo_owner).issue_types.find_by(id: issue_type_id)

    if found_issue_type.nil?
      errors.add(:issue_type_id, :not_found)
      return
    end

    unless found_issue_type.enabled?
      errors.add(:issue_type_id, :not_enabled)
    end
  end

  sig { returns(T::Boolean) }
  private def should_validate?
    return true if issue_type_id? && issue_type_id_changed?

    false
  end
end
