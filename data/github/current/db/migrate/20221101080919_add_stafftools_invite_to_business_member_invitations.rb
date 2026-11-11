# typed: true

class AddStafftoolsInviteToBusinessMemberInvitations < ActiveRecord::Migration[7.1]
  def change
    reversible do |dir|
      change_table :business_member_invitations, bulk: true do |t|
        dir.up do
          t.boolean :stafftools_invite, default: false, null: false

          t.change :id, :bigint, unsigned: true, auto_increment: true
          t.change :business_id, :bigint, unsigned: true
          t.change :inviter_id, :bigint, unsigned: true
          t.change :invitee_id, :bigint, unsigned: true
        end

        dir.down do
          t.remove :stafftools_invite

          t.change :id, :int, auto_increment: true
          t.change :business_id, :int
          t.change :inviter_id, :int
          t.change :invitee_id, :int
        end
      end
    end
  end
end
