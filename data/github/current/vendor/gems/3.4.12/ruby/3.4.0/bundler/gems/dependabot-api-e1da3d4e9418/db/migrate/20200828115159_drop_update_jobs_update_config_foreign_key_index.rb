# frozen_string_literal: true

class DropUpdateJobsUpdateConfigForeignKeyIndex < ActiveRecord::Migration[6.0]
  def change
    remove_index :update_jobs, :update_config_id
  end
end
