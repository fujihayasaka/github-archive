# typed: true
# frozen_string_literal: true

class Hook::Event::BranchProtectionConfigurationEvent < Hook::Event

  supports_targets *DEFAULT_TARGETS

  description "All branch protections disabled or enabled for a repository."

  event_attr :action, :actor_id, :repository_id, required: true

  def actor
    @actor ||= User.find_by(id: actor_id)
  end

  def target_repository
    @target_repository ||= begin
      repo = Repositories.domain.by_id(repository_id)
      repo&.owner # preload owner
      repo
    end
  end

  def deliverable?
    target_repository.present?
  end
end
