# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::SeatManagement::EnterpriseTeamJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    enable_feature_flag(:copilot_enterprise_team_job)
    disable_feature_flag(:copilot_destroy_seat_assignment_in_cooldown_period)
  end

  context "handle_create_event" do
    test "creates seat assignment if none exist" do
      Copilot::ErrorReporter.expects(:report!).never
      enterprise_team = create(:copilot_enterprise_team)

      logs = capture_logs do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).once
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseTeamJob.perform_now(
            team_id: enterprise_team.id,
            action: :enterprise_team_assigned,
          )
        end
      end
      assert_includes logs, "Creating SeatAssignment for Enterprise Team"
      assert_includes logs, "Queuing delayed_converter_job"
    end

    test "tells everyone if the seat assignment already exists" do
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      team = assignment.assignable
      logs = capture_logs do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_created).never
        Copilot::ErrorReporter.expects(:report!).once
        Copilot::Helpers.expects(:force_chatterbox_say!).twice
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseTeamJob.perform_now(
            team_id: team.id,
            action: :enterprise_team_assigned,
          )
        end
      end
      assert_includes logs, "SeatAssignment for EnterpriseTeam already exists but create event emitted"
    end

    test "refreshes the seat assignment if the pending cancellation date was set" do
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      team = assignment.assignable

      assignment.update!(pending_cancellation_date: Time.now)

      logs = capture_logs do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_refreshed).once
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseTeamJob.perform_now(
            team_id: team.id,
            action: :enterprise_team_assigned,
          )
        end
      end

      assert_includes logs, "Refreshing SeatAssignment for Enterprise Team"

      assignment.reload

      assert_nil assignment.pending_cancellation_date
    end
  end

  context "handle_update_event" do
    test "tells everyone if the seat assignment doesn't exist" do
      Copilot::ErrorReporter.expects(:report!).once
      Copilot::Helpers.expects(:force_chatterbox_say!).twice
      team = create(:copilot_enterprise_team)
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseTeamJob.perform_now(
            team_id: team.id,
            action: :update,
            payload: { "slug" => team.slug },
          )
        end
      end
      assert_includes logs, "SeatAssigment for EnterpriseTeam does not already exist but update event emitted"
    end

    test "handles update event with no existing seats" do
      Copilot::ErrorReporter.expects(:report!).never
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      team = assignment.assignable
      Copilot::Helpers.expects(:force_chatterbox_say!).with("Processing update event for EnterpriseTeam #{team.id} (Payload: )", room_id: "#copilot-standalone-ops").once
      Copilot::Helpers.expects(:force_chatterbox_say!).with("Updating SeatAssignment #{assignment.id} For EnterpriseTeam (#{team.id}-#{team.slug}) - Converting to seats (Payload: )", room_id: "#copilot-standalone-ops").once

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseTeamJob.perform_now(
            team_id: team.id,
            action: :update,
          )
        end
      end

      assert_includes logs, "code.function=\"insert_seats\""
      assert_includes logs, "Copilot::SeatAssignments::EnterpriseTeamConverterCommand"
      assert_includes logs, "gh.business.id=\"#{team.business_id}\""
      assert_includes logs, "gh.copilot.command=\"Copilot::SeatAssignments::EnterpriseTeamConverterCommand\""
      assert_includes logs, "gh.copilot.seat_assignment.id=\"#{assignment.id}\""
      assert_includes logs, "gh.copilot.team_member_count=\"#{team.member_user_ids.count}\""
      assert_includes logs, "gh.enterprise_team.id=\"#{team.id}\""
      assert_includes logs, "gh.enterprise_team.slug=\"#{team.slug}\""
      assert_includes logs, "Loaded list of current team members"
      assert_includes logs, "Performing Copilot::SeatManagement::EnterpriseTeamJob"
      assert_includes logs, "Updating SeatAssignment for EnterpriseTeam"
      assert_includes logs, "Updating SeatAssignment for EnterpriseTeam"
    end

    test "handles update event with existing seats" do
      Copilot::ErrorReporter.expects(:report!).never
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      assignment.convert_to_seats
      enterprise_team = assignment.assignable
      assignment.reload
      assert_equal enterprise_team.member_user_ids.count, assignment.seats.count
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseTeamJob.perform_now(
            team_id: enterprise_team.id,
            action: :update,
          )
        end
      end
      refute_includes logs, "code.function=\"insert_seats\""
      assert_includes logs, "Copilot::SeatAssignments::EnterpriseTeamConverterCommand"
      assert_includes logs, "gh.business.id=\"#{enterprise_team.business_id}\""
      assert_includes logs, "gh.copilot.command=\"Copilot::SeatAssignments::EnterpriseTeamConverterCommand\""
      assert_includes logs, "gh.copilot.seat_assignment.id=\"#{assignment.id}\""
      assert_includes logs, "gh.copilot.team_member_count=\"#{enterprise_team.member_user_ids.count}\""
      assert_includes logs, "gh.enterprise_team.id=\"#{enterprise_team.id}\""
      assert_includes logs, "gh.enterprise_team.slug=\"#{enterprise_team.slug}\""
      assert_includes logs, "Performing Copilot::SeatManagement::EnterpriseTeamJob"
      assert_includes logs, "Updating SeatAssignment for EnterpriseTeam"
      assert_includes logs, "Loaded list of current team members"
      assert_includes logs, "No new seats need to be created"
      assert_includes logs, "No seats need to be deleted"
    end

    test "handles update event with existing to be deleted seats" do
      Copilot::ErrorReporter.expects(:report!).never
      assignment = create(:copilot_seat_assignment, :enterprise_team, member_count: 3)
      assignment.convert_to_seats
      enterprise_team = assignment.assignable
      assignment.reload
      assert_equal enterprise_team.member_user_ids.count, assignment.seats.count
      external_group = enterprise_team.enterprise_team_group_mappings.first.external_group
      external_identity = external_group.external_identity_group_memberships.first.external_identity
      external_identity.destroy

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseTeamJob.perform_now(
            team_id: enterprise_team.id,
            action: :update,
          )
        end
      end
      assert_includes logs, "Copilot::SeatAssignments::EnterpriseTeamConverterCommand"
      assert_includes logs, "Deleting seats not associated with EnterpriseTeam members"
      assert_includes logs, "gh.business.id=\"#{enterprise_team.business_id}\""
      assert_includes logs, "gh.copilot.command=\"Copilot::SeatAssignments::EnterpriseTeamConverterCommand\""
      assert_includes logs, "gh.copilot.seat_assignment.id=\"#{assignment.id}\""
      assert_includes logs, "gh.copilot.team_member_count=\"#{enterprise_team.member_user_ids.count}\""
      assert_includes logs, "gh.copilot.to_be_deleted.count=\"1\""
      assert_includes logs, "gh.enterprise_team.id=\"#{enterprise_team.id}\""
      assert_includes logs, "gh.enterprise_team.slug=\"#{enterprise_team.slug}\""
      assert_includes logs, "Loaded list of current team members"
      assert_includes logs, "No new seats need to be created"
      assert_includes logs, "Performing Copilot::SeatManagement::EnterpriseTeamJob"
      assert_includes logs, "Updating SeatAssignment for EnterpriseTeam"
      refute_includes logs, "code.function=\"insert_seats\""
    end
  end

  context "handle_unassign_event" do
    test "tell everyone if the seat assignment doesn't exist" do
      Copilot::ErrorReporter.expects(:report!).once
      Copilot::Helpers.expects(:force_chatterbox_say!).twice
      enterprise_team = create(:copilot_enterprise_team)
      logs = capture_logs do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).never
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseTeamJob.perform_now(
            team_id: enterprise_team.id,
            action: :enterprise_team_unassigned,
          )
        end
      end
      assert_includes logs, "SeatAssignment for EnterpriseTeam does not already exist but destroy event emitted"
    end

    test "sets the seat assignment to pending cancellation" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      logs = capture_logs do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once.with(seat_assignment, seat_assignment.assigning_user, :enterprise_team_unassigned)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseTeamJob.perform_now(
            team_id: seat_assignment.assignable_id,
            action: :enterprise_team_unassigned,
          )
        end
      end
      seat_assignment.reload

      refute_nil seat_assignment.pending_cancellation_date
      assert_includes logs, "Setting pending_cancellation_date SeatAssignment for EnterpriseTeam"
    end

    test "resolves tenant on a multi-tenant enterprise with business owner" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      on_multi_tenant_enterprise do
        # Simulate no tenant being set
        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get

        Copilot::SeatManagement::EnterpriseTeamJob.perform_now(
          team_id: seat_assignment.assignable_id,
          action: :enterprise_team_unassigned,
        )
        assert_equal seat_assignment.assignable.business, GitHub::CurrentTenant.get
      end
    end
  end
