# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/missing_record_helper"

class Copilot::SeatManagement::BasicEnterpriseAccessReinstatementJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include DogstatsTestHelpers
  include MissingRecordHelper

  setup do
    enable_feature_flag(:copilot_basic_enterprise_access_reinstatement_job)
    enable_feature_flag(:copilot_revokable_access)
  end

  test "skips when enterprise cannot be found" do
    enterprise = missing(:business)
    logs = capture_logs do
      Copilot::ErrorReporter.expects(:report!).once
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::BasicEnterpriseAccessReinstatementJob.perform_now(
          enterprise_id: enterprise.id,
          reason: :test_reason
        )
      end
    end

    assert_includes logs, "Enterprise cannot be found."
  end

  test "skips when enterprise is not enabled for revokable access" do
    disable_feature_flag(:copilot_revokable_access)
    Copilot::Business.any_instance.stubs(:is_standalone_business?).returns(true)

    enterprise = create(:business)

    logs = capture_logs do
      Copilot::ErrorReporter.expects(:report!).never
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::BasicEnterpriseAccessReinstatementJob.perform_now(
          enterprise_id: enterprise.id,
          reason: :test_reason
        )
      end
    end

    assert_includes logs, "Copilot revokable access feature is not enabled for this enterprise, exiting"
  end

  test "skips when enterprise is not standalone" do
    enterprise = create(:business)

    Copilot::Business.any_instance.stubs(:is_standalone_business?).returns(false)

    logs = capture_logs do
      Copilot::ErrorReporter.expects(:report!).never
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::BasicEnterpriseAccessReinstatementJob.perform_now(
          enterprise_id: enterprise.id,
reason:           :test_reason,
        )
      end
    end

    assert_includes logs, "Enterprise is not standalone, exiting"
  end

  test "skips when there are no seat assignments" do
    enterprise = create(:business, seats_plan_type: :basic)
    Copilot::Business.new(enterprise).enable_copilot!
    Copilot::SeatAssignment.stubs(:for_standalone_business).returns([])

    logs = capture_logs do
      Copilot::ErrorReporter.expects(:report!).never
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::BasicEnterpriseAccessReinstatementJob.perform_now(
          enterprise_id: enterprise.id,
          reason: :test_reason
        )
      end
    end

    assert_includes logs, "No seat assignments, exiting"
  end

  test "skips when there are no seat assignments with revoked access" do
    seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    enterprise = seat_assignment.owner
    Copilot::Business.new(enterprise).enable_copilot!

    logs = capture_logs do
      Copilot::ErrorReporter.expects(:report!).never
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::BasicEnterpriseAccessReinstatementJob.perform_now(
          enterprise_id: enterprise.id,
          reason: :test_reason
        )
      end
    end

    assert_includes logs, "No seat assignments with revoked access to restore, exiting"
  end

  test "restores access to revoked seat assignments" do
    enterprise = create(:business, :default_managed, seats_plan_type: :basic)
    revoked_ent_team = create(:enterprise_team, name: "ent-team-revoked", business: enterprise)
    ent_team = create(:enterprise_team, name: "ent-team", business: enterprise)

    revoked_assignment = create(
      :copilot_seat_assignment,
      :enterprise_team,
      supplied_business: enterprise,
      assignable: revoked_ent_team,
      access_revoked_at: Time.current,
      pending_cancellation_date: Time.current
    )
    create(
      :copilot_seat_assignment,
      :enterprise_team,
      supplied_business: enterprise,
      assignable: ent_team
    )
    reason = :test_reason

    Copilot::Business.new(enterprise).enable_copilot!

    logs = capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::BasicEnterpriseAccessReinstatementJob.perform_now(
          enterprise_id: enterprise.id,
reason:           reason
        )
      end
    end

    revoked_assignment.reload

    assert_includes logs, "Restoring access to seat assignments"
    assert_includes logs, "gh.copilot.seat_assignment.reinstated_count=\"1\""
    assert_nil revoked_assignment.pending_cancellation_date
    assert_nil revoked_assignment.access_revoked_at
    assert_dogstats_increment(1, "copilot.seat_management.standalone_enterprise_seat_assignment_reinstatement_job.success")
  end

  test "restores access to revoked seat assignments when EMU mode is enabled" do
    enterprise = create(:business, seats_plan_type: :basic)
    revoked_team_assignment = create(
      :copilot_seat_assignment,
      :enterprise_team,
      supplied_business: enterprise,
      access_revoked_at: Time.current,
      pending_cancellation_date: Time.current
    )
    create(
      :copilot_seat_assignment,
      :enterprise_team,
      supplied_business: enterprise
    )

    Copilot::Business.new(enterprise).enable_copilot!

    logs = capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::BasicEnterpriseAccessReinstatementJob.perform_now(
          enterprise_id: enterprise.id,
          reason: :test_reason
        )
      end
    end

    assert_includes logs, "Restoring access to seat assignments"
    assert_includes logs, "gh.copilot.seat_assignment.reinstated_count=\"1\""
    assert_nil revoked_team_assignment.reload.pending_cancellation_date
    assert_nil revoked_team_assignment.reload.access_revoked_at
    assert_dogstats_increment(1, "copilot.seat_management.standalone_enterprise_seat_assignment_restore_access_job.success")
  end if TestEnv.test_with_all_emus?

  test "restores access but does not uncancel when Copilot is not enabled" do
    enterprise = create(:business, :default_managed, seats_plan_type: :basic)
    revoked_ent_team = create(:enterprise_team, name: "ent-team-revoked", business: enterprise)
    revoked_assignment = create(
      :copilot_seat_assignment,
      assignable: revoked_ent_team,
      owner: enterprise,
      access_revoked_at: Time.current,
      pending_cancellation_date: Time.current
    )

    reason = :test_reason

    logs = capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::BasicEnterpriseAccessReinstatementJob.perform_now(
          enterprise_id: enterprise.id,
reason:           reason
        )
      end
    end

    assert_includes logs, "Restoring access to seat assignments"
    assert_includes logs, "gh.copilot.seat_assignment.reinstated_count=\"1\""
    assert_nil revoked_assignment.reload.access_revoked_at
    refute_nil revoked_assignment.reload.pending_cancellation_date
  end

  test "resolves tenant on multi-tenant enterprise with business owner" do
    seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    enterprise = seat_assignment.owner

    on_multi_tenant_enterprise do
      GitHub::CurrentTenant.remove
      assert_nil GitHub::CurrentTenant.get

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::BasicEnterpriseAccessReinstatementJob.perform_now(
          enterprise_id: enterprise.id,
          reason: :test_reason
        )
      end

      assert_equal enterprise, GitHub::CurrentTenant.get
    end
  end
end if GitHub.copilot_enabled?
