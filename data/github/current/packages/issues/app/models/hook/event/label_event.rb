# typed: true
# frozen_string_literal: true

class Hook::Event::LabelEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  description "Label created, edited or deleted."

  event_attr :action, :label_id, :actor_id, required: true
  event_attr :changes

  def label
    @label ||= Label.find_by(id: label_id)
  end

  def actor
    @actor ||= User.find_by(id: actor_id)
  end

  def deliverable?
    target_repository.present?
  end

  def target_repository
    return unless label
    label.repository
  end

  def changes
    return unless changes_attr

    old_name  = changes_attr["old_name"]
    old_color = changes_attr["old_color"]
    old_description = changes_attr["old_description"]

    {}.tap do |hash|
      hash[:name] = { from: old_name } if old_name
      hash[:color] = { from: old_color } if old_color
      hash[:description] = { from: old_description } if old_description
    end
  end

  private

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end
end
