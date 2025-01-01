# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationInviterTest < GitHub::TestCase
  context "#invite_user", skip_enterprise: true do
    test "prevents overallocation of enterprise licenses without EA" do
      business = create(:business, seats: 2)
      organization = create(:organization, business: business)

      perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob do
        assert_difference -> { OrganizationInvitation.count } => 1 do
          assert OrganizationInviter.new(
            organization,
            actor: organization.admin,
            email: "karl.marx@github.com"
          ).invite_user
        end
      end

      # Need to load a fresh organization to get a fresh business association to avoid stale memoization
      organization = Organization.find(organization.id)

      assert_difference -> { OrganizationInvitation.count } => 0 do
        refute OrganizationInviter.new(
          organization,
          actor: organization.admin,
          email: "eugene.debs@github.com"
        ).invite_user
      end
    end

    test "allows invitations until the combined license cap is consumed" do
      business = create(:business, seats: 1)
      create(:enterprise_agreement, business: business, seats: 1)
      organization = create(:organization, business: business)

      perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob do
        assert_difference -> { OrganizationInvitation.count } => 1 do
          assert OrganizationInviter.new(
            organization,
            actor: organization.admin,
            email: "karl.marx@github.com"
          ).invite_user
        end
      end

      # Need to load a fresh organization to get a fresh business association to avoid stale memoization
      organization = Organization.find(organization.id)

      assert_difference -> { OrganizationInvitation.count } => 0 do
        refute OrganizationInviter.new(
          organization,
          actor: organization.admin,
          email: "eugene.debs@github.com"
        ).invite_user
      end
    end

    test "allows inviting a user who is already a member of the organization's business when we're at the seat cap" do
      business = create(:business, seats: 2)
      organization1 = create(:organization, plan: "business_plus", business: business)
      organization2 = create(:organization, plan: "business_plus", business: business)
      organization2 = Organization.find(organization2.id)

      assert_changes -> { OrganizationInvitation.count }, 1 do
        OrganizationInviter.new(
          organization2,
          actor: organization2.admins.first,
          invitee: organization1.admins.first,
        ).invite_user
      end
    end

    test "when an enterprise team managed organization team is selected blocks invitation" do
      business = create(:business)
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      org = create(:organization, business: business)
      team = create(:team, organization: org)
      etmot = create(:team, organization: org)
      enterprise_team = create(:enterprise_team, business: business, sync_to_organizations: :all)
      EnterpriseTeamOrganizationMapping.create!(enterprise_team: enterprise_team, organization: org, team_id: etmot.id)
      invitee = create(:user)

      inviter = OrganizationInviter.new(
        org,
        actor: org.admin,
        invitee: invitee,
        team_ids: [team.id, etmot.id]
      )
      refute inviter.invite_user
      assert_equal OrganizationInviter::ENTERPRISE_TEAM_MANAGED_ERROR, inviter.error
      assert_equal UrlHelpers.org_edit_invitation_path(org, invitee.display_login), inviter.return_path
      refute OrganizationInvitation.exists?(invitee: invitee, organization: org)
    end
  end
end
