class AddIndexOnBusinessMemberInvitationsInvitee < ActiveRecord::Migration[7.2]
  def change
    add_index :business_member_invitations, :invitee_id
  end
end
