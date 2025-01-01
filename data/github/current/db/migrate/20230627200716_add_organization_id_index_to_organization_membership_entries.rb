# typed: true
class AddOrganizationIdIndexToOrganizationMembershipEntries < ActiveRecord::Migration[7.1]
  def up
    change_table :organization_membership_entries, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :user_id, :bigint, unsigned: true, null: false
      t.change :organization_id, :bigint, unsigned: true, null: false
      t.change :adder_id, :bigint, unsigned: true, null: false
      t.change :ability_id, :bigint, unsigned: true, null: false
      t.index [:organization_id, :adder_id, :adder_type], name: "index_organization_membership_entries_on_org_and_adder"
      t.index [:ability_id], name: "index_organization_membership_entries_on_ability"
    end
  end

  def down
    change_table :organization_membership_entries, bulk: true do |t|
      t.remove_index name: "index_organization_membership_entries_on_org_and_adder"
      t.remove_index name: "index_organization_membership_entries_on_ability"
      t.change :id, :int, null: false, auto_increment: true
      t.change :user_id, :int, null: false
      t.change :organization_id, :int, null: false
      t.change :adder_id, :int, null: false
      t.change :ability_id, :int, null: false
    end
  end
end
