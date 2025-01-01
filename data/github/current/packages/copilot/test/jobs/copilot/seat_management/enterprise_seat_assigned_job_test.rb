# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/missing_record_helper"

class Copilot::SeatManagement::EnterpriseSeatAssignedJobTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include GitHub::LoggerHelper
  include JobTestHelper
  include MissingRecordHelper
  include HydroTestHelpers

  setup do
    enable_feature_flag(:copilot_seat_assignment_job)
  end

  test "no business" do
    business = missing(:business)
    user = create(:user)

    logs = log_job_execution do
      Copilot::SeatManagement::EnterpriseSeatAssignedJob.perform_now(business.id, user.id)
    end

    assert_match "Invalid Business", logs
  end

  test "no user" do
    business = create(:business)
    user = missing(:user)

    logs = log_job_execution do
      Copilot::SeatManagement::EnterpriseSeatAssignedJob.perform_now(business.id, user.id)
    end

    assert_match "Invalid User", logs
  end

  test "no seat" do
    business = create(:business)
    user = create(:user)

    logs = log_job_execution do
      Copilot::SeatManagement::EnterpriseSeatAssignedJob.perform_now(business.id, user.id)
    end

    assert_match "Missing Seat", logs
  end

  test "creates a seat history if one does not exist", skip_enterprise: true do
    team_seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    team_seat_assignment.convert_to_seats

    assert_empty Copilot::SeatHistory.where(owner_id: team_seat_assignment.owner_id)

    with_write do
      Copilot::SeatManagement::EnterpriseSeatAssignedJob.perform_now(team_seat_assignment.owner_id, team_seat_assignment.assignable.member_user_ids.first)
    end

    assert_equal Copilot::SeatHistory.where(owner_id: team_seat_assignment.owner_id).count, 1
  end

  test "doesn't create a seat history if one already exists", skip_enterprise: true do
    seat = create(:copilot_seat, :enterprise_team_member)

    assert_equal Copilot::SeatHistory.where(seat_id: seat.id).count, 1

    with_write do
      Copilot::SeatManagement::EnterpriseSeatAssignedJob.perform_now(seat.owner.id, seat.assigned_user_id)
    end

    assert_equal Copilot::SeatHistory.where(seat_id: seat.id).count, 1
  end

  test "emails the user when a seat is created", skip_enterprise: true do
    seat = create(:copilot_seat, :enterprise_team_member)
    business = seat.owner
    user = seat.assigned_user

    mailer = mock
    mailer.stubs(:deliver_later)

    CopilotForBusinessMailer.expects(:seat_added_for_user).with(business, user).returns(mailer).once

    logs = log_job_execution do
      Copilot::SeatManagement::EnterpriseSeatAssignedJob.perform_now(business.id, user.id)
    end

    assert_match "Sending email to user", logs
  end

  test "deletes free user records if they exists", skip_enterprise: true do
    team_seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    team_seat_assignment.convert_to_seats

    user_id = team_seat_assignment.assignable.member_user_ids.first

    assert_empty Copilot::FreeUser.all
    create(:copilot_free_user, user_id: user_id)

    assert_empty Copilot::SeatHistory.where(owner_id: team_seat_assignment.owner_id)

    with_write do
      Copilot::SeatManagement::EnterpriseSeatAssignedJob.perform_now(team_seat_assignment.owner_id, team_seat_assignment.assignable.member_user_ids.first)
    end

    assert_equal Copilot::SeatHistory.where(owner_id: team_seat_assignment.owner_id).count, 1
    assert_equal Copilot::FreeUser.where(user_id: user_id).count, 0
  end

  test "deletes limited user records if they exists", skip_enterprise: true do
    team_seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    team_seat_assignment.convert_to_seats

    user_id = team_seat_assignment.assignable.member_user_ids.first

    assert_empty Copilot::LimitedUser.all
    create(:copilot_free_user, user_id: user_id)

    assert_empty Copilot::SeatHistory.where(owner_id: team_seat_assignment.owner_id)

    with_write do
      Copilot::SeatManagement::EnterpriseSeatAssignedJob.perform_now(team_seat_assignment.owner_id, team_seat_assignment.assignable.member_user_ids.first)
    end

    assert_equal Copilot::SeatHistory.where(owner_id: team_seat_assignment.owner_id).count, 1
    assert_equal Copilot::FreeUser.where(user_id: user_id).count, 0
  end

  sig { params(block: T.proc.void).returns(String) }
  def log_job_execution(&block)
    with_logs do
      with_write do
        yield
      end
    end
  end

  sig { params(block: T.proc.void).void }
  def with_write(&block)
    ActiveRecord::Base.connected_to(role: :writing) do
      yield
    end
  end

  sig { params(block: T.proc.void).returns(String) }
  def with_logs(&block)
    capture_logs do
      yield
    end
  end

  test "resolves tenant on a multi-tenant enterprise with business owner" do
    on_multi_tenant_enterprise do
      # Simulate no tenant being set
      GitHub::CurrentTenant.remove
      assert_nil GitHub::CurrentTenant.get

      user = create(:user)
      business = create(:business)

      Copilot::SeatManagement::EnterpriseSeatAssignedJob.perform_now(business.id, user.id)

      assert_equal business, GitHub::CurrentTenant.get
    end
  end
end
