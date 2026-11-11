# typed: strict
# frozen_string_literal: true

class Hook::Event::SubIssuesEvent < Hook::Event
  include GitHub::Memoizer

  supports_targets *DEFAULT_TARGETS
  description "Sub-issues added or removed, and parent issues added or removed."

  event_attr :action, :parent_issue_id, :child_issue_id, required: true
  event_attr :actor_id, :audit_only

  sig { returns(T::Array[Symbol]) }
  def self.actions
    [
      :sub_issue_added,
      :sub_issue_removed,
      :parent_issue_added,
      :parent_issue_removed,
    ]
  end

  sig { params(_user: T.nilable(User), target: T.any(Organization, Repository)).returns(T::Boolean) }
  def self.visible_for?(_user, target)
    true
  end

  sig { returns(T.nilable(Issue)) }
  memoize def sub_issue
    Issue.find_by(id: child_issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  sig { returns(T.nilable(Repository)) }
  memoize def sub_issue_repository
    if sub_issue_event?
      sub_issue&.repository
    end
  end

  sig { returns(T.nilable(Issue)) }
  memoize def parent_issue
    Issue.find_by(id: parent_issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  sig { returns(T.nilable(Repository)) }
  memoize def parent_issue_repository
    if parent_issue_event?
      parent_issue&.repository
    end
  end

  sig { returns(T.nilable(Repository)) }
  memoize def target_repository
    if parent_issue_event?
      sub_issue&.repository
    # If it's a sub-issue event
    else
      parent_issue&.repository
    end
  end

  sig { returns(T.nilable(User)) }
  memoize def actor
    User.find_by(id: actor_id)
  end

  # Prevents the event from being delivered to the hookshot server
  sig { returns(T::Boolean) }
  def audit_only?
    !!audit_only
  end

  sig { returns(T::Boolean) }
  memoize def deliverable?
    !audit_only? &&
      sub_issue.present? &&
      parent_issue.present? &&
      (sub_issue_repository.present? || parent_issue_repository.present?) &&
      target_repository.present? &&
      actor.present?
  end

  sig { returns(T::Boolean) }
  memoize private def parent_issue_event?
    [:parent_issue_added, :parent_issue_removed].include?(action.to_sym)
  end

  sig { returns(T::Boolean) }
  memoize private def sub_issue_event?
    [:sub_issue_added, :sub_issue_removed].include?(action.to_sym)
  end
end
