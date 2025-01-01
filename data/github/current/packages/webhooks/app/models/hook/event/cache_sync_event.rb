# typed: true
# frozen_string_literal: true

class Hook::Event::CacheSyncEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS if GitHub.enterprise?

  display_name "cache sync"
  description "Cache Server sync completed."

  event_attr :repository_id, :ref_update, :cache_location, required: true

  # The action that this event represents. This is not required but is a
  # convention that we have been following. Right now it is just a hard
  # coded value, but this will allow us to extend this event in the future
  # if we ever need to.
  def action
    :synced
  end

  # Helper method to look up the repository using the id we were passed.
  def repository
    @repository ||= Repository.find_by(id: repository_id)
  end

  # The repository that this event is associated with. The delivery
  # system will use this to find subscribed repository and organization
  # hooks.
  #
  # This will automatically be included in hook payloads.
  def target_repository
    repository
  end

  # Events which need a mechanism for bailing out in certain cases should
  # define `deliverable?`. If it returns false, hooks won't be delivered
  # for this event.
  def deliverable?
    repository.present?
  end

  # The user who performed the action.
  #
  # This will automatically be included in hook payloads.
  def actor
    @actor ||= User.find_by(login: "github-enterprise")
  end
end
