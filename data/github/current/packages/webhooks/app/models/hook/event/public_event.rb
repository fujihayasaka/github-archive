# typed: true
# frozen_string_literal: true

class Hook::Event::PublicEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  display_name "visibility changes"
  description "Repository changes from private to public."

  event_attr :repo_id, :actor_id, required: true

  def target_repository
    @repo ||= Repositories::Public.find_active(repo_id)
  end

  def actor
    @actor ||= User.find(actor_id)
  end

  def deliverable?
    target_repository.present?
  end
end
