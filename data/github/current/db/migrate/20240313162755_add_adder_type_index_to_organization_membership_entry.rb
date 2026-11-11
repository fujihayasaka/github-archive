class AddAdderTypeIndexToOrganizationMembershipEntry < ActiveRecord::Migration[7.2]
  def up
    change_table :organization_membership_entries, bulk: true do |t|
      t.index [:adder_type, :adder_id], name: "index_organization_membership_entries_on_adder_type_and_adder_id"
    end
  end

  def down
    change_table :organization_membership_entries, bulk: true do |t|
      t.remove_index [:adder_type, :adder_id], name: "index_organization_membership_entries_on_adder_type_and_adder_id"
    end
  end
end
