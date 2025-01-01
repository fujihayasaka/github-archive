# typed: true
# frozen_string_literal: true

class Hook::Payload::RepositoryTopicPayload < Hook::Payload

  def to_payload_hash
    {}.tap do |payload|
      payload[:action] = hook_event.action
      payload[:topic] = topic_hash
    end
  end

  private

  def topic_hash
    topic = hook_event.topic
    repository_topic = hook_event.repository_topic
    return nil unless topic

    {
      name: topic.name,
      actor_html_url: actor_html_url_for(repository_topic),
      state: repository_topic&.state,
      created_at: Api::Serializer.time(topic.created_at),
      updated_at: Api::Serializer.time(topic.updated_at),
    }
  rescue => e
    GitHub.logger.error("Error serializing topic", error: e.message, topic_id: hook_event.repository_topic&.topic_id)
    nil
  end

  def actor_html_url_for(repository_topic)
    return nil unless repository_topic&.user

    api_serialize(:simple_user_hash, repository_topic.user)[:html_url]
  end
end
