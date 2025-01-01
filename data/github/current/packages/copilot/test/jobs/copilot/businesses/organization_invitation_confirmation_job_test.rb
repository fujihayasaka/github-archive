# typed: true
# frozen_string_literal: true
require "test_helper"

class CopilotOrganizationInvitationConfirmationJobTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "org.confirm_business_invitation" do
    test "calls job when event is fired" do
      GitHub.flipper[:copilot_business_invitation_confirmation_job].enable

      biz_admin = create(:user)
      org_admin = create(:user)

      business = create(:business, owners: [biz_admin], organizations: [])
      org = create(:organization, admins: [org_admin])
      invite = create(:business_organization_invitation, business: business, inviter: biz_admin, invitee: org)

      copilot_org = Copilot::Organization.new(org)
      copilot_org.enable_copilot!
      copilot_org.block_public_code_suggestions!

      copilot_business = Copilot::Business.new(business)
      copilot_business.enable_copilot_for_all_organizations!
      copilot_business.allow_public_code_suggestions!

      # The Org has its own snippy setting, which won't be the same as the businesses
      refute_equal(copilot_business.snippy_setting, copilot_org.snippy_setting)

      perform_enqueued_jobs(only: [Copilot::Businesses::OrganizationInvitationConfirmationJob]) do
        invite.accept(org_admin)
        invite.confirm(biz_admin)

        org.reload
        # Once the invitation has been confirmed, we should see the same snippy settings
        assert_equal(Copilot::Organization.new(org).snippy_setting, copilot_business.snippy_setting)
      end
    end

    test "never sends email for chat on setting propagation" do
      GitHub.flipper[:copilot_business_invitation_confirmation_job].enable

      biz_admin = create(:user)
      org_admin = create(:user)

      business = create(:business, owners: [biz_admin], organizations: [])
      org = create(:organization, admins: [org_admin])

      user = create(:user)
      org.add_member(user)
      seat_assignment = create(:copilot_seat_assignment, organization: org, assignable: user, assigning_user: org_admin)
      create(:copilot_seat, organization: org, assigned_user: user, seat_assignment: seat_assignment)

      invite = create(:business_organization_invitation, business: business, inviter: biz_admin, invitee: org)

      copilot_org = Copilot::Organization.new(org)
      copilot_org.enable_copilot!
      copilot_org.block_public_code_suggestions!

      copilot_business = Copilot::Business.new(business)
      copilot_business.enable_copilot_for_all_organizations!
      copilot_business.allow_public_code_suggestions!
      copilot_business.enable_chat!

      assert copilot_business.copilot_enabled_for_all_organizations?

      refute copilot_org.chat_enabled?
      assert copilot_business.chat_enabled?

      invite.accept(org_admin)
      invite.confirm(biz_admin)

      org.reload

      mailer = mock
      mailer.stubs(:deliver_later)

      # no one should get an email about chat settings
      CopilotForBusinessMailer
      .expects(:chat_enabled_for_user)
      .returns(mailer)
      .never

      Copilot::Businesses::OrganizationInvitationConfirmationJob.perform_now(
        organization_id: org.id,
        invitation_id: invite.id,
        business_id: business.id,
        action: :confirm_invitation,
        transaction_id: "lskdjfklsf",
        payload: { hello: "hello" }
      )
    end
  end
end if GitHub.copilot_enabled?
