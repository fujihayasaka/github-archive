# typed: true
# frozen_string_literal: true

require "github/transitions/20250319154101_backfill_app_management_with_rbac"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations

class NewRunBackfillAppManagementWithRbac < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Iam)

  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::BackfillAppManagementWithRbac.new(arguments)
    transition.run
  end

  def self.down
  end
end

# rubocop:enable GitHub/ConnectionClassPresentInMigration
