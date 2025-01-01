# typed: true
# frozen_string_literal: true

class Hook::Event::CreateEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  display_name "branch or tag creation"
  description "Branch or tag created."

  event_attr :repository_id, :ref, required: true
  event_attr :pusher_id # TODO make this required once we're reliably tracking pushers

  def repository
    @repository ||= Repository.find_by(id: repository_id)
  end
  alias_method :target_repository, :repository

  def ref_type
    ref.starts_with?("refs/tags") ? :tag : :branch
  end

  def branch_or_tag_name
    @branch_or_tag_name ||= ref.split("/", 3).last
  end

  def pusher
    return unless pusher_id.present?

    @pusher ||= User.find(pusher_id)
  end

  def pusher_type
    pusher.present? ? :user : :deploy_key
  end

  def actor
    @actor ||= (pusher || repository.created_by_user || repository.owner)
  end

  def deliverable?
    target_repository.present?
  end
end
