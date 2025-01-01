# typed: true
# frozen_string_literal: true
#
class Hook::Event::MergeQueueEntryEvent < Hook::Event
  supports_targets Integration

  description "Merge Queue entry added"

  feature_flag :merge_queue

  event_attr :merge_queue_entry_id, :action, required: true
  event_attr :message, :actor_id, :pull_request_id, :merge_queue_id

  def actor
    if actor_id
      @actor ||= User.find_by(id: actor_id)
    else
      merge_queue_entry&.enqueuer
    end
  end

  def merge_queue
    if merge_queue_id
      @merge_queue ||= MergeQueue.find_by(id: merge_queue_id)
    else
      merge_queue_entry&.queue
    end
  end

  def merge_queue_entry
    return nil if action == :deleted
    return @merge_queue_entry if defined?(@merge_queue_entry)
    @merge_queue_entry = MergeQueueEntry.find_by(id: merge_queue_entry_id)
  end

  def pull_request
    if pull_request_id
      @pull_request ||= PullRequest.find_by(id: pull_request_id)
    else
      merge_queue_entry&.pull_request
    end
  end

  def target_repository
    merge_queue&.repository
  end

  # Hook::Event checks this for feature_flag_enabled? but we want to
  # enable the merge_queue flag per repo not per org. This means that
  # having a target_organization set will prevent the event from being
  # delivered.
  def target_organization
    nil
  end
end
