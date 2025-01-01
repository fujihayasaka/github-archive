class AddBusinessToCopilotSeats < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_seats, bulk: true do |t|
      # remove NOT NULL from organization_id
      t.change :organization_id, :bigint, null: true
    end
  end
end
