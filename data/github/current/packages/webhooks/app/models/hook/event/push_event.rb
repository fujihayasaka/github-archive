# typed: true
# frozen_string_literal: true

class Hook::Event::PushEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Git push to a repository."

  event_attr :repo, :before, :after, :ref, required: true
  event_attr :pusher, :target_hook, :pushed_at

  def repository
    repo
  end
  alias_method :target_repository, :repository

  alias_method :actor, :pusher

  # Override subscribed_hooks to only include the target hook if specified.
  # This is used for testing hook deliveries.
  def subscribed_hooks
    if target_hook
      @target_hooks ||= [target_hook]
    else
      super
    end
  end

  def deliverable?
    target_repository.present?
  end
end
