# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionContributionsByRepositoryTest < GitHub::TestCase
  context "#contributions" do
    test "can sort by occurred at" do
      oldest_contrib = stub(occurred_at: 1.month.ago)
      newest_contrib = stub(occurred_at: 1.week.ago)
      contribs_by_repo = Contribution::ContributionsByRepository.new(
        contributions: [oldest_contrib, newest_contrib], repository: stub, user: stub,
        contribution_type: Contribution::CreatedIssue, time_range: 2.months.ago..Time.current
      )
      assert_equal [newest_contrib, oldest_contrib],
        contribs_by_repo.contributions(order_by: { field: "occurred_at", direction: "DESC" })
    end

    test "can sort by commit count for commit contributions" do
      largest_contrib = stub(commit_count: 10)
      smallest_contrib = stub(commit_count: 5)
      contribs_by_repo = Contribution::ContributionsByRepository.new(
        contributions: [largest_contrib, smallest_contrib], repository: stub, user: stub,
        contribution_type: Contribution::CreatedCommit, time_range: 2.months.ago..Time.current
      )
      assert_equal [smallest_contrib, largest_contrib],
        contribs_by_repo.contributions(order_by: { field: "commit_count", direction: "ASC" })
    end

    test "cannot sort by commit count for non-commit contributions" do
      contribs_by_repo = Contribution::ContributionsByRepository.new(
        contributions: [stub, stub], repository: stub, user: stub,
        contribution_type: Contribution::CreatedIssue, time_range: 2.months.ago..Time.current
      )
      assert_raises do
        contribs_by_repo.contributions(order_by: { field: "commit_count", direction: "ASC" })
      end
    end

    test "cannot sort by unrecognized field" do
      contribs_by_repo = Contribution::ContributionsByRepository.new(
        contributions: [stub, stub], repository: stub, user: stub,
        contribution_type: Contribution::CreatedIssue, time_range: 2.months.ago..Time.current
      )
      assert_raises do
        contribs_by_repo.contributions(order_by: { field: "whatever", direction: "ASC" })
      end
    end
  end

  context "#total_count" do
    test "returns the sum of the contribution counts" do
      contrib = stub(contributions_count: 2)
      contribs_by_repo = Contribution::ContributionsByRepository.new(
        contributions: [contrib, contrib], repository: stub, user: stub,
        contribution_type: Contribution::CreatedCommit, time_range: 2.months.ago..Time.current
      )
      assert_equal 4, contribs_by_repo.total_count
    end
  end
end
