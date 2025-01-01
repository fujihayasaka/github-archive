# typed: false
# frozen_string_literal: true

class Hook::Event::ProjectColumnEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Project column created, updated, moved or deleted."

  event_attr :action, :project_column_id, :actor_id, required: true
  event_attr :changes, :after_id

  def project_column
    @project_column ||= ProjectColumn.find_by_id(project_column_id)
  end

  def project
    return unless project_column.present?
    project_column.project
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
    project_column.present? && project.present?
  end

  def changes
    return unless changes_attr

    {}.tap do |changes_hash|
      changes_hash[:name] = { from: changes_attr[:old_name] } if name_changes?
    end
  end

  def self.visible_for?(user, target)
    false
  end

  private

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def name_changes?
    changes_attr[:old_name] && changes_attr[:name]
  end
end
