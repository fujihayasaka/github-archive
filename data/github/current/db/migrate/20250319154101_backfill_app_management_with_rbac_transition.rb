# typed: true
# frozen_string_literal: true

require "github/transitions/20250319154101_backfill_app_management_with_rbac"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillAppManagementWithRbacTransition < ActiveRecord::Migration[8.1]
  #NO-OP
  def self.up
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
