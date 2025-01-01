# typed: true

class AddDatesToTwoFactorRequirementMetadata < ActiveRecord::Migration[7.1]
  def change
    change_table :two_factor_requirement_metadata, bulk: true do |t|
      t.datetime :required_by, precision: nil, null: true
      t.datetime :original_required_by, precision: nil, null: true
      t.datetime :interrupt_first_seen_at, precision: nil, null: true

      t.index [:required_by], name: "index_two_factor_requirement_metadata_on_required_by", unique: false
    end
  end
end
