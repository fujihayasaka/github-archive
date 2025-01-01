# typed: true
# frozen_string_literal: true

require "test_helper"

class Repository::MilestoneDependencyTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner)

    @milestones = 6.times.map do |n|
      create(:milestone, repository: @repo, title: "v#{n}", state: n < 3 ? "closed" : "open")
    end

    @v0_issue = create(:issue, repository: @repo, milestone: @milestones[0], state: "closed")
    @v4_issue = create(:issue, repository: @repo, milestone: @milestones[4])

    @milestones.select(&:closed?).each_with_index do |m, index|
      m.touch(time: (3 - index).weeks.ago)
    end
  end

  context "#available_milestones" do
    test "returns separate list of open and closed milestones" do
      open_milestones, closed_milestones = @repo.available_milestones

      # Open milestones are sorted by title
      assert_equal %w(v3 v4 v5), open_milestones.map(&:title)

      # Closed milestones are sorted by descending updated_at
      assert_equal %w(v2 v1 v0), closed_milestones.map(&:title)
    end

    test "omits provided current_milestone from list of open milestones" do
      assert_predicate @v4_issue.milestone, :open?
      open_milestones, _ = @repo.available_milestones(current_milestone: @v4_issue.milestone)
      refute_includes open_milestones.map(&:id), @v4_issue.milestone_id
    end

    test "omits provided current_milestone from list of closed milestones" do
      assert_predicate @v0_issue.milestone, :closed?
      _, closed_milestones = @repo.available_milestones(current_milestone: @v0_issue.milestone)
      refute_includes closed_milestones.map(&:id), @v0_issue.milestone_id
    end
  end
end
