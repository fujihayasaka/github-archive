# typed: true
# frozen_string_literal: true

class Hook::Event::MilestoneEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  description "Milestone created, closed, opened, edited, or deleted."

  event_attr :action, :milestone_id, :actor_id, required: true
  event_attr :changes

  def actor
    @actor ||= User.find(actor_id)
  end

  def milestone
    @milestone ||= Milestone.find(milestone_id)
  end

  def target_repository
    milestone.repository
  end

  def changes
    return unless changes_attr

    {}.tap do |changes_hash|
      changes_hash[:description] = { from: changes_attr[:old_description] } if description_changed?
      changes_hash[:due_on] = { from: changes_attr[:old_due_on] } if due_on_changed?
      changes_hash[:title] = { from: changes_attr[:old_title] } if title_changed?
    end
  end

  def deliverable?
    target_repository.present?
  end

  private

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def description_changed?
    changes_attr[:old_description]
  end

  def due_on_changed?
    changes_attr[:old_due_on]
  end

  def title_changed?
    changes_attr[:old_title]
  end
end
