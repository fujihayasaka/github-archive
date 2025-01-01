# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ClearBusinessTeamOrgAssignmentsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @business = GitHub.global_business || create(:business)
  end

  setup do
    @org = create(:organization, business: @business)
    @business_team = create(:business_team, business: @business, name: "selected1", organization_selection_type: :selected)
    @business_team.add_to_organizations(org_ids: [@org])
  end

  test "perform cleaning" do
    business_team2 = create(:business_team, business: @business, name: "selected2", organization_selection_type: :selected)
    business_team2.add_to_organizations(org_ids: [@org])
    ClearBusinessTeamOrgAssignmentsJob.perform_now(@org.id)
    assert_equal 0, BusinessTeamOrgAssignment.where(business_team: @business_team).count
    assert_equal 0, BusinessTeamOrgAssignment.where(business_team: business_team2).count
  end

  context "retry" do
    test "on throttler error" do
      assert_retry_on_throttler_error(job: ClearBusinessTeamOrgAssignmentsJob, args: [@org.id])
    end

    test "on dirty exit" do
      assert_retry_on_dirty_exit(job: ClearBusinessTeamOrgAssignmentsJob, args: [@org.id])
    end

    test "on recoverable exception" do
      assert_retry_on_recoverable_exceptions(job: ClearBusinessTeamOrgAssignmentsJob, args: [@org.id])
    end
  end
end
