# typed: true
# frozen_string_literal: true

class Hook::Event::DeployKeyEvent < Hook::Event

  supports_targets *DEFAULT_TARGETS
  event_attr :repository_id, :key_id, :action, required: true
  event_attr :actor_id

  description "A deploy key is created or deleted from a repository."

  def actor
    @actor ||= User.find_by(id: actor_id) || User.ghost
  end

  def key
    @key ||= PublicKey.find_by(id: key_id)
  end

  def target_repository
    @target_repository ||= Repository.find_by(id: repository_id)
  end

  def deliverable?
    key.present? && actor.present? && target_repository.present?
  end
end
