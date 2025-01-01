# typed: true
# frozen_string_literal: true
require "test_helper"

class CopilotSeatManagementInstrumenterTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @product_uuid_subscribable ||= create(:billing_product_uuid, :copilot)
    @yearly_product_uuid_subscribable = create(:billing_product_uuid, :copilot, billing_cycle: :year)
  end

  context "Enterprise Level" do
    context "enterprise_account.organization_add" do
      test "queues the job" do
        organization = create(:copilot_for_business_enabled_organization)
        business = organization.business

        Copilot::SeatManagement::EnterpriseJob.expects(:perform_later).with do |args|
          assert_equal :remove_organization, args[:action]
          assert_equal business.id, args[:enterprise_id]
          assert_equal organization.id, args[:organization_id]
        end

        organization.business.remove_organization(organization)
      end
    end

    context "enterprise_account.organization_remove" do
      test "queues the job" do
        business = create(:business)
        organization = create(:organization)
        Copilot::Business.new(business).enable_copilot_for_all_organizations!

        Copilot::SeatManagement::EnterpriseJob.expects(:perform_later).with do |args|
          assert_equal :add_organization, args[:action]
          assert_equal business.id, args[:enterprise_id]
          assert_equal organization.id, args[:organization_id]
        end

        business.add_organization(organization)
      end
    end
  end

  context "Enterprise Team Level" do
    context "copilot_enterprise_team.update" do
      test "queues the job" do
        enterprise_team = create(:copilot_enterprise_team_assignment)

        Copilot::SeatManagement::EnterpriseTeamJob.expects(:perform_later).with do |args|
          assert_equal :enterprise_team_updated, args[:action]
          assert_equal enterprise_team.id, args[:team_id]
        end

        enterprise_team.instrument_update
      end
    end
  end

  context "Enterprise Team Level - New" do
    context "enterprise_team.copilot.assignment" do
      test "queues the job" do
        business = create(:business)
        enterprise_team = create(:enterprise_team, business: business)

        Copilot::SeatManagement::EnterpriseTeamJob.expects(:perform_later).once.with do |args|
          assert_equal :enterprise_team_assigned, args[:action]
          assert_equal enterprise_team.id, args[:team_id]
        end

        EnterpriseTeamAssignment.create!(enterprise_team: enterprise_team, assignment_type: "copilot")
      end
    end

    context "enterprise_team.copilot.unassignment" do
      test "queues the job" do
        business = create(:business)
        enterprise_team = create(:enterprise_team, business: business)

        ent_team_assignment = EnterpriseTeamAssignment.create!(enterprise_team: enterprise_team, assignment_type: "copilot")

        Copilot::SeatManagement::EnterpriseTeamJob.expects(:perform_later).once.with do |args|
          assert_equal :enterprise_team_unassigned, args[:action]
          assert_equal enterprise_team.id, args[:team_id]
        end

        ent_team_assignment.destroy!
      end
    end

    context "enterprise_team.copilot.update" do
      test "queues the job" do
        team = create :copilot_enterprise_team_assignment

        Copilot::SeatManagement::EnterpriseTeamJob.expects(:perform_later).once.with do |args|
          assert_equal :enterprise_team_updated, args[:action]
          assert_equal team.id, args[:team_id]
        end

        team.instrument_update
      end
    end
  end

  context "User Level" do
    context "org.add_member" do
      test "adds member calls job" do
        organization = create(:organization)
        user = create(:user)
        Copilot::SeatManagement::OrganizationMemberJob
          .expects(:perform_after_waiting_period)
          .with { |_, args| assert_equal :add_member, args[:action] }
          .once
        organization.add_member(user)
      end

      test "requires stuff" do
        Copilot::SeatManagement::OrganizationMemberJob
          .expects(:perform_after_waiting_period)
          .never
        result = capture_logs do
          GitHub.instrument("org.add_member", { sloppy: "joe" })
        end
        assert_match "Missing arguments for instrumentation", result
      end
    end

    context "org.invite" do
      test "adds member calls job" do
        organization = create(:organization)
        user = create(:user)
        copilot_organization = Copilot::Organization.new(organization)
        copilot_organization.assign([user], organization.admins.first)

        assignment = Copilot::SeatAssignment.first

        invitation = T.must(assignment).assignable
        Copilot::SeatManagement::OrganizationMemberJob
          .expects(:perform_after_waiting_period)
          .with { |_, args| assert_equal :add_member, args[:action] }
          .once
        invitation.accept
      end

      test "adds member by email calls job" do
        organization = create(:organization)

        copilot_organization = Copilot::Organization.new(organization)
        copilot_organization.assign(["test@veverka.net"], organization.admins.first)

        user = create(:user, email: "test@veverka.net")
        user.emails.map(&:verify!)
        assignment = Copilot::SeatAssignment.first

        invitation = T.must(assignment).assignable

        Copilot::SeatManagement::OrganizationMemberJob
          .expects(:perform_after_waiting_period)
          .with(
            instance_of(ActiveSupport::Duration),
            has_entries(
              action: :add_member,
              organization_id: organization.id,
              invitation_email: "test@veverka.net",
            ),
          ).once
        invitation.accept(acceptor: user)
      end
    end

    context "org.remove_member" do
      test "org removes members" do
        organization = create(:organization)
        user = create(:user)
        organization.add_member(user)

        Copilot::SeatManagement::OrganizationRemoveMemberJob.expects(:perform_later).once
        organization.remove_member!(user)
      end

      test "requires stuff" do
        Copilot::SeatManagement::OrganizationRemoveMemberJob.expects(:perform_later).never
        result = capture_logs do
          GitHub.instrument("org.remove_member", { sloppy: "joe" })
        end
        assert_match "Missing arguments for instrumentation", result
      end
    end

    context "user.destroy" do
      test "user.destroy" do
        user = create(:user)
        Copilot::SeatManagement::UserJob
          .expects(:perform_later)
          .with(has_entries(action: :destroy))
          .once
        user.destroy
      end

      test "requires stuff" do
        Copilot::SeatManagement::OrganizationMemberJob
          .expects(:perform_later)
          .never
        result = capture_logs do
          GitHub.instrument("user.destroy", { sloppy: "joe" })
        end
        assert_match "Missing arguments for instrumentation", result
      end
    end

    context "external_identity.deprovision" do
      test "external_identity.deprovision" do
        user = create(:emu, :owner)
        business = user.enterprise_managed_business
        provider = business.saml_provider
        identity = create(:external_identity, provider: provider)

        Copilot::SeatManagement::ExternalIdentityJob
          .expects(:perform_later)
          .with(has_entries(action: :deprovision, user_id: identity.user_id, external_identity_id: identity.id))
          .once

        identity.instrument_deprovision
      end

      test "requires stuff" do
        Copilot::SeatManagement::ExternalIdentityJob
          .expects(:perform_later)
          .never

        result = capture_logs do
          GitHub.instrument("external_identity.deprovision", { sloppy: "joe" })
        end
        assert_match "Missing arguments for instrumentation", result
      end
    end

    context "external_identity.provision" do
      test "external_identity.provision" do
        user = create(:emu, :owner)
        business = user.enterprise_managed_business
        provider = business.saml_provider
        identity = create(:external_identity, provider: provider)

        Copilot::SeatManagement::ExternalIdentityJob
          .expects(:perform_later)
          .with(has_entries(action: :provision, user_id: identity.user_id, external_identity_id: identity.id))
          .once

        identity.instrument_provision
      end

      test "requires stuff" do
        Copilot::SeatManagement::ExternalIdentityJob
          .expects(:perform_later)
          .never

        result = capture_logs do
          GitHub.instrument("external_identity.provision", { sloppy: "joe" })
        end
        assert_match "Missing arguments for instrumentation", result
      end
    end
  end

  context "Team Level" do
    context "team.add_member" do
      test "team.add_member existing org member" do
        team = create(:team)
        user = create(:user)
        team.organization.add_member(user)
        Copilot::SeatManagement::OrganizationTeamJob
          .expects(:perform_later)
          .with(has_entries(action: :add_member))
          .once
        team.add_member(user)
      end

      test "team.add_member" do
        team = create(:team)
        user = create(:user)
        Copilot::SeatManagement::OrganizationTeamJob
          .expects(:perform_later)
          .with(has_entries(action: :add_member))
          .once
        team.add_member(user)
      end

      test "requires stuff" do
        Copilot::SeatManagement::OrganizationTeamJob
          .expects(:perform_later)
          .never
        result = capture_logs do
          GitHub.instrument("team.add_member", { sloppy: "joe" })
        end
        assert_match "Missing arguments for instrumentation", result
      end
    end

    context "team.destroy" do
      test "team.destroy" do
        team = create(:team)
        perform_enqueued_jobs(only: [DestroyTeamDependantsJob]) do
          Copilot::SeatManagement::OrganizationTeamJob
            .expects(:perform_later)
            .with(has_entries(action: :destroy_team))
            .once
          team.destroy
        end
      end

      test "requires stuff" do
        Copilot::SeatManagement::OrganizationTeamJob
          .expects(:perform_later)
          .never
        result = capture_logs do
          GitHub.instrument("team.destroy", { sloppy: "joe" })
        end
        assert_match "Missing arguments for instrumentation", result
      end
    end

    context "team.remove_member" do
      test "team.remove_member" do
        team = create(:team)
        user = create(:user)
        team.add_member(user)
        Copilot::SeatManagement::OrganizationTeamJob.expects(:perform_later).with(
          has_entries(
            action: :remove_member,
            team_id: team.id,
            organization_id: team.organization.id,
            user_id: user.id,
          )
        ).once
        team.remove_member(user)
      end

      test "requires stuff" do
        Copilot::SeatManagement::OrganizationTeamJob
          .expects(:perform_later)
          .never
        result = capture_logs do
          GitHub.instrument("team.remove_member", { sloppy: "joe" })
        end
        assert_match "Missing arguments for instrumentation", result
      end
    end
  end

  context "Organization Level" do
    context "org.archive" do
      test "archiving an org removes all seats" do
        organization = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        organization.add_member(user)

        Copilot::SeatManagement::OrganizationJob.expects(:perform_later).with do |args|
          assert_equal :organization_archived, args[:action]
          assert_equal organization.id, args[:organization_id]
          assert_instance_of String, args[:transaction_id]
          refute_empty args[:payload]
        end.once

        organization.set_archived(organization.admins.first)
      end
    end

    context "org.delete" do
      test "deleting an org removes all seats" do
        organization = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        organization.add_member(user)

        Copilot::SeatManagement::OrganizationJob.expects(:perform_later).with do |args|
          assert_includes %i[organization_destroyed organization_destroying], args[:action]
          assert_equal organization.id, args[:organization_id]
        end.twice

        organization.destroy
      end
    end

    context "org.transform" do
      test "transforming a user into an org queues the job" do
        user = create(:credit_card_user)

        Copilot::SeatManagement::OrgTransformFromIndividualJob.expects(:perform_later).with do |args|
          assert_equal user.id, args[:org_id]
        end.once

        Organization.transform!(user, user, plan: "business")
      end
    end

    context "org.confirm_business_invitation" do
      test "triggers a job" do
        admin = create(:user)
        org_admin = create(:user)
        org = create(:business_plus_organization, admins: [org_admin])
        business = create(:business, owners: [admin], organizations: [])

        invite = create(:business_organization_invitation, business: business, inviter: admin, invitee: org)
        invite.accept(org_admin)

        Copilot::Businesses::OrganizationInvitationConfirmationJob.expects(:perform_later).with do |args|
          assert_equal :confirm_invitation, args[:action]
        end.once

        invite.confirm(admin)
      end
    end
  end

  context "Invitation Level" do
    context "org.cancel_invitation" do
      test "org.cancel_invitation for user invitation" do
        organization = create(:organization)
        user = create(:user)
        invitation = organization.invite(user, inviter: organization.admin)

        Copilot::SeatManagement::OrganizationInvitationJob.expects(:perform_later).with(
          has_entries(
            action: :cancel_invitation,
            invitation_id: invitation.id,
            organization_id: organization.id,
            user_id: user.id,
          )
        ).once
        invitation.cancel(actor: organization.admin, instrument: true)
      end

      test "org.cancel_invitation for email invitation" do
        organization = create(:organization)
        invitation = create(:organization_invitation, :email, organization: organization)

        Copilot::SeatManagement::OrganizationInvitationJob.expects(:perform_later).with(
          has_entries(
            action: :cancel_invitation,
            invitation_id: invitation.id,
            organization_id: organization.id,
            user_id: nil,
          )
        ).once
        invitation.cancel(actor: organization.admin, instrument: true)
      end
    end

    context "org.member_invite_expired" do
      test "org.member_invite_expired for user invitation" do
        organization = create(:organization)
        user = create(:user)
        invitation = organization.invite(user, inviter: organization.admin)

        Copilot::SeatManagement::OrganizationInvitationJob.expects(:perform_later).with(
          has_entries(
            action: :invite_expired,
            invitation_id: invitation.id,
            organization_id: organization.id,
            user_id: user.id,
          )
        ).once
        invitation.expire
      end

      test "org.member_invite_expired for mail invitation" do
        organization = create(:organization)
        invitation = create(:organization_invitation, :email, organization: organization)

        Copilot::SeatManagement::OrganizationInvitationJob.expects(:perform_later).with(
          has_entries(
            action: :invite_expired,
            invitation_id: invitation.id,
            organization_id: organization.id,
            user_id: nil,
          )
        ).once
        invitation.expire
      end

      test "requires stuff" do
        Copilot::SeatManagement::OrganizationMemberJob
          .expects(:perform_later)
          .never
        result = capture_logs do
          GlobalInstrumenter.instrument("org.member_invite_expired", { sloppy: "joe" })
        end
        assert_match "Missing arguments for instrumentation", result
      end
    end
  end

  context "business.destroy" do
    test "calls the correct job" do
      biz = create(:business)

      Copilot::Businesses::DestroyedBusinessCleanupJob.expects(:perform_later).once.with do |args|
        assert_equal biz.id, args[:business_id]
      end

      biz.destroy
    end
  end
end if GitHub.copilot_enabled?
