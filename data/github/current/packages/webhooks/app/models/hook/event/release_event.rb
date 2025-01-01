# typed: true
# frozen_string_literal: true

class Hook::Event::ReleaseEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  event_attr :release_id, :action, :actor_id, required: true
  event_attr :changes

  def self.description(desc = nil)
    actions = [
      :created,
      :edited,
      :published,
      :unpublished,
      :deleted,
    ]

    @description = "Release #{actions.to_sentence(last_word_connector: ", or ")}."
  end

  def release
    @release ||= Releases::Public.load_release(release_id)
  end

  def target_repository
    release.try(:repository)
  end

  def actor
    @actor ||= User.find_by(id: actor_id)
  end

  def deliverable?
    target_repository.present?
  end

  def changes
    return unless changes_attr

    {}.tap do |changes_hash|
      changes_hash[:name] = { from: changes_attr[:old_name] } if name_changed?
      changes_hash[:body] = { from: changes_attr[:old_body] } if body_changed?
      changes_hash[:tag_name]    = { from: changes_attr[:old_tag_name] } if tag_name_changed?
      changes_hash[:make_latest] = { to: changes_attr[:make_latest] } if latest_changed?
    end
  end

  private

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def name_changed?
    changes_attr[:old_name]
  end

  def body_changed?
    changes_attr[:old_body]
  end

  def tag_name_changed?
    changes_attr[:old_tag_name]
  end

  def latest_changed?
    changes_attr[:make_latest]
  end
end
