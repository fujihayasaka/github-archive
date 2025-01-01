# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotBusinessesDestroyedBusinessJobTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "#perform" do
    test "logs named tags" do
      # We can pass any id here, the job is effectively a no op if nothing exists
      logs = capture_logs do
        Copilot::Businesses::DestroyedBusinessCleanupJob.perform_now(business_id: 1)
      end

      assert_log_match logs, "code.namespace", Copilot::Businesses::DestroyedBusinessCleanupJob.name
      assert_log_match logs, "code.function", "perform"
      assert_log_match logs, "gh.business.id", 1
      refute_log_match logs, "gh.transaction.id", ".*"
      refute_includes logs, "Destroying configuration"
      refute_includes logs, "Destroying seat assignment"
    end

    test "cleans up records for an emu standalone business" do
      biz = create(:business)
      biz.update(seats_plan_type: :basic)

      Copilot::Business.new(biz).enable_copilot!

      assignment = create(:copilot_seat_assignment, :enterprise_team, supplied_business: biz)
      assignment.convert_to_seats

      team_assignment = EnterpriseTeamAssignment.new(enterprise_team: assignment.assignable, assignment_type: :copilot)
      team_assignment.save(validate: false)

      assert_job_logs do
        assert_changes -> { EnterpriseTeamAssignment.count }, from: 1, to: 0 do
          assert_changes -> { Copilot::SeatAssignment.count }, from: 1, to: 0 do
            assert_changes -> { Copilot::Configuration.count }, from: 1, to: 0 do
              Copilot::Businesses::DestroyedBusinessCleanupJob.perform_now(business_id: biz.id)
            end
          end
        end
      end
    end if TestEnv.test_with_all_emus?

    test "cleans up records for non-emu standalone business" do
      biz = create(:business)
      biz.update(seats_plan_type: :basic)

      team = create(:enterprise_team, business: biz)
      user = create(:user)
      biz.add_user_accounts([user.id], business_roles_bitfield: 0)
      team.enterprise_team_memberships.create!(user_id: user.id)

      Copilot::Business.new(biz).enable_copilot!
      assignment = Copilot::SeatAssignment.new(
        owner_id: team.business_id,
        owner_type: "Business",
        assignable_type: "EnterpriseTeam",
        assignable_id: team.id,
        assigning_user: team.business.owners.first,
      )
      assignment.save!
      assignment.convert_to_seats

      assert_job_logs do
        assert_changes -> { Copilot::SeatAssignment.count }, from: 1, to: 0 do
          assert_changes -> { Copilot::Configuration.where(configurable_type: "Business", configurable_id: biz.id).count }, from: 1, to: 0 do
            Copilot::Businesses::DestroyedBusinessCleanupJob.perform_now(business_id: biz.id)
          end
        end
      end
    end unless TestEnv.test_with_all_emus?

    test "cleans up records for a full copilot business with orgs" do
      biz = create(:business)
      org = create(:organization, business: biz)
      user = create(:user)

      org.add_member(user)

      assignment = create(:copilot_seat_assignment, assignable: user, organization: org)
      assignment.convert_to_seats

      Copilot::Business.new(biz).enable_copilot_for_all_organizations!
      Copilot::Organization.new(org).enable_copilot!

      org_configurations = Copilot::Configuration.where(configurable_type: "Organization", configurable_id: org.id)
      business_configurations = Copilot::Configuration.where(configurable_type: "Business", configurable_id: biz.id)
      assert_job_logs do
        assert_changes -> { Copilot::SeatAssignment.count }, from: 1, to: 0 do
          assert_changes -> { Copilot::Configuration.where(configurable_type: "Organization", configurable_id: org.id).count + Copilot::Configuration.where(configurable_type: "Business", configurable_id: biz.id).count }, from: org_configurations.count + business_configurations.count, to: 0 do
            Copilot::Businesses::DestroyedBusinessCleanupJob.perform_now(business_id: biz.id)
          end
        end
      end
    end
  end

  def assert_job_logs(&block)
    logs = capture_logs(&block)

    assert_includes logs, "Cleaning up business post-deletion"
    assert_includes logs, "Finished cleaning business"
    assert_includes logs, "Destroying configuration"
    assert_includes logs, "Destroying seat assignment"
  end
end unless GitHub.enterprise?
