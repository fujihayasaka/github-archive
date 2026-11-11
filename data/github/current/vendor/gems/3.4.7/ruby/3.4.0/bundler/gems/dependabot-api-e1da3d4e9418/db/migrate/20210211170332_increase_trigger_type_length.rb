# frozen_string_literal: true

class IncreaseTriggerTypeLength < ActiveRecord::Migration[6.0]
  def change
    change_column :update_jobs, :trigger_type, :string, null: false, default: "unknown", limit: 25 # rubocop:disable Rails/ReversibleMigration
  end
end
