class AddStateToTwoFactorRequirementMetadata < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :two_factor_requirement_metadata, bulk: true do |t|
      t.column :state, "tinyint(4)", null: false, default: 0

      t.index [:user_id, :state], name: "index_two_factor_requirement_metadata_on_user_id_and_state", unique: false
    end
  end
end
