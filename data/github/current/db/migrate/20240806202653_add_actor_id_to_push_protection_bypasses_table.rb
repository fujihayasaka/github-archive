class AddActorIdToPushProtectionBypassesTable < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    change_table :secret_scanning_push_protections_bypass_placeholders, bulk: true do |t|
      t.column :actor_id, :bigint, unsigned: true, null: true, comment: "id for the actor/user that triggered the creation of the bypass placeholder"
    end
  end
end
