# typed: true

class AddIndexToCopilotSeatHistoriesOnOwnerIdAndOwnerTypeAndSeatCreatedAt < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_index :copilot_seat_histories, [:owner_id, :owner_type, :seat_created_at], name: "index_owner_id_owner_type_seat_created_at"
  end
end