end if GitHub.copilot_enabled?

class EnterpriseTeamJobWithCooldownDestructionTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  setup do
    enable_feature_flag(:copilot_enterprise_team_job)
    enable_feature_flag(:copilot_destroy_seat_assignment_in_cooldown_period)

    # we need to do this otherwise the delay is set to 0 for all types in the test environment
    silence_warnings do
      ::Copilot::COPILOT_SEAT_COOLDOWN_PERIODS = T.let({
        ENTERPRISE_TEAM: 15.minutes,
      }, T::Hash[Symbol, ActiveSupport::Duration])
    end
  end

  test "destroys seat assignment if it was unassigned within cooldown period" do
    freeze_time do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team, created_at: 5.minutes.ago)

      logs = capture_logs do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once.with(seat_assignment, seat_assignment.owner.admins.first, :unassigned_during_cooldown, { unassigned_during_cooldown: true })
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseTeamJob.perform_now(
            team_id: seat_assignment.assignable_id,
            action: :enterprise_team_unassigned,
          )
        end
      end

      refute Copilot::SeatAssignment.exists?(seat_assignment.id)
      assert_dogstats_increment(1, "copilot.seat_assignment.unassigned_within_cooldown")
      assert_includes logs, "Destroying EnterpriseTeam SeatAssignment that was unassigned in cooldown period."
    end
  end

  test "does not destroy seat assignment if it was unassigned outside of cooldown period" do
    freeze_time do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team, created_at: 20.minutes.ago)

      logs = capture_logs do
        Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_assignment_unassigned).once.with(seat_assignment, seat_assignment.owner.admins.first, :enterprise_team_unassigned)
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::EnterpriseTeamJob.perform_now(
            team_id: seat_assignment.assignable_id,
            action: :enterprise_team_unassigned,
          )
        end
      end

      refute_nil Copilot::SeatAssignment.find_by(id: seat_assignment.id)
      refute_dogstats_increment("copilot.seat_assignment.unassigned_outside_cooldown")
      refute_includes logs, "Destroying EnterpriseTeam SeatAssignment that was unassigned in cooldown period."
    end
  end


end if GitHub.copilot_enabled?
