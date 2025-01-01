# typed: true
# frozen_string_literal: true

# this handles topic events based of packages/repositories/app/models/topic
class Hook::Event::RepositoryTopicEvent < Hook::Event
  supports_targets Repository
  description "A topic is created or deleted."

  event_attr :action, :repository_topic_id, required: true
  event_attr :actor_id

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

  def repository_topic
    @repository_topic ||= RepositoryTopic.find_by(id: repository_topic_id)
  end

  def topic
    repository_topic&.topic
  end

  def actor
    @actor ||= User.find_by(id: actor_id)
  end

  def target_repository
    repository_topic&.repository
  end

  # Events which need a mechanism for bailing out in certain cases should
  # define `deliverable?`. If it returns false, hooks won't be delivered
  # for this event.
  def deliverable?
    target_repository.present?
  end
end
