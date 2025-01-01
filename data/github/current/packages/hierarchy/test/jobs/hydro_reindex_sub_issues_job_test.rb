# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

# issue_types basic tests
class HydroReindexSubIssuesJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    enable_feature_flag(:sub_issues)
    @org = create(:organization)
    @user = create(:user)
    @org.add_member(@user)

    @repo = create(:repository, owner: @org)
    @other_repo = create(:repository, owner: @org)

    @issue1 = create(:issue, repository: @repo)
    @issue2 = create(:issue, repository: @repo)
    @issue3 = create(:issue, repository: @repo)
    @issue4 = create(:issue, repository: @repo)

    @parent1 = create(:issue, repository: @other_repo)
    @parent2 = create(:issue, repository: @repo)

    @sub_issue1 = create(:issue, repository: @other_repo)
    @sub_issue2 = create(:issue, repository: @other_repo)
    @sub_issue3 = create(:issue, repository: @repo)

    @parent1.add_sub_issue!(@issue1, @user.id)

    @issue2.add_sub_issue!(@sub_issue1, @user.id)
    @issue2.add_sub_issue!(@sub_issue2, @user.id)

    @parent2.add_sub_issue!(@issue3, @user.id)
    @issue3.add_sub_issue!(@sub_issue3, @user.id)
  end

  EVENTS = [
    "github.repositories.v1.Transferred",
    "github.repositories.v1.Renamed",
  ]

  EVENTS.each do |event|
    test "on #{event}, reindexes all issues in the repo, and related parent and sub-issues outside of the repo" do
      Search.expects(:add_to_search_index).with("bulk_issues", @repo.id, "purge" => true).once

      [@parent1, @sub_issue1, @sub_issue2].each do |issue|
        Search.expects(:add_to_search_index).with("issue", issue.id).once
      end

      [@issue1, @issue2, @issue3, @issue4, @parent2, @sub_issue3].each do |issue|
        Search.expects(:add_to_search_index).with("issue", issue.id).never
      end

      message = { repository_id: @repo.id }
      perform_hydro_message_job(
        message,
        schema: event,
        queue: "hydro_reindex_sub_issues",
      )
    end
  end

  EVENTS.each do |event|
    test "on #{event}, only reindexes repo issues if there are no parent or sub-issues outside of the repo" do
      repo_no_sub_issues = create(:repository, owner: @org)
      issue = create(:issue, repository: repo_no_sub_issues)
      sub_issue = create(:issue, repository: repo_no_sub_issues)
      issue.add_sub_issue!(sub_issue, @user.id)

      Search.expects(:add_to_search_index).with("bulk_issues", repo_no_sub_issues.id, "purge" => true).once
      Search.expects(:add_to_search_index).with("issue", instance_of(Integer)).never

      message = { repository_id: repo_no_sub_issues.id }
      perform_hydro_message_job(
        message,
        schema: event,
        queue: "hydro_reindex_sub_issues",
      )
    end
  end
end
