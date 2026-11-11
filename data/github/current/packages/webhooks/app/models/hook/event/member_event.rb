# typed: true
# frozen_string_literal: true

class Hook::Event::MemberEvent < Hook::Event
  supports_targets Business, *DEFAULT_TARGETS

  display_name "collaborator add, remove, or changed"
  description "Collaborator added to, removed from, or has changed permissions for a repository."

  event_attr :action, :actor_id, :repo_id, :user_id, required: true
  event_attr :changes

  def user
    @user ||= User.find(user_id)
  end

  def target_repository
    @repository ||= Repositories.domain.by_id(repo_id) || (
      raise ActiveRecord::RecordNotFound.new(id: repo_id, model: Repository)
    )
  end

  def actor
    return target_repository.owner unless actor_id
    @actor ||= User.find(actor_id)
  end

  def changes
    return unless changes_attr
    return unless permission_changed?

    attrs = {
      permission: {}
    }

    attrs[:permission][:from] = changes_attr[:old_permission] if old_permission_changed?
    attrs[:permission][:to] = changes_attr[:new_permission] if new_permission_changed?
    attrs[:role_name] = { to: changes_attr[:new_role_name] } if new_role_name_changed?

    attrs
  end

  def deliverable?
    target_repository.present?
  end

  private

  def changes_attr
    attributes.with_indifferent_access[:changes]
  end

  def old_permission_changed?
    changes_attr.has_key?(:old_permission)
  end

  def new_permission_changed?
    changes_attr.has_key?(:new_permission)
  end

  def new_role_name_changed?
    changes_attr.has_key?(:new_role_name) && changes_attr[:new_role_name].present?
  end

  def permission_changed?
    old_permission_changed? || new_permission_changed? || new_role_name_changed?
  end
end
