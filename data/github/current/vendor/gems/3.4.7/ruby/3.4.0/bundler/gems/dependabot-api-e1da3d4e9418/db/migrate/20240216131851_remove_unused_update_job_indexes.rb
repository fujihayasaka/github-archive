# frozen_string_literal: true

class RemoveUnusedUpdateJobIndexes < ActiveRecord::Migration[7.0]
  def change
    change_table :update_jobs, bulk: true do |t|
      t.remove_index :trigger_type, name: "index_update_jobs_on_trigger_type"
      t.remove_index :expires_at, name: "index_update_jobs_on_expires_at"
    end
  end
end
