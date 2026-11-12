# frozen_string_literal: true

class AddTriggerTypeToUpdateJobs < ActiveRecord::Migration[6.0]
  def change
    add_column :update_jobs,
               :trigger_type,
               :string,
               null: false,
               default: "unknown",
               limit: 10
  end
end
