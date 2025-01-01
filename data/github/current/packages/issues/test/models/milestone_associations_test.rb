# typed: true
# frozen_string_literal: true

require "test_helper"

class MilestoneAssociationTest < GitHub::TestCase
  fixtures do
    @ari = create(:user, login: "ari")
    @source = create(:repository, owner: @ari, from_example: :pull_request_source)

    @bwalsh = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @bwalsh, fork_repo: @source, from_example: :pull_request_fork)

    issue = build(:issue, repository: @source, user: @bwalsh)

    @pull = PullRequest.create_for!(@source,
      user: @bwalsh,
      base: "ari:master",
      head: "bwalsh:topic",
      title: issue.title,
      body: issue.body)

    @issue = @pull.issue

    @milestone = create(:milestone, repository: @source)
  end

  test "finds associated pull requests" do
    assert @milestone.pull_requests.empty?
    @pull.issue.update!(milestone: @milestone)
    assert_equal [@pull], @milestone.pull_requests
  end

  test "finds associated issues" do
    assert @milestone.issues.empty?
    @issue.update!(milestone: @milestone)
    assert_equal [@issue], @milestone.reload.issues
  end

  test "finds open issues" do
    assert @milestone.open_issues.empty?
    @issue.update!(state: "open", milestone: @milestone)
    assert_equal [@issue], @milestone.open_issues
  end

  test "finds open pull requests" do
    assert @milestone.open_pull_requests.empty?
    @pull.issue.update!(state: "open", milestone: @milestone)
    assert_equal [@pull], @milestone.reload.open_pull_requests
  end

  test "finds closed pull requests" do
    assert @milestone.closed_pull_requests.empty?
    @pull.issue.update!(state: "closed", milestone: @milestone)
    assert_equal [@pull], @milestone.reload.closed_pull_requests
  end

  test "finds closed issues" do
    assert @milestone.closed_issues.empty?
    @issue.update!(state: "closed", milestone: @milestone)
    assert_equal [@issue], @milestone.closed_issues
  end

  test "counts open issues" do
    assert_equal 0, @milestone.open_issues_count
    @issue.update!(milestone: @milestone, pull_request_id: nil)
    assert_equal 1, @milestone.open_issues_count
    @issue.update!(pull_request: @pull)
    assert_equal 0, @milestone.open_issues_count
  end

  test "counts open pull requests" do
    assert_equal 0, @milestone.open_pull_requests_count
    @pull.issue.update!(milestone: @milestone)
    assert_equal 1, @milestone.open_pull_requests_count
    @pull.issue.update!(pull_request: nil)
    assert_equal 0, @milestone.open_pull_requests_count
  end
end
