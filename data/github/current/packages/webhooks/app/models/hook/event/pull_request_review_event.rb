# typed: true
# frozen_string_literal: true

class Hook::Event::PullRequestReviewEvent < Hook::Event
  extend PullRequests::Copilot::CodeReviewHelper

  supports_targets *DEFAULT_TARGETS

  description "Pull request review submitted, edited, or dismissed."

  event_attr :action, :pull_request_review_id, required: true
  event_attr :changes, :actor_id

  def self.queue(action:, pull_request_review_id:, actor_id: nil, changes: nil, triggered_at: nil, event_guid: nil, flags: nil)
    return if is_empty_copilot_review?(actor_id:, pull_request_review_id:)
    super(action:, pull_request_review_id:, actor_id:, changes:, triggered_at:, event_guid:, flags:)
  end

  def changes
    changes_attr = attributes.with_indifferent_access[:changes]
    return unless changes_attr

    {}.tap do |changes_hash|
      changes_hash[:body] = { from: changes_attr[:old_body] } if changes_attr[:old_body]
    end
  end

  def pull_request_review
    @pull_request_review ||= PullRequestReview.find_by(id: pull_request_review_id)
  end

  def pull_request
    pull_request_review.try(:pull_request)
  end

  def target_repository
    pull_request_review.try(:repository)
  end

  def actor
    return @actor if defined?(@actor)

    @actor = if actor_id
      User.find_by(id: actor_id) || User.ghost
    else
      pull_request_review.try(:user)
    end
  end
end
