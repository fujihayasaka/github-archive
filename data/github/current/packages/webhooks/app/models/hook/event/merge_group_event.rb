# typed: strict
# frozen_string_literal: true

class Hook::Event::MergeGroupEvent < Hook::Event
  include GitHub::Memoizer

  supports_targets(*DEFAULT_TARGETS)

  high_priority

  # Stands in for a MergeQueueEntry at the head of a group that has already
  # been destroyed.
  class MergeGroupProps < T::Struct
    include GitHub::Memoizer

    const :pull_request_id, T.nilable(Integer)
    const :qualified_head_ref, T.nilable(String)
    const :head_sha, T.nilable(String)
    const :base_sha, T.nilable(String)

    sig { returns(T.nilable(PullRequest)) }
    memoize def pull_request
      PullRequest.find_by(id: pull_request_id)
    end

    sig { returns(T.nilable(Repository)) }
    def repository
      pull_request&.repository
    end
  end

  sig { returns(String) }
  def self.description
    "Merge Group requested checks, or was destroyed."
  end

  event_attr :action, :actor_id, required: true
  event_attr :merge_group_entry_id, :merge_group_props, :destroyed_reason

  sig { returns(T.nilable(T.any(MergeGroupProps, MergeQueueEntry))) }
  memoize def entry
    qualified_head_ref, head_sha, base_sha, pull_request_id = merge_group_props&.values_at(
      "qualified_head_ref", "head_sha", "base_sha", "pull_request_id"
    )

    if qualified_head_ref || head_sha || base_sha || pull_request_id
      MergeGroupProps.new(pull_request_id:, qualified_head_ref:, head_sha:, base_sha:)
    else
      MergeQueueEntry.find_by(id: merge_group_entry_id)
    end
  end

  sig { returns(T.nilable(User)) }
  memoize def actor
    User.find_by(id: actor_id)
  end

  sig { returns(T.nilable(Repository)) }
  memoize def target_repository
    entry&.repository
  end

  sig { returns(T::Boolean) }
  def deliverable?
    entry.present? && target_repository.present?
  end

  private

  sig { void }
  def validate_required_attributes
    super

    if action == :destroyed && attributes[:merge_group_props].blank?
      raise MissingRequiredAttribute.new(self.class.name, :merge_group_props)
    elsif action == :checks_requested && (attributes[:merge_group_entry_id].blank? && attributes[:merge_group_props].blank?)
      raise MissingRequiredAttribute.new(self.class.name, :merge_group_entry_id)
    end
  end
end
