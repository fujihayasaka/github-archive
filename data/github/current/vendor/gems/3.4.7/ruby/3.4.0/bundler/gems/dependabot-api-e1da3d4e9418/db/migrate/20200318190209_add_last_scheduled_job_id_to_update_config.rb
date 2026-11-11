# frozen_string_literal: true

class AddLastScheduledJobIdToUpdateConfig < ActiveRecord::Migration[6.0]
  def change
    add_column :update_configs, :last_scheduled_job_id, :bigint, default: nil
  end
end
