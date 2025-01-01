# typed: true

class AddIndexOnTwoFactorRequirementMetadata < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_index :two_factor_requirement_metadata, [:state, :required_by, :interrupt_first_seen_at]
  end
end
