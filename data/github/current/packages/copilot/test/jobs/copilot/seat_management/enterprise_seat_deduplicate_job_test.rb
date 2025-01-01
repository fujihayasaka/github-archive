# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::SeatManagement::EnterpriseSeatDeduplicateJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    enable_feature_flag(:copilot_enterprise_seat_deduplicate_job)
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "perform" do
    test "resolves the tenant" do
      business = create(:business)

      on_multi_tenant_enterprise do
        Copilot::SeatManagement::EnterpriseSeatDeduplicateJob.perform_now(business.id)
        assert_equal GitHub::CurrentTenant.get, business
      end
    end

    test "does nothing if the enterprise has no seats" do
      business = create(:copilot_business)
      assert_no_changes -> { Copilot::Seat.count } do
        Copilot::SeatManagement::EnterpriseSeatDeduplicateJob.perform_now(business.id)
      end
    end

    test "does nothing if the enterprise has a single non-duplicated seat" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      biz = seat_assignment.owner
      assigned = User.find_by(id: seat_assignment.assignable.member_user_ids.first)
      create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: assigned)

      assert_no_changes -> { Copilot::Seat.count } do
        Copilot::SeatManagement::EnterpriseSeatDeduplicateJob.perform_now(biz.id)
      end
    end

    test "does nothing if the enterprise has multiple non-duplicated seat" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      seat_assignment.convert_to_seats

      assert_equal 2, Copilot::Seat.count

      biz = seat_assignment.owner
      assert_no_changes -> { Copilot::Seat.count } do
        Copilot::SeatManagement::EnterpriseSeatDeduplicateJob.perform_now(biz.id)
      end
    end

    test "removes single duplicated seat" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      biz = seat_assignment.owner
      assigned = User.find_by(id: seat_assignment.assignable.member_user_ids.first)
      create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: assigned)
      create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: assigned)

      assert_changes -> { Copilot::Seat.count }, from: 2, to: 1 do
        Copilot::SeatManagement::EnterpriseSeatDeduplicateJob.perform_now(biz.id)
      end
    end

    test "removes many duplicated seats" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      biz = seat_assignment.owner
      assigned = User.find_by(id: seat_assignment.assignable.member_user_ids.first)
      another_assigned = User.find_by(id: seat_assignment.assignable.member_user_ids.second)
      5.times { create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: assigned) }
      create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: another_assigned)

      assert_changes -> { Copilot::Seat.count }, from: 6, to: 2 do
        Copilot::SeatManagement::EnterpriseSeatDeduplicateJob.perform_now(biz.id)
      end
    end

    test "removes duplicated user seats as well" do
      copilot_business = create(:copilot_business)
      biz = copilot_business.business_object
      seat_assignment = create(:copilot_seat_assignment, owner: biz, assignable: biz.owners.first, assigning_user: biz.owners.first)
      create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: biz.owners.first)
      create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: biz.owners.first)

      assert_changes -> { Copilot::Seat.count }, from: 2, to: 1 do
        Copilot::SeatManagement::EnterpriseSeatDeduplicateJob.perform_now(biz.id)
      end
    end

    test "sends correct owner type to dogstats" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      biz = seat_assignment.owner
      assigned = User.find_by(id: seat_assignment.assignable.member_user_ids.first)
      create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: assigned)
      create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: assigned)

      Copilot::SeatManagement::EnterpriseSeatDeduplicateJob.perform_now(biz.id)
      gauges = GitHub.dogstats.gauges("gh.copilot.duplicate_assigned_user_count")

      assert_equal 1, gauges.last.value
      assert_equal "owner:business", gauges.last.tags.first
    end
  end
end if GitHub.copilot_enabled?
