# typed: strict
# frozen_string_literal: true

class Hook::Event::IssueDependenciesEvent < Hook::Event
  include GitHub::Memoizer

  feature_flag :issue_dependencies do |_flag, actor|
    # Skip feature flag check for enterprise environments
    if GitHub.enterprise?
      true
    else
      # For GitHub.com, check the feature flag
      FeatureFlag.vexi.enabled?(:issue_dependencies, actor, default: false)
    end
  end

  supports_targets *DEFAULT_TARGETS
  description "Issue dependencies - such as blocked by or blocking - added or removed."

  event_attr :action, :blocked_issue_id, :blocking_issue_id, required: true
  event_attr :actor_id

  sig { returns(T::Array[Symbol]) }
  def self.actions
    [
      :blocked_by_added,
      :blocking_added,
      :blocked_by_removed,
      :blocking_removed,
    ]
  end

  sig { params(_user: T.nilable(User), target: T.any(Organization, Repository)).returns(T::Boolean) }
  def self.visible_for?(_user, target)
    IssueDependenciesFeature.enabled?(target)
  end

  sig { returns(T.nilable(Issue)) }
  memoize def blocked_issue
    Issue.find_by(id: blocked_issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  sig { returns(T.nilable(Repository)) }
  memoize def blocked_issue_repository
    # Don't set the repository for blocked by events, since it will be the same as the target_repository
    if blocking_issue_event?
      blocked_issue&.repository
    end
  end

  sig { returns(T.nilable(Issue)) }
  memoize def blocking_issue
    Issue.find_by(id: blocking_issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  sig { returns(T.nilable(Repository)) }
  memoize def blocking_issue_repository
    # Don't set the repository for blocking events, since it will be the same as the target_repository
    if blocked_by_issue_event?
      blocking_issue&.repository
    end
  end

  sig { returns(T.nilable(Repository)) }
  memoize def target_repository
    if blocked_by_issue_event?
      blocked_issue&.repository
    elsif blocking_issue_event?
      blocking_issue&.repository
    end
  end

  sig { returns(T.nilable(User)) }
  memoize def actor
    User.find_by(id: actor_id)
  end

  sig { returns(T::Boolean) }
  memoize def deliverable?
    blocked_issue.present? &&
      blocking_issue.present? &&
      (blocked_issue_repository.present? || blocking_issue_repository.present?) &&
      target_repository.present? &&
      actor.present?
  end

  sig { returns(T::Boolean) }
  memoize private def blocked_by_issue_event?
    [:blocked_by_added, :blocked_by_removed].include?(action.to_sym)
  end

  sig { returns(T::Boolean) }
  memoize private def blocking_issue_event?
    [:blocking_added, :blocking_removed].include?(action.to_sym)
  end
end
