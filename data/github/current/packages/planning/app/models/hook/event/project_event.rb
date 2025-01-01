# typed: false
# frozen_string_literal: true

class Hook::Event::ProjectEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Project created, updated, or deleted."

  event_attr :action, :project_id, :actor_id, required: true
  event_attr :changes

  def project
    @project ||= Project.find_by_id(project_id)
  end

  def target_repository
    return unless deliverable?
    if project.owner_type == "Repository"
      project.owner
    else
      nil
    end
  end

  def target_organization
    return unless deliverable?
    if project.owner_type == "Organization"
      project.owner
    else
      super
    end
  end

  def actor
    @actor ||= User.find_by_id(actor_id)
  end

  def deliverable?
    project.present?
  end

  def changes
    return unless changes_attr && (body_changes? || name_changes?)

    {}.tap do |changes_hash|
      changes_hash[:name] = { from: changes_attr[:old_name] } if name_changes?
      changes_hash[:body] = { from: changes_attr[:old_body] } if body_changes?
    end
  end

  def self.visible_for?(user, target)
    false
  end

  private

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def body_changes?
    changes_attr[:old_body] && changes_attr[:body]
  end

  def name_changes?
    changes_attr[:old_name] && changes_attr[:name]
  end
end
