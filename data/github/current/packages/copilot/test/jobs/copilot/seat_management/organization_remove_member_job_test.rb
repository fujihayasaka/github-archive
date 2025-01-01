# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::SeatManagement::OrganizationRemoveMemberJobTest < GitHub::TestCase
  include JobTestHelper
  include AuditLogHelpers
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    GitHub.flipper[:copilot_seat_assignment_job].enable
  end

  context "perform" do
    test "resolves the tenant context" do
      org = create(:copilot_for_business_enabled_organization)
      on_multi_tenant_enterprise do
        Copilot::SeatManagement::OrganizationRemoveMemberJob.perform_now(
          user_id: org.members.first.id,
          organization_id: org.id,
        )

        assert_equal org.business, GitHub::CurrentTenant.get
      end
    end

    test "does nothing with fake org" do
      user = create(:user)

      logs = capture_logs do
        Copilot::ErrorReporter.expects(:report!).with do |error, context|
          error.is_a?(Copilot::Errors::CopilotError) &&
          context[:extra_details]["gh.organization.id"] == 233552342
        end
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationRemoveMemberJob.perform_now(
            organization_id: 233552342,
            transaction_id: "1234",
            payload: { foo: "bar" },
            user_id: user.id,
          )
        end
      end

      assert_match "User being removed from invalid or non-existant Organization", logs
    end

    test "does nothing with a non-CFB org" do
      org = create(:credit_card_organization)
      user = create(:user)

      copilot_organization = Copilot::Organization.new(org)
      refute copilot_organization.copilot_for_business_enabled?

      Copilot::OrganizationCleaner.expects(:call).with(org.id, copilot_organization.customer_for&.id).once
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationRemoveMemberJob.perform_now(
            organization_id: org.id,
            transaction_id: "1234",
            payload: { foo: "bar" },
            user_id: user.id,
          )
        end
      end

      assert_match "User being removed from org that doesn't have copilot enabled, cleaning Organization", logs
    end

    test "cleans with fake user_id" do
      organization = create(:copilot_for_business_enabled_organization)
      create(:user)

      Copilot::UserCleaner.expects(:call).with(233552342).once
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationRemoveMemberJob.perform_now(
            user_id: 233552342,
            organization_id: organization.id,
            transaction_id: "1234",
            payload: { foo: "bar" },
          )
        end
      end

      assert_match "User being removed from org is invalid or non-existant", logs
    end
  end

  context "remove_member" do
    test "seats and user seat assignments are deleted" do
      org = create(:copilot_for_business_enabled_organization)
      seat_assignment = build(
        :copilot_seat_assignment,
        :user,
        organization: org,
      )
      seat = create(
        :copilot_seat,
        seat_assignment: seat_assignment,
        organization: org,
        assigned_user: seat_assignment.assignable,
      )

      CopilotForBusinessMailer
        .expects(:seat_removed_for_user)
        .with(seat.organization, seat.assigned_user)
        .returns(mock(deliver_later: true))
        .once

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationRemoveMemberJob.perform_now(
            user_id: seat.assigned_user.id,
            organization_id: seat.organization.id,
          )
        end
      end

      assert_match "Deleting User SeatAssignment for member removed from organization", logs
      assert_match "Cancelling Seat", logs

      refute Copilot::Seat.exists?(seat.id),
        "deletes the seat"
      refute Copilot::SeatAssignment.exists?(seat_assignment.id),
        "deletes the seat assignment"
    end

    test "does not delete organization seat assignments" do
      org = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      org.add_member(user)
      seat_assignment = build(
        :copilot_seat_assignment,
        :organization,
        organization: org,
        assignable_type: "Organization",
        assignable_id: org,
      )
      seat = create(
        :copilot_seat,
        seat_assignment: seat_assignment,
        assigned_user: user,
        organization: org,
      )

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationRemoveMemberJob.perform_now(
            user_id: seat.assigned_user.id,
            organization_id: seat.organization.id,
          )
        end
      end

      assert_match "Skipping Organization SeatAssignment for member removed from organization", logs

      refute Copilot::Seat.exists?(seat.id),
        "deletes the seat"
      assert Copilot::SeatAssignment.exists?(seat_assignment.id),
        "does not delete the seat assignment"
    end

    test "does not delete team seat assignments with other members" do
      org = create(:copilot_for_business_enabled_organization)

      user = create(:user)
      org.add_member(user)
      other_user = create(:user)
      org.add_member(other_user)

      team = create(:team, organization: org)
      team.add_member(user)
      team.add_member(other_user)

      seat_assignment = build(
        :copilot_seat_assignment,
        organization: org,
        assignable_type: "Team",
        assignable_id: team.id,
      )
      seat = create(
        :copilot_seat,
        seat_assignment: seat_assignment,
        assigned_user: user,
        organization: org,
      )

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationRemoveMemberJob.perform_now(
            user_id: seat.assigned_user.id,
            organization_id: seat.organization.id,
          )
        end
      end

      assert_match "Skipping non-empty Team SeatAssignment for member removed from organization", logs

      refute Copilot::Seat.exists?(seat.id),
        "deletes the seat"
      assert Copilot::SeatAssignment.exists?(seat_assignment.id),
        "does not delete the seat assignment"
    end

    test "deletes team seat assignments with no other members" do
      org = create(:copilot_for_business_enabled_organization)

      user = create(:user)
      org.add_member(user)

      team = create(:team, organization: org)
      team.add_member(user)

      seat_assignment = build(
        :copilot_seat_assignment,
        organization: org,
        assignable_type: "Team",
        assignable_id: team.id,
      )
      seat = create(
        :copilot_seat,
        seat_assignment: seat_assignment,
        assigned_user: user,
        organization: org,
      )

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationRemoveMemberJob.perform_now(
            user_id: seat.assigned_user.id,
            organization_id: seat.organization.id,
          )
        end
      end

      assert_match "Deleting SeatAssignment", logs

      refute Copilot::Seat.exists?(seat.id),
        "deletes the seat"
      refute Copilot::SeatAssignment.exists?(seat_assignment.id),
        "deletes the seat assignment"
    end

    test "handles it if the team has been weirdly deleted in between" do
      org = create(:copilot_for_business_enabled_organization)

      user = create(:user)
      org.add_member(user)

      team = create(:team, organization: org)
      team.add_member(user)

      seat_assignment = build(
        :copilot_seat_assignment,
        organization: org,
        assignable_type: "Team",
        assignable_id: team.id,
      )
      seat = create(
        :copilot_seat,
        seat_assignment: seat_assignment,
        assigned_user: user,
        organization: org,
      )

      team.delete
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationRemoveMemberJob.perform_now(
            user_id: seat.assigned_user.id,
            organization_id: seat.organization.id,
          )
        end
      end

      assert_match "Deleting SeatAssignment", logs

      refute Copilot::Seat.exists?(seat.id),
        "deletes the seat"
      refute Copilot::SeatAssignment.exists?(seat_assignment.id),
        "deletes the seat assignment"
    end

    test "does nothing if no seat or user seat assignments exist" do
      user = create(:user)
      organization = create(:copilot_for_business_enabled_organization)

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count } do
          assert_no_changes -> { Copilot::SeatAssignment.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationRemoveMemberJob.perform_now(
                user_id: user.id,
                organization_id: organization.id,
              )
            end
          end
        end
      end

      assert_match "No seats or seat assignments to remove for user being removed from organization", logs
    end

    test "cleans up any user seat assignments that don't have seats" do
      user = create(:user)
      organization = create(:copilot_for_business_enabled_organization)
      organization.add_member(user)

      seat_assignment = create(:copilot_seat_assignment, :user, organization: organization, assignable: user)

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count } do
          assert_difference -> { Copilot::SeatAssignment.count }, -1 do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationRemoveMemberJob.perform_now(
                user_id: user.id,
                organization_id: organization.id,
              )
            end
          end
        end
      end

      refute_match "No seats or seat assignments to remove for user being removed from organization", logs
      assert_match "Deleting User SeatAssignment for member removed from organization", logs
      assert_nil Copilot::SeatAssignment.find_by(id: seat_assignment.id)
    end
  end
end if GitHub.copilot_enabled?
