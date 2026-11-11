# typed: true

class AddRequirementReasonToTwoFactorRequirementMetadata < ActiveRecord::Migration[7.1]
  def change
    change_table :two_factor_requirement_metadata, bulk: true do |t|
      t.column :requirement_reason, "tinyint(4)", null: false
      t.change :cohort, "tinyint(4)", null: true

      t.index [:requirement_reason], name: "index_two_factor_requirement_metadata_on_requirement_reason", unique: false
    end
  end
end
