# typed: false
# frozen_string_literal: true

class Hook::Event::ProjectCardEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Project card created, updated, or deleted."

  event_attr :action, :project_card_id, :actor_id, required: true
  event_attr :changes, :after_id

  def project_card
    @project_card ||= ProjectCard.find_by_id(project_card_id)
  end

  def project
    return unless project_card.present?
    project_card.project
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
    project_card.present? && project.present?
  end

  def changes
    return unless changes_attr

    {}.tap do |changes_hash|
      changes_hash[:note] = { from: changes_attr[:old_note] } if note_changes?
      changes_hash[:column_id] = { from: changes_attr[:old_column_id] } if column_changes?
    end
  end

  def self.visible_for?(user, target)
    org = nil
    if target.is_a?(Organization)
      org = target
    elsif target.is_a?(Repository)
      org = target.organization
    end

    ProjectsClassicSunset.projects_classic_ui_enabled?(user, org: org)
  end

  private

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def column_changes?
    changes_attr.has_key?(:old_column_id) && changes_attr[:column_id]
  end

  def note_changes?
    changes_attr.has_key?(:old_note) && changes_attr.has_key?(:note)
  end
end
