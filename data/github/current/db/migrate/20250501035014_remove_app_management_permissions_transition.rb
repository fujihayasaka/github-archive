# typed: true
# frozen_string_literal: true

require "github/transitions/20250501035014_remove_app_management_permissions"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class RemoveAppManagementPermissionsTransition < ActiveRecord::Migration[8.1]
  #NO-OP
  def self.up
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
