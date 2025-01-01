# typed: true
# frozen_string_literal: true

class Hook::Event::GollumEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  display_name "wiki"
  description "Wiki page updated."

  event_attr :actor_id, :repository_id, :updates, required: true

  def repository
    @repository ||= Repositories::Public.find_active(repository_id)
  end
  alias_method :target_repository, :repository

  def actor
    @actor ||= User.find(actor_id)
  end

  def updates
    @updates ||= attributes[:updates].map(&:symbolize_keys)
  end

  def deliverable?
    target_repository.present?
  end
end
