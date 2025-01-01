# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionEnterpriseContributionInfoTest < GitHub::TestCase
  setup do
    @user = create(:user)
    @other_user = create(:user)
    @installation = create :enterprise_installation

    @date_range = Date.parse("2018-03-05")..Date.parse("2018-04-01")

    @contribution_record_1 = EnterpriseContribution.insert_or_update_contribution(@user, @installation, Date.parse("2018-03-05"), 22)
    @contribution_record_2 = EnterpriseContribution.insert_or_update_contribution(@user, @installation, Date.parse("2018-04-01"), 33)

    @contribution_1 = Contribution::EnterpriseContributionInfo.new(
      user: @user,
      subject: @contribution_record_1,
    )
  end

  context "#occurred_at" do
    test "returns a timestamp matching the contribution date informed by GHE" do
      assert_equal Date.parse("2018-03-05"), @contribution_1.occurred_at
    end
  end

  context "#count" do
    test "returns the number of contributions aggreggated by the database record" do
      assert_equal 22, @contribution_1.contributions_count
    end
  end

  context "#associated_subject" do
    test "returns the (dotcom) user whose contributions are being counted" do
      assert_equal @contribution_record_1, @contribution_1.associated_subject
    end
  end

  context "::subjects_for" do
    test "only includes database records for a given user in a given time range" do
      out_of_range_contribution_record = EnterpriseContribution.insert_or_update_contribution(@user, @installation, Date.parse("2018-04-15"), 66)
      other_user_contribution_record = EnterpriseContribution.insert_or_update_contribution(@other_user, @installation, Date.parse("2018-04-01"), 99)

      contributions = Contribution::EnterpriseContributionInfo::subjects_for(@user, date_range: @date_range)
      assert_equal 2, contributions.count
      assert_includes contributions, @contribution_record_1
      assert_includes contributions, @contribution_record_2
      refute_includes contributions, out_of_range_contribution_record
      refute_includes contributions, other_user_contribution_record
    end

    test "returns an empty collection when filtering by organization_id" do
      contributions = Contribution::EnterpriseContributionInfo::subjects_for(@user, date_range: @date_range, organization_id: 123)

      assert_empty contributions
    end
  end
end
