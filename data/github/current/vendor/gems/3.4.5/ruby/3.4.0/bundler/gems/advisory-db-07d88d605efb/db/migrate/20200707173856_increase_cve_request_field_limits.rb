# frozen_string_literal: true

# rubocop:disable Rails/ReversibleMigration

class IncreaseCVERequestFieldLimits < ActiveRecord::Migration[6.0]
  def change
    change_column :cve_requests, :affected_versions, "varbinary(1024)", null: false
    change_column :cve_requests, :patches, "varbinary(1024)", null: false
  end
end

# rubocop:enable Rails/ReversibleMigration
