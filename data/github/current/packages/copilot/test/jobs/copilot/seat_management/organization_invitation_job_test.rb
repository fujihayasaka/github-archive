# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::SeatManagement::OrganizationInvitationJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    enable_feature_flag(:copilot_seat_assignment_job)
  end

  context "perform" do
    test "raises an error if the action is invalid" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      invitation = create(:organization_invitation, organization: organization, invitee: user)
      action = :invalid_action

      assert_raises(ArgumentError) do
        Copilot::SeatManagement::OrganizationInvitationJob.perform_now(
          organization_id: organization.id,
          invitation_id: invitation.id,
          action: action,
          transaction_id: "1234",
          payload: { foo: "bar" },
          user_id: user.id,
        )
      end
    end

    test "does nothing with fake org" do
      user = create(:user)
      organization = create(:organization)
      invitation = create(:organization_invitation, organization: organization, invitee: user)
      action = :cancel_invitation

      assert_logged("Body" => "Invalid Organization") do
        Copilot::ErrorReporter.expects(:report!).with do |error, context|
          error.is_a?(Copilot::Errors::CopilotError) &&
          context[:extra_details]["gh.organization.id"] == 233552342
        end
        Copilot::SeatManagement::OrganizationInvitationJob.perform_now(
          organization_id: 233552342,
          invitation_id: invitation.id,
          action: action,
          transaction_id: "1234",
          payload: { foo: "bar" },
        )
      end
    end

    test "does nothing with a non-CFB org" do
      user = create(:user)
      organization = create(:organization)
      invitation = create(:organization_invitation, organization: organization, invitee: user)
      action = :cancel_invitation

      assert_logged("Body" => "Organization not enabled for CFB") do
        Copilot::SeatManagement::OrganizationInvitationJob.perform_now(
          organization_id: organization.id,
          invitation_id: invitation.id,
          action: action,
          transaction_id: "1234",
          payload: { foo: "bar" },
        )
      end
    end

    test "does nothing with fake invitation" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      create(:organization_invitation, organization: organization, invitee: user)
      action = :cancel_invitation

      Copilot::ErrorReporter.expects(:report!).with do |error, context|
        error.is_a?(Copilot::Errors::CopilotError) &&
        context[:extra_details]["gh.invitation.id"] == 233552342
      end
      Copilot::SeatManagement::OrganizationInvitationJob.perform_now(
        organization_id: organization.id,
        invitation_id: 233552342,
        action: action,
        transaction_id: "1234",
        payload: { foo: "bar" },
      )
    end

    test "resolves tenant on a multi-tenant enterprise with business owner" do
      on_multi_tenant_enterprise do
        # Simulate no tenant being set
        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get

        business = create(:business)
        organization = create(:organization, business: business)
        Copilot::SeatManagement::OrganizationInvitationJob.perform_now(
          organization_id: organization.id,
          invitation_id: 233552342,
          action: :cancel_invitation,
          transaction_id: "1234",
          payload: { foo: "bar" },
        )

        refute_nil GitHub::CurrentTenant.get
        assert_equal business, GitHub::CurrentTenant.get
      end
    end
  end

  context "cancel_invitation/invite_expired" do
    %i(cancel_invitation invite_expired).each do |action|
      test "#{action} removes seat assignment for existing user invite" do
        organization = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        invitation = create(:organization_invitation, organization: organization, invitee: user)
        case action
        when :cancel_invitation
          invitation.cancel(actor: organization.admins.first)
        when :invite_expired
          invitation.expire
        end

        seat_assignment = create(
          :copilot_seat_assignment,
          organization: organization,
          assignable: invitation,
          assigning_user: organization.admin
        )

        assert_logged("Body" => "Removing Invitation SeatAssignment") do
          Copilot::SeatManagement::OrganizationInvitationJob.perform_now(
            action: action,
            invitation_id: invitation.id,
            organization_id: organization.id,
            transaction_id: "1234",
          )
        end
        refute Copilot::SeatAssignment.exists?(seat_assignment.id)
      end

      test "#{action} removes seat assignment for email invite" do
        organization = create(:copilot_for_business_enabled_organization)
        invitation = create(:organization_invitation, :email, organization: organization)
        case action
        when :cancel_invitation
          invitation.cancel(actor: organization.admins.first)
        when :invite_expired
          invitation.expire
        end

        seat_assignment = create(
          :copilot_seat_assignment,
          organization: organization,
          assignable: invitation,
          assigning_user: organization.admin
        )

        assert_logged("Body" => "Removing Invitation SeatAssignment") do
          Copilot::SeatManagement::OrganizationInvitationJob.perform_now(
            action: action,
            invitation_id: invitation.id,
            organization_id: organization.id,
            transaction_id: "1234",
          )
        end
        refute Copilot::SeatAssignment.exists?(seat_assignment.id)
      end

      test "#{action} does nothing without a seat assignment" do
        organization = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        invitation = create(:organization_invitation, organization: organization, invitee: user)

        assert_no_changes -> { Copilot::SeatAssignment.count } do
          assert_no_changes -> { Copilot::Seat.count } do
            assert_logged("Body" => "Removing Invitation SeatAssignment") do
              Copilot::SeatManagement::OrganizationInvitationJob.perform_now(
                action: action,
                invitation_id: invitation.id,
                organization_id: organization.id,
                transaction_id: "1234",
              )
            end
          end
        end
      end
    end
  end
end if GitHub.copilot_enabled?
