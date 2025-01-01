# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/missing_record_helper"

class Copilot::SeatManagement::OrgAccessReinstatementJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include DogstatsTestHelpers
  include MissingRecordHelper

  setup do
    enable_feature_flag(:copilot_org_access_reinstatement_job)
    enable_feature_flag(:copilot_revokable_access)
  end

  test "does not run if the feature flag is disabled" do
    disable_feature_flag(:copilot_org_access_reinstatement_job)
    logs = capture_logs do
      Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
        org_id: missing(:organization).id,
        reason: :test,
      )
    end

    refute_includes logs, "Performing Copilot::SeatManagement::OrgAccessReinstatementJob"
    assert_includes logs, "Skipping Copilot::SeatManagement::OrgAccessReinstatementJob"
  end

  test "runs when the feature flag is enabled" do
    enable_feature_flag(:copilot_org_access_reinstatement_job)
    logs = capture_logs do
      Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
        org_id: missing(:organization).id,
        reason: :test,
      )
    end

    assert_includes logs, "Performing Copilot::SeatManagement::OrgAccessReinstatementJob"
    refute_includes logs, "Skipping Copilot::SeatManagement::OrgAccessReinstatementJob"
  end

  context "perform" do
    test "resolves the tenant context" do
      org = create(:copilot_for_business_enabled_organization)
      on_multi_tenant_enterprise do
        Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
          org_id: org.id,
          reason: :test,
        )

        assert_equal org.business, GitHub::CurrentTenant.get
      end
    end

    test "does nothing with fake org" do
      Copilot::ErrorReporter.expects(:report!).once
      org = missing(:organization)

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
            org_id: org.id,
            reason: :test,
          )
        end
      end

      assert_includes logs, "Invalid organization"
    end

    test "does nothing when organization does not have copilot_revokable_access enabled" do
      disable_feature_flag(:copilot_revokable_access)

      org = create(:copilot_for_business_enabled_organization)

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
            org_id: org.id,
            reason: :test,
          )
        end
      end

      assert_includes logs, "Organization does not have revokable access enabled, skipping reinstatement"
    end

    test "does nothing when organization does not have Copilot enabled" do
      org = create(:organization)

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
            org_id: org.id,
            reason: :test,
          )
        end
      end

      assert_includes logs, "Organization does not have Copilot enabled, skipping reinstatement"
    end

    test "does nothing when no seat assignments have revoked access" do
      org = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      org.add_member(user)
      admin = org.admins.first

      seat_assignment = create(:copilot_seat_assignment, assignable: user, owner: org, assigning_user: admin)
      seat_assignment.convert_to_seats

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
            org_id: org.id,
            reason: :test,
          )
        end
      end

      assert_includes logs, "No seat assignments to reinstate"
    end

    test "reinstates access but maintains pending_cancellation_date when seat management is not enabled" do
      org = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      org.add_member(user)
      admin = org.admins.first

      seat_assignment = create(
        :copilot_seat_assignment,
        assignable: user,
        owner: org,
        assigning_user: admin,
      )
      seat_assignment.convert_to_seats
      seat_assignment.update_columns(
        access_revoked_at: Time.now,
        pending_cancellation_date: Time.now
      )

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
            org_id: org.id,
            reason: :test,
          )
        end
      end

      seat_assignment.reload

      assert_nil seat_assignment.access_revoked_at
      refute_nil seat_assignment.pending_cancellation_date
      assert_includes logs, "Reinstated access to seat assignments"
      assert_dogstats_increment(1, "copilot.seat_management.organization_seat_assignment_reinstatement_job.success")
    end

    test "reinstates access and resets pending_cancellation_date when seat management is not disabled" do
      org = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      org.add_member(user)
      admin = org.admins.first

      Copilot::Organization.any_instance.stubs(:seat_management_disabled?).returns(false)

      seat_assignment = create(
        :copilot_seat_assignment,
        assignable: user,
        owner: org,
        assigning_user: admin,
      )
      seat_assignment.convert_to_seats
      seat_assignment.update_columns(
        access_revoked_at: Time.now,
        pending_cancellation_date: Time.now
      )

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
          org_id: org.id,
          reason: :test,
        )
      end

      seat_assignment.reload

      assert_nil seat_assignment.access_revoked_at
      assert_nil seat_assignment.pending_cancellation_date
    end

    test "reinstates multiple seat assignments" do
      org = create(:copilot_for_business_enabled_organization)
      users = create_list(:user, 3)
      admin = org.admins.first

      seat_assignments = users.map do |user|
        org.add_member(user)
        assignment = create(
          :copilot_seat_assignment,
          assignable: user,
          owner: org,
          assigning_user: admin,
        )
        assignment.convert_to_seats
        assignment.update_columns(
          access_revoked_at: Time.now,
          pending_cancellation_date: Time.now
        )
        assignment
      end

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
            org_id: org.id,
            reason: :test,
          )
        end
      end

      assert_includes logs, "Reinstated access to seat assignments"
      assert_includes logs, "gh.copilot.seat_assignment.reinstated_count=\"3\""
      assert_dogstats_increment(3, "copilot.seat_assignment.access_reinstated")

      seat_assignments.each do |assignment|
        assert_nil assignment.reload.access_revoked_at
      end
    end

    test "skips reinstating access for suspended users" do
      org = create(:copilot_for_business_enabled_organization)
      active_user = create(:user)
      suspended_user = create(:user)
      org.add_member(active_user)
      org.add_member(suspended_user)
      admin = org.admins.first

      active_seat_assignment = create(
        :copilot_seat_assignment,
        assignable: active_user,
        owner: org,
        assigning_user: admin,
      )
      active_seat_assignment.convert_to_seats
      active_seat_assignment.update_columns(
        access_revoked_at: Time.now,
        pending_cancellation_date: Time.now
      )

      suspended_seat_assignment = create(
        :copilot_seat_assignment,
        assignable: suspended_user,
        owner: org,
        assigning_user: admin,
      )
      suspended_seat_assignment.convert_to_seats
      suspended_seat_assignment.update_columns(
        access_revoked_at: Time.now,
        pending_cancellation_date: Time.now
      )

      suspended_user.suspend("bad")

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
            org_id: org.id,
            reason: :test,
          )
        end
      end

      assert_includes logs, "is suspended, skipping reinstatement"
      assert_includes logs, "gh.copilot.seat_assignment.reinstated_count=\"1\""
      assert_dogstats_increment(1, "copilot.seat_assignment.access_reinstated")

      assert_nil active_seat_assignment.reload.access_revoked_at
      refute_nil suspended_seat_assignment.reload.access_revoked_at
    end

    test "instruments copilot access reinstated when reinstating access" do
      org = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      org.add_member(user)
      admin = org.admins.first

      seat_assignment = create(
        :copilot_seat_assignment,
        assignable: user,
        owner: org,
        assigning_user: admin
      )
      seat_assignment.convert_to_seats
      seat_assignment.update_columns(access_revoked_at: Time.now, pending_cancellation_date: Time.now)

      Copilot::Instrumenter
        .expects(:instrument_copilot_user_access_reinstated)
        .with(seat_assignment, :test, {})
        .once

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
          org_id: org.id,
          reason: :test,
        )
      end
      assert_dogstats_increment(1, "copilot.seat_assignment.access_reinstated")
    end

    test "reinstates non-user seat assignments" do
      org = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      org.add_member(user)
      team = create(:team, organization: org)
      team.add_member(user)
      admin = org.admins.first

      team_assignment = create(
        :copilot_seat_assignment,
        assignable: team,
        owner: org,
        assigning_user: admin
      )
      team_assignment.convert_to_seats
      team_assignment.update_columns(access_revoked_at: Time.now, pending_cancellation_date: Time.now)

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
            org_id: org.id,
            reason: :test,
          )
        end
      end

      assert_includes logs, "Reinstated access to seat assignments"
      assert_nil team_assignment.reload.access_revoked_at
    end

    test "only reistates seat assignments for members of the org" do
      org = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      removed_user = create(:user)
      admin = org.admins.first

      org.add_member(user)
      org.add_member(removed_user)

      ::Organization.any_instance.stubs(:member_ids).returns([user.id, admin.id])

      [user, removed_user].map do |member|
        assignment = create(
          :copilot_seat_assignment,
          assignable: member,
          owner: org,
          assigning_user: admin,
        )
        assignment.convert_to_seats
        assignment.update_columns(access_revoked_at: Time.now, pending_cancellation_date: Time.now)
      end

      org.remove_member(removed_user)

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
            org_id: org.id,
            reason: :test,
          )
        end
      end

      assert_includes logs, "gh.copilot.seat_assignment.reinstated_count=\"1\""
      assert_nil Copilot::SeatAssignment.find_by(assignable: user)&.access_revoked_at
      refute_nil Copilot::SeatAssignment.find_by(assignable: removed_user)&.access_revoked_at
    end

    test "only reinstates seat assignments that belonged to the org" do
      org = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      admin = org.admins.first

      org.add_member(user)

      assignment = create(
        :copilot_seat_assignment,
        assignable: user,
        owner: org,
        assigning_user: admin,
      )
      assignment.convert_to_seats

      Organization.any_instance.stubs(:archived?).returns(true)
      Copilot::OrganizationCleaner.call(org.id, org.business.customer.id)

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrgAccessReinstatementJob.perform_now(
            org_id: org.id,
            reason: :organization_unarchived,
          )
        end
      end

      assert_includes logs, "Reinstated access to seat assignments"
      assert_nil assignment.reload.access_revoked_at
    end
  end
end if GitHub.copilot_enabled?
