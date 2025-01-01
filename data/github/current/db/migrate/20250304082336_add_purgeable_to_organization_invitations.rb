# typed: true

class AddPurgeableToOrganizationInvitations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :organization_invitations, bulk: true do |t|
      t.boolean :purgeable, null: false, as: "failed_at IS NOT NULL OR cancelled_at IS NOT NULL"
      t.index [:purgeable, :created_at]
    end
  end

  def down
    change_table :organization_invitations, bulk: true do |t|
      t.remove_index [:purgeable, :created_at]
      t.remove :purgeable
    end
  end
end
