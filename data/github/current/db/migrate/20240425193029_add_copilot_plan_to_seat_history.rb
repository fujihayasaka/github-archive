class AddCopilotPlanToSeatHistory < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_column :copilot_seat_histories, :copilot_plan, :json, comment: "the GitHub Copilot plan the seat was granted under, e.g. Copilot Enterprise or Copilot Business"
  end
end
