# typed: true

class AddReplacementTwoFactorRequirementMetadataIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :two_factor_requirement_metadata, bulk: true do |t|
      t.index [:state, :required_by, :user_id], unique: false
      t.index [:state, :user_id], unique: false
    end
  end
end
