# typed: true
# frozen_string_literal: true

class Hook::Event::WorkflowDispatchEvent < Hook::Event
  supports_targets Integration

  description "A manual workflow run is requested."

  event_attr :repository_id, :ref, :actor_id, :workflow, required: true
  event_attr :inputs

  # The repository that this event is associated with. The delivery
  # system will use this to find subscribed repository and organization
  # hooks.
  #
  # This will automatically be included in hook payloads.
  def target_repository
    @target_repository ||= Repositories::Public.find_active(repository_id)
  end

  # The user who performed the action.
  #
  # This will automatically be included in hook payloads.
  def actor
    @actor ||= User.find(actor_id)
  end

  def deliverable?
    target_repository.present?
  end
end
