# typed: true
# frozen_string_literal: true

class Hook::Event::ForkEvent < Hook::Event
  supports_targets Business, *DEFAULT_TARGETS
  description "Repository forked."

  event_attr :fork_repository_id, required: true

  def fork_repository
    @fork_repository ||= Repositories::Public.find_active(fork_repository_id)
  end

  def parent_repository
    fork_repository&.parent
  end

  def target_repository
    parent_repository
  end

  # TODO: make this the user who created the fork
  # not the fork owner.
  def actor
    fork_repository.owner
  end

  def deliverable?
    target_repository.present?
  end
end
