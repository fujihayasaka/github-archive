# typed: true
# frozen_string_literal: true

class Hook::Event::SecurityAndAnalysisEvent < Hook::Event
  supports_targets(*DEFAULT_TARGETS)

  description "Code security features enabled or disabled for a repository."

  event_attr :changes, :repository_id, :actor_id, required: true

  # Maps to the 'sender' object in the event payload.
  def actor
    @actor ||= User.find_by(id: actor_id)
  end

  def target_repository
    @repository ||= Repository.find_by(id: repository_id)
  end

  def target_organization
    return nil if !target_repository
    owner = target_repository.owner
    owner.organization? ? owner : nil
  end

  def deliverable?
    !!target_repository
  end
end
