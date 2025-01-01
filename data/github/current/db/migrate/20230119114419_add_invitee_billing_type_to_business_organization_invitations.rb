# typed: true
class AddInviteeBillingTypeToBusinessOrganizationInvitations < ActiveRecord::Migration[7.1]
  def change
    add_column :business_organization_invitations, :invitee_billing_type, "varchar(20)", null: true, after: :invitee_id
  end
end
