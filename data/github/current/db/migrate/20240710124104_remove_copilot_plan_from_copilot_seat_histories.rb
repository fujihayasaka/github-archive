class RemoveCopilotPlanFromCopilotSeatHistories < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    remove_column :copilot_seat_histories, :copilot_plan, :json
  end
end
