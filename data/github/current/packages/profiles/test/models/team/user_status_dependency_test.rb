# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamUserStatusDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @team = create(:team, organization: @org)
    @member = create(:user)
    @org.add_member(@member)
    @team.add_member(@member)
  end

  context "#member_statuses" do
    test "includes status from current member that is specific to the org" do
      status = create(:user_status, user: @member, organization: @org)
      assert_includes @team.member_statuses, status
    end

    test "includes status from current member that is public" do
      status = create(:user_status, user: @member)
      assert_includes @team.member_statuses, status
    end

    test "omits status from current member that is for another org" do
      other_org = create(:organization)
      other_org.add_member(@member)
      status = create(:user_status, user: @member, organization: other_org)

      refute_includes @team.member_statuses, status
    end

    test "omits status from member of another team in the org" do
      other_member = create(:user)
      @org.add_member(other_member)
      other_team = create(:team, organization: @org)
      other_team.add_member(other_member)
      status = create(:user_status, user: other_member, organization: @org)

      refute_includes @team.member_statuses, status
    end

    test "omits status from past team member that is specific to the org" do
      old_member = create(:user)
      @org.add_member(old_member)
      @team.add_member(old_member)
      status = create(:user_status, user: old_member, organization: @org)
      @team.remove_member(old_member)

      refute_includes @team.member_statuses, status
    end

    test "sorts statuses with most recent first" do
      other_member = create(:user)
      @org.add_member(other_member)
      @team.add_member(other_member)
      status1 = Timecop.freeze(1.week.ago) do
        create(:user_status, user: other_member, organization: @org)
      end
      status2 = create(:user_status, user: @member, organization: @org)

      assert_equal [status2, status1], @team.member_statuses
    end

    test "enforces a limit on how many team members to check for user statuses" do
      other_member = create(:user)
      @org.add_member(other_member)
      @team.add_member(other_member)
      status1 = Timecop.freeze(1.day.ago) { create(:user_status, user: other_member, organization: @org) }
      status2 = create(:user_status, user: @member, organization: @org)

      result = @team.member_statuses(limit: 1)
      assert_includes result, status2, "should include newest status"
      refute_includes result, status1
    end
  end
end
