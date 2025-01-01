# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Hierarchy::NotifyTrackedByJobTest < GitHub::TestCase
  include ActiveJob::TestHelper
  include JobTestHelper

  fixtures do
    @user = create(:user)
    @repository = create(:repository, owner: @user, has_issues: true)
    @issue = create(:issue, user: @user, repository: @repository)
    @issue2 = create(:issue, user: @user, repository: @repository)
  end

  test "enqueues the NotifyTrackedBy job when notify_tracked_by_issues is called`" do
    repository = create(:repository)
    GitHub.flipper[:tasklist_block].enable(repository.owner)
    GitHub.flipper[:issue_hierarchy_state].enable
    GitHub.flipper[:issues_graph_api_concurrent_faraday].enable
    issue = create(:issue, repository: repository)

    tracking_issue = IssuesGraph::Proto::Issue.new(
      key: IssuesGraph::Proto::Key.new(itemId: 50),
      userName: "login",
      repoName: "name",
      number: 1,
      repoId: 1,
      title: "tracked issue",
      url: "http://dummy-url.github.com/login/name/issues/1",
      state: "open",
    )
    tracking_block = IssuesGraph::Proto::TrackingBlock.new(issues: [tracking_issue])
    tracking_block_2 = IssuesGraph::Proto::TrackingBlock.new(issues: [tracking_issue])
    tracking_block_response = IssuesGraph::Proto::GetIssueResponse.new(trackedBy: [tracking_block, tracking_block_2])
    result = ::IssuesGraph::Result.success(tracking_block_response)
    GitHub.async_issues_graph_api_client.expects(:get_issue).once.with(
      has_entries(
        use_denormalized_data: false,
        key: IssuesGraph::Proto::Key.new(
          ownerId: repository.owner_id,
          itemId: issue.id,
        )
      )
    ).returns(Promise.resolve(result))

    issue.notify_tracked_by_issue
    assert_enqueued_with(job: NotifyTrackedByJob, args: [[tracking_issue.key&.itemId]])
  end
end
