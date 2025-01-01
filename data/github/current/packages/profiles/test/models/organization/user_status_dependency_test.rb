# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationUserStatusDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @member = create(:user)
    @org.add_member(@member)
  end

  context "#member_statuses" do
    test "includes status from current member that is specific to the org" do
      status = create(:user_status, user: @member, organization: @org)
      assert_includes @org.member_statuses, status
    end

    test "includes status from current member that is public" do
      status = create(:user_status, user: @member)
      assert_includes @org.member_statuses, status
    end

    test "omits status from current member that is for another org" do
      other_org = create(:organization)
      other_org.add_member(@member)
      status = create(:user_status, user: @member, organization: other_org)

      refute_includes @org.member_statuses, status
    end

    test "omits status from private org member if include_private_org_members flag is false" do
      @org.conceal_member(@member)
      status = create(:user_status, user: @member, organization: @org)

      refute_includes @org.member_statuses(include_private_org_members: false), status
    end

    test "sorts statuses with most recent first" do
      other_member = create(:user)
      @org.add_member(other_member)
      status1 = Timecop.freeze(1.week.ago) do
        create(:user_status, user: other_member, organization: @org)
      end
      status2 = create(:user_status, user: @member, organization: @org)

      assert_equal [status2, status1], @org.member_statuses
    end
  end
end
