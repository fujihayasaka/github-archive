# typed: true
# frozen_string_literal: true

class Hook::Event::RepositoryDispatchEvent < Hook::Event
  supports_targets Integration

  description "When a message is dispatched from a repository."

  event_attr :repository_id, :action, :branch, :actor_id, required: true
  event_attr :client_payload, :user_action

  # The repository that this event is associated with. The delivery
  # system will use this to find subscribed repository and organization
  # hooks.
  #
  # This will automatically be included in hook payloads.
  def target_repository
    @target_repository ||= Repositories.domain.active_by_id(repository_id)
  end

  # The user who performed the action.
  #
  # This will automatically be included in hook payloads.
  def actor
    @actor ||= User.find(actor_id)
  end

  def deliverable?
    target_repository&.present?
  end
end
