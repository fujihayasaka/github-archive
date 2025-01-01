# typed: true
# frozen_string_literal: true

class Hook::Event::DeleteEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  display_name "branch or tag deletion"
  description "Branch or tag deleted."

  event_attr :repository_id, required: true
  event_attr :ref, :pusher_id

  def repository
    @repository ||= Repositories::Public.find_active(repository_id)
  end
  alias_method :target_repository, :repository

  def ref_type
    return :unknown unless ref

    ref.starts_with?("refs/tags") ? :tag : :branch
  end

  def branch_or_tag_name
    return unless ref

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
