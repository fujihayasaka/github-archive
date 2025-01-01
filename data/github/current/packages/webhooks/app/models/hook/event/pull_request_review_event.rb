# typed: true
# frozen_string_literal: true

class Hook::Event::PullRequestReviewEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  description "Pull request review submitted, edited, or dismissed."

  event_attr :action, :pull_request_review_id, required: true
  event_attr :changes, :actor_id

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
