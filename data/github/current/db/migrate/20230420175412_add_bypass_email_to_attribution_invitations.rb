# typed: true

class AddBypassEmailToAttributionInvitations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    change_table :attribution_invitations, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, auto_increment: true
      t.change :source_id, :bigint, unsigned: true
      t.change :target_id, :bigint, unsigned: true
      t.change :creator_id, :bigint, unsigned: true
      t.change :owner_id, :bigint, unsigned: true
    end

    add_column :attribution_invitations, :bypass_email, :boolean, null: false, default: false
  end
end
