# typed: true

class AddUpgradedFromOrganizationPreviousPlanToBusiness < ActiveRecord::Migration[7.1]
  def change
    add_column :businesses, :upgraded_from_plan, "varchar(20)", null: true, after: :upgraded_from_id
  end
end
