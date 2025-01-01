# typed: true
# frozen_string_literal: true

class Hook::Event::RepositoryImportEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  description "Repository import succeeded, failed, or cancelled."

  event_attr :status, :repository_id, :actor_id, required: true

  # This is still present here since we need to be able to disable this on GHE.
  feature_flag :porter_webhooks

  def self.feature_flagged?
    !GitHub.porter_available?
  end

  def target_repository
    @repo ||= Repository.find_by(id: repository_id)
  end

  def actor
    @actor ||= User.find_by(id: actor_id)
  end

  def deliverable?
    target_repository.present? && actor.present?
  end
end
