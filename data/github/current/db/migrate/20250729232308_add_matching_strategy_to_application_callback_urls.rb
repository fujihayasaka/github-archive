# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/MigrationCrossSchemaDomainConnection
# rubocop:disable GitHub/EnsureDomainIsolationInMigration

class AddMatchingStrategyToApplicationCallbackUrls < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IntegrationsCollab)

  def up
    change_table :application_callback_urls, bulk: true do |t|
      # Added at the behest of a linter asking to upgrade unrelated ID fields to BIGINT:
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :application_id, :bigint, unsigned: true, null: false

      # The new enum for the changed behavior in the model.
      t.column :matching_strategy, :integer, default: 0, null: false
    end
  end

  def down
    change_table :application_callback_urls, bulk: true do |t|
      t.change :id, :integer, null: false, auto_increment: true
      t.change :application_id, :integer, unsigned: true, null: false
      t.remove :matching_strategy
    end
  end
end
