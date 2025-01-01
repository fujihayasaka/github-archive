# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessInvitationsTest < GitHub::TestCase
  fixtures do
    @business = create :business
    @owner = @business.owners.first
    @member = create(:user, login: "member")
  end

  context "#cancel_all_invitations_involving" do
    unless GitHub.bypass_business_member_invites_enabled?
      test "cancels any pending admin invitations where the user is the inviter" do
        owner_invite = create :business_administrator_invitation,
          business: @business, inviter: @owner, invitee: create(:user), role: :owner
        billing_manager_invite = create :business_administrator_invitation,
          business: @business, inviter: @owner, invitee: create(:user), role: :billing_manager
        assert_same_elements \
          [owner_invite, billing_manager_invite],
          @business.invitations.pending.where(inviter: @owner)

        @business.cancel_all_invitations_involving(@owner)

        assert_empty @business.invitations.pending.where(inviter: @owner)
      end

      test "cancels any pending org invitations where the user is the inviter" do
        org_invite = create :business_organization_invitation,
          business: @business, inviter: @owner
        assert_same_elements \
          [org_invite],
          @business.organization_invitations.pending.where(inviter: @owner)

        @business.cancel_all_invitations_involving(@owner)

        assert_empty @business.invitations.pending.where(inviter: @owner)
      end

      test "cancels any pending admin invitations where the user is the invitee" do
        owner_invite = create :business_administrator_invitation,
          business: @business, inviter: @owner, invitee: @member, role: :owner
        billing_manager_invite = create :business_administrator_invitation,
          business: @business, inviter: @owner, invitee: @member, role: :billing_manager
        assert_same_elements \
          [owner_invite, billing_manager_invite],
          @business.invitations.pending.where(invitee: @member)

        @business.cancel_all_invitations_involving(@member)

        assert_empty @business.invitations.pending.where(invitee: @member)
      end
    end
  end
end
