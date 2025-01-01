# typed: true
# frozen_string_literal: true

class Hook::Event::CloseIssueReferenceEvent < Hook::Event
  supports_targets Repository

  description "A close issue reference is created or deleted."

  event_attr :action, :close_issue_reference_id, :issue_id, :pull_request_id, required: true
  event_attr :pull_request_author_id, :source, :referenced_at

  def issue
    @issue ||= Issue.find_by(id: issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def pull_request
    @pull_request ||= PullRequest.find_by(id: pull_request_id)
  end

  def actor
    @actor ||= User.find_by(id: actor_id)
  end

  def target_repository
    @target_repository ||= Repositories.domain.by_id(repository_id)
  end

  def deliverable?
    target_repository.present?
  end

  # if we haven't enabled migration vnext webhooks, handle this as if it's feature flagged
  # if it's enabled, don't raise it as feature flagged so wildcard works
  def self.feature_flagged?
    !GitHub.elm_internal_webhooks_enabled?
  end

  # if migration vnext webhooks are enabled, this is visible
  def self.visible_for?(user, target)
    GitHub.elm_internal_webhooks_enabled?
  end

  def feature_flag_enabled?
    GitHub.elm_internal_webhooks_enabled?
  end
end
