# frozen_string_literal: true

class AddEnqueueScheduleUpdateIdToUpdateJobs < ActiveRecord::Migration[7.0]
  def change
    change_table :update_jobs, bulk: true do |t|
      t.string :enqueue_scheduled_update_id, null: true
      t.index :enqueue_scheduled_update_id
    end
  end
end
