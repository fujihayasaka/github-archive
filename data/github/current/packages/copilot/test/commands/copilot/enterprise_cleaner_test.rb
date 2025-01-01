# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::EnterpriseCleanerTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include GitHub::LoggerHelper

  context "perform" do
    test "returns immediately when the business doesn't exist" do
      Copilot::ErrorReporter.expects(:report!).never

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::EnterpriseCleaner.call(1234)
        end
      end

      assert_includes logs, "Business does not exist"
      refute_includes logs, "Destroying seat"
      refute_includes logs, "Destroying seat assignment"
      refute_includes logs, "Destroying configuration"
    end

    test "logs and exits with an error when the business exists but cannot / should not be cleaned" do
      business = create(:business)
      Copilot::Business.any_instance.stubs(:copilot_disabled?).returns(false)
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)

      Copilot::ErrorReporter.expects(:report!).once

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::EnterpriseCleaner.call(business.id)
        end
      end

      assert_includes logs, "Business exists"
      assert_includes logs, "gh.copilot.is_billable=\"true\""
      assert_includes logs, "gh.business.spammy=\"false\""
      assert_includes logs, "gh.business.suspended=\"false\""
      assert_includes logs, "gh.business.copilot_disabled=\"false\""
    end

    test "it logs when business exists and is not billable" do
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(false)
      business = create(:business)
      admin = create(:user)
      other_user = create(:user)
      org = create(:organization, business: business, admin: admin)
      org.add_member(other_user)
      Copilot::Organization.new(org).enable_copilot!
      seat_assignment = create(:copilot_seat_assignment, organization: org, assignable: other_user)
      create(:copilot_seat_assignment, organization: org, assignable: admin)

      seat_assignment.convert_to_seats
      Copilot::Business.new(business).enable_copilot_for_all_organizations!

      reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::EnterpriseCleaner.call(business.id, reason)
        end
      end

      assert_includes logs, "Business exists"
      assert_includes logs, "gh.copilot.is_billable=\"false\""
      assert_includes logs, "gh.business.spammy=\"false\""
      assert_includes logs, "gh.business.suspended=\"false\""
      assert_includes logs, "gh.business.copilot_disabled=\"false\""

      refute_empty Copilot::SeatAssignment.where(organization_id: org.id)
      refute_empty Copilot::Seat.where(organization_id: org.id)
    end

    test "it cleans the business when the business is spammy" do
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
      business = create(:business)
      admin = create(:user)
      other_user = create(:user)
      org = create(:organization, business: business, admin: admin)
      org.add_member(other_user)
      Copilot::Organization.new(org).enable_copilot!
      seat_assignment = create(:copilot_seat_assignment, organization: org, assignable: other_user)
      create(:copilot_seat_assignment, organization: org, assignable: admin)

      seat_assignment.convert_to_seats
      Copilot::Business.new(business).enable_copilot_for_all_organizations!

      business.mark_as_spammy

      reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]
      Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(business, reason).once

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::EnterpriseCleaner.call(business.id, reason)
        end
      end

      assert_includes logs, "gh.copilot.is_billable=\"true\""
      assert_includes logs, "gh.business.spammy=\"true\""
      assert_includes logs, "gh.business.suspended=\"false\""
      assert_includes logs, "gh.business.copilot_disabled=\"false\""

      assert_empty Copilot::SeatAssignment.where(organization_id: org.id)
      assert_empty Copilot::Seat.where(organization_id: org.id)
    end

    test "it cleans the business when the business is suspended" do
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
      business = create(:business)
      admin = create(:user)
      other_user = create(:user)
      org = create(:organization, business: business, admin: admin)
      org.add_member(other_user)
      Copilot::Organization.new(org).enable_copilot!
      seat_assignment = create(:copilot_seat_assignment, organization: org, assignable: other_user)
      create(:copilot_seat_assignment, organization: org, assignable: admin)

      seat_assignment.convert_to_seats
      Copilot::Business.new(business).enable_copilot_for_all_organizations!

      business.suspend("test")

      reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_suspended]
      Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(business, reason).once

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::EnterpriseCleaner.call(business.id, reason)
        end
      end

      assert_includes logs, "gh.copilot.is_billable=\"true\""
      assert_includes logs, "gh.business.spammy=\"false\""
      assert_includes logs, "gh.business.suspended=\"true\""
      assert_includes logs, "gh.business.copilot_disabled=\"false\""

      assert_empty Copilot::SeatAssignment.where(organization_id: org.id)
      assert_empty Copilot::Seat.where(organization_id: org.id)
    end

    test "it cleans the business when the business does not have copilot enabled" do
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
      business = create(:business)
      admin = create(:user)
      other_user = create(:user)
      org = create(:organization, business: business, admin: admin)
      org.add_member(other_user)
      Copilot::Organization.new(org).enable_copilot!
      seat_assignment = create(:copilot_seat_assignment, organization: org, assignable: other_user)
      create(:copilot_seat_assignment, organization: org, assignable: admin)

      seat_assignment.convert_to_seats
      Copilot::Business.new(business).disable_copilot!

      reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]
      Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(business, reason).once

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::EnterpriseCleaner.call(business.id, reason)
        end
      end

      assert_includes logs, "gh.copilot.is_billable=\"true\""
      assert_includes logs, "gh.business.spammy=\"false\""
      assert_includes logs, "gh.business.suspended=\"false\""
      assert_includes logs, "gh.business.copilot_disabled=\"true\""
      refute_includes logs, "Cleaning standalone business"

      assert_empty Copilot::SeatAssignment.where(organization_id: org.id)
      assert_empty Copilot::Seat.where(organization_id: org.id)
    end

    test "it cleans a standalone business when the business does not have copilot enabled" do
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)

      business = create(:business, seats_plan_type: :basic)

      seat_assignment = create(:copilot_seat_assignment, :enterprise_team, supplied_business: business)
      seat_assignment_id = seat_assignment.id
      assignable_id = seat_assignment.assignable_id
      seat_assignment.convert_to_seats
      team_assignment = EnterpriseTeamAssignment.new(enterprise_team: seat_assignment.assignable, assignment_type: :copilot)
      team_assignment.save(validate: false)

      Copilot::Business.new(business).disable_copilot!

      reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]
      Copilot::Instrumenter.expects(:instrument_copilot_access_revoked).with(business, reason).once

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::EnterpriseCleaner.call(business.id, reason)
        end
      end

      assert_includes logs, "gh.copilot.is_billable=\"true\""
      assert_includes logs, "gh.business.spammy=\"false\""
      assert_includes logs, "gh.business.suspended=\"false\""
      assert_includes logs, "gh.business.copilot_disabled=\"true\""
      assert_includes logs, "Cleaning standalone business"

      assert_empty Copilot::SeatAssignment.where(owner_id: business.id)
      assert_empty Copilot::Seat.where(copilot_seat_assignment_id: seat_assignment_id)
      assert_empty EnterpriseTeamAssignment.where(enterprise_team_id: assignable_id)
    end if TestEnv.test_with_all_emus?
  end
end unless GitHub.enterprise?
