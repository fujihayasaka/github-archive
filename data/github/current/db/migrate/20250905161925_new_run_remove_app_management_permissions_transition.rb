# typed: true
# frozen_string_literal: true

require "github/transitions/20250501035014_remove_app_management_permissions"

class NewRunRemoveAppManagementPermissionsTransition < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Permissions)

  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::RemoveAppManagementPermissions.new(arguments)
    transition.run
  end

  def self.down
  end
end
