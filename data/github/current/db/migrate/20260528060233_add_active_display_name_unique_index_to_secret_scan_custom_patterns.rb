# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
class AddActiveDisplayNameUniqueIndexToSecretScanCustomPatterns < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    remove_index :secret_scan_custom_patterns, name: "index_secret_scan_custom_patterns_on_owner_scope_id" if index_exists?(:secret_scan_custom_patterns, [:owner_scope_id], name: "index_secret_scan_custom_patterns_on_owner_scope_id")

    change_table(:secret_scan_custom_patterns, bulk: true) do |t|
      t.column :active_display_name, "varchar(256) GENERATED ALWAYS AS (CASE WHEN `state` = 1 THEN NULL ELSE `display_name` END) VIRTUAL" unless column_exists?(:secret_scan_custom_patterns, :active_display_name)
      t.index [:owner_scope_id, :active_display_name], unique: true, name: "uq_owner_scope_active_display_name" unless index_exists?(:secret_scan_custom_patterns, [:owner_scope_id, :active_display_name], name: "uq_owner_scope_active_display_name")
    end
  end

  def down
    remove_index :secret_scan_custom_patterns, name: "uq_owner_scope_active_display_name" if index_exists?(:secret_scan_custom_patterns, [:owner_scope_id, :active_display_name], name: "uq_owner_scope_active_display_name")

    change_table(:secret_scan_custom_patterns, bulk: true) do |t|
      t.remove :active_display_name if column_exists?(:secret_scan_custom_patterns, :active_display_name)
      t.index [:owner_scope_id], name: "index_secret_scan_custom_patterns_on_owner_scope_id" unless index_exists?(:secret_scan_custom_patterns, [:owner_scope_id], name: "index_secret_scan_custom_patterns_on_owner_scope_id")
    end
  end
end
# rubocop:enable GitHub/DoNotAddUniqueIndexToExistingColumn
