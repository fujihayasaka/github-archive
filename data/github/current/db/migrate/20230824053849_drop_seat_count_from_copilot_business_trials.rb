class DropSeatCountFromCopilotBusinessTrials < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    remove_column :copilot_business_trials, :seat_count
  end
end
