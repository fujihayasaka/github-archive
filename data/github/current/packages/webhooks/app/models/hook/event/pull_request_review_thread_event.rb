# typed: true
# frozen_string_literal: true

class Hook::Event::PullRequestReviewThreadEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  description "A pull request review thread was resolved or unresolved."

  event_attr :thread_id, :pull_request_id, :action, :actor_id, required: true

  def thread
    return @thread if defined?(@thread)

    @thread = PullRequestReviewThread.includes(:repository, :pull_request, :resolver).find_by(id: thread_id)
  end

  def target_repository
    return @target_repository if defined?(@target_repository)

    @target_repository = thread&.repository
  end

  def pull_request
    return @pull_request if defined?(@pull_request)

    @pull_request = thread&.pull_request
  end

  def actor
    return @actor if defined?(@actor)

    @actor = User.find_by(id: actor_id)
  end
end
