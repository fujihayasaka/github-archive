# typed: true
# frozen_string_literal: true

class RolePermission < ApplicationRecord::Iam
  validates :role_id, presence: true
  validate  :valid_fgp
  validate  :valid_action

  belongs_to :role
  belongs_to :fine_grained_permission

  scope :custom_roles_enabled, -> {
    where(action: Permissions::FineGrainedPermissionIm.where(custom_roles_enabled: true).map(&:action))
  }

  def valid_fgp
    r = role
    return if r.nil?

    fgp = Permissions::FineGrainedPermissionIm.find(action)
    return if fgp.nil? # for sorbet
    return if (r.target_type.nil? || fgp.target_type.nil?) && r.preset? # nil is used to bypass validation for legacy preset roles

    unless fgp.target_type.in?(r.allowed_permissions_types)
      errors.add(:fine_grained_permission, "'#{fgp.action}' has a target type of '#{fgp.target_type}' which does not match any role allowed target types '#{r.allowed_permissions_types}'")
    end
  end

  # will valid_action and/or the use of Permissions::FineGrainedPermissionIm prevent removing FGPs?
  # - No, transitions use raw sql statements to insert fpgs, role_permissions, and roles
  def valid_action
    unless action.present?
      errors.add(:action, "must be present")
      return
    end

    unless Permissions::FineGrainedPermissionIm.where(actions: action).any?
      errors.add(:action, "must be valid")
    end
  end
end
