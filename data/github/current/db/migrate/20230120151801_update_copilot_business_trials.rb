# typed: true

class UpdateCopilotBusinessTrials < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_business_trials, bulk: true do |t|
      # adding this so that we can reference it and create the start and end dates from it
      t.integer  :trial_length, null: false, default: 30, after: :trialable_id, comment: "The length of the trial in days"

      # the trial isn't started at db record creation time, so we need to add a started_at column
      t.datetime :started_at, null: false, after: :seat_count, precision: 6, comment: "The time the trial started"
    end
  end
end
