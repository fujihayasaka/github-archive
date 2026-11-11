# frozen_string_literal: true

class AddUpdateJobsExpiresAt < ActiveRecord::Migration[6.0]
  def change
    add_column :update_jobs, :expires_at, :datetime, default: nil
    add_index :update_jobs, :expires_at
  end
end
