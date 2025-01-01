class AddGhasOnlyToLicensingModelTransitions < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    change_table :licensing_model_transitions, bulk: true do |t|
      t.boolean :ghas_only, default: false, null: false
    end
  end
end
