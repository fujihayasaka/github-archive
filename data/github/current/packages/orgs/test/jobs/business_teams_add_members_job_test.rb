# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class BusinessTeamsAddMembersJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @owner = create :user
    @user = create :user
    @business = create :business, owners: [@owner]
    @org = create(:organization, business: @business)
    @org.add_member(@user)
    @team = create(:business_team, business: @business)
    create(:business_user_account, user: @owner, business: @business) if GitHub.single_business_environment?
    enable_feature_flag(:enterprise_teams_crud)
  end

  test "perform adds members" do
    BusinessTeamsAddMembersJob.perform_now(@team, [@owner, @user])
    assert_equal 2, @team.member_ids.size
  end

  context "retry" do
    test "on throttler error" do
      assert_retry_on_throttler_error(job: BusinessTeamsAddMembersJob, args: [@team, [@owner, @user]])
    end

    test "on dirty exit" do
      assert_retry_on_dirty_exit(job: BusinessTeamsAddMembersJob, args: [@team, [@owner, @user]])
    end

    test "on recoverable exception" do
      assert_retry_on_recoverable_exceptions(job: BusinessTeamsAddMembersJob, args: [@team, [@owner, @user]])
    end
  end
end
