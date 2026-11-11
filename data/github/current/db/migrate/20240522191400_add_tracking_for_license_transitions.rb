class AddTrackingForLicenseTransitions < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    change_table :licensing_model_transitions, bulk: true do |t|
      t.bigint :actor_id, unsigned: true
      t.string :message
    end
  end
end
