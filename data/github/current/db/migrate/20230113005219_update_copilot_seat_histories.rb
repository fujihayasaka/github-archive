# typed: true
class UpdateCopilotSeatHistories < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_seat_histories, bulk: true do |t|
      t.remove_references :business

      t.references :business, index: { unique: false }, null: true, after: :id

      t.remove_index name: "index_copilot_seat_histories_on_business_id"
      t.remove_index name: "index_copilot_seat_histories_on_organization_id"

      t.index [:business_id, :billing_cycle_start_date, :billing_cycle_end_date], name: "business_and_billing_cycle"
      t.index [:organization_id, :billing_cycle_start_date, :billing_cycle_end_date], name: "organization_and_billing_cycle"
    end
  end
end
