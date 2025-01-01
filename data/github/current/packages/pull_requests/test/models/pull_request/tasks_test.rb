# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestTasksTest < GitHub::TestCase
  fixtures do
    @owner  = create :user, login: "owner"
    @forker = create :user, login: "forker"

    @source = create :repository, owner: @owner, from_example: :pull_request_source
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @pr_issue = create :issue, repository: @source, user: @forker,
      body: "* [ ] task one\n* [ ] task two"

    @comment = @pr_issue.comments.create! body: "* [ ] comment task list item",
      user: @owner,
      issue: @pr_issue

    @pr = create :pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @pr_issue,
        user: @forker

    @pr_issue.pull_request = @pr

    @prrc1 = build(:pull_request_review_comment, pull_request: @pr, user: @owner, body: "cool")
    @prrc2 = build(:pull_request_review_comment, pull_request: @pr, user: @forker, body: "* [ ] prrc task")
    @pr.review_comments << @prrc1
    @pr.review_comments << @prrc2
  end

  setup do
    @tasks = PullRequest::Tasks.new(@pr)
  end

  test "gets all tasks" do
    assert_equal 4, @tasks.items.size
  end

  test "tasks have a permalink of their source comment" do
    assert_equal @pr.permalink, @tasks.items.first.permalink
    assert_equal @pr.permalink, @tasks.items[1].permalink
    assert_equal @comment.permalink, @tasks.items[2].permalink
    assert_equal @prrc2.permalink, @tasks.items[3].permalink
  end

  test "getting the number of complete items" do
    assert_equal 0, @tasks.complete_count
    @pr.issue.update! body: "* [x] task one\n* [ ] task two"

    @tasks = PullRequest::Tasks.new(@pr)
    assert_equal 1, @tasks.complete_count
  end
end
