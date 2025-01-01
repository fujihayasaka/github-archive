# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationBusinessInvitationsAcceptableByTest < GitHub::TestCase
  unless GitHub.single_business_environment?
    test "returns pending invitations from businesses to that particular org" do
      bus_admin_1 = create :user
      bus_admin_2 = create :user
      org_admin = create :user
      org = create :organization, admins: [org_admin]
      other_org = create :organization, admins: [org_admin]
      business_1 = create :business, owners: [bus_admin_1]
      business_2 = create :business, owners: [bus_admin_2]
      invitation_from_business_1 = create :business_organization_invitation,
        business: business_1, inviter: bus_admin_1, invitee: org
      invitation_from_business_2 = create :business_organization_invitation,
        business: business_2, inviter: bus_admin_2, invitee: org
      invitation_to_other_org = create :business_organization_invitation,
        business: business_1, inviter: bus_admin_1, invitee: other_org

      assert_same_elements [invitation_from_business_1, invitation_from_business_2],
        org.business_invitations_acceptable_by(org_admin)
    end

    test "does not return invitations if org already owned by a business" do
      bus_admin = create :user
      org_admin = create :user
      org = create :organization, admins: [org_admin]
      business = create :business, owners: [bus_admin]
      invitation = create :business_organization_invitation,
        business: business, inviter: bus_admin, invitee: org
      business.add_organization(org)
      org.reload

      refute_nil org.business
      assert_empty org.business_invitations_acceptable_by(org_admin)
    end

    test "does not return invitations if user is not the org's admin (even if they admin the business)" do
      user = create :user
      bus_admin = create :user
      org_admin = create :user
      org = create :organization, admins: [org_admin]
      business = create :business, owners: [bus_admin]
      invitation = create :business_organization_invitation,
        business: business, inviter: bus_admin, invitee: org

      assert_empty org.business_invitations_acceptable_by(user)
      assert_empty org.business_invitations_acceptable_by(bus_admin)
    end

    test "does not return already accepted (or even confirmed) invitations" do
      bus_admin = create :user
      org_admin = create :user
      org = create :organization, admins: [org_admin]
      business = create :business, owners: [bus_admin]
      invitation = create :business_organization_invitation,
        business: business, inviter: bus_admin, invitee: org

      invitation.accept(org_admin)
      assert_empty org.business_invitations_acceptable_by(org_admin)
      invitation.confirm(bus_admin)
      assert_empty org.business_invitations_acceptable_by(org_admin)
    end

    test "does not return cancelled invitations" do
      bus_admin = create :user
      org_admin = create :user
      org = create :organization, admins: [org_admin]
      business = create :business, owners: [bus_admin]
      invitation = create :business_organization_invitation,
        business: business, inviter: bus_admin, invitee: org

      invitation.cancel(org_admin)
      assert_empty org.business_invitations_acceptable_by(org_admin)
    end
  end
end
