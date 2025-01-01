# typed: true
# frozen_string_literal: true

class AddInvitationSourceToOrganizationInvitations < ActiveRecord::Migration[7.1]
  def change
    change_table :organization_invitations, bulk: true do |t|
      t.column :invitation_source, :integer, null: false, default: 0
      t.index :invitation_source
    end
  end
end
