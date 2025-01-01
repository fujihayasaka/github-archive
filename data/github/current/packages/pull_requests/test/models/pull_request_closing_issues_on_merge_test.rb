# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class PullRequestClosingIssuesOnMergeTest < GitHub::TestCase
  fixtures do
    @owner  = create(:user)
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @issue  = create(:issue, user: @forker, repository: @source)

    @commit_author = create(:user, email: "rtomayko@gmail.com", login: "rtomayko")
    @coauthor = create(:user, email: "happy.coauthor@gmail.com")
    message = <<~MESSAGE
      commit with a co-author

      co-authored-by: Homer Simpson <#{@coauthor.email}>
    MESSAGE
    branch = @fork.heads.find("topic")
    latest_commit = branch.
      append_commit({ message: message, author: @commit_author }, @commit_author) do |files|
        files.add("pizza", "pepperoni")
      end

    @cross_pull = PullRequest.create_for!(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @fork.user,
      title: "a cross-repo PR",
      body: "nothing special",
    )

    @same_pull = PullRequest.create_for!(@source,
      base: "master",
      head: "master-forward-2",
      user: @source.user,
      title: "a same-repo PR",
      body: "nothing special",
    )

    example_repo_snapshot
  end

  setup do
    example_repo_restore
    reset_cache
  end

  test "no issue reference, same repo" do
    @pull = @same_pull

    assert_no_difference "@issue.events.reload.size" do
      perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.open?
  end

  test "no issue reference, cross repo" do
    @pull = @cross_pull

    assert_no_difference "@issue.events.reload.size" do
      perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.open?
  end

  test "normal issue reference, same repo" do
    @pull = @same_pull

    @pull.issue.update(body: "Let's talk about ##{@issue.number}")

    assert_no_difference "@issue.events.reload.size" do
      perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.open?
  end

  test "normal issue reference, cross repo" do
    @pull = @cross_pull

    @pull.issue.update(body: "Let's talk about ##{@issue.number}")

    assert_no_difference "@issue.events.reload.size" do
      perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.open?
  end

  test "keyword issue reference, same repo" do
    @pull = @same_pull

    @pull.issue.update(body: "Let's talk about how this fixes ##{@issue.number}")

    assert_difference "@issue.events.reload.size" do
      perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.closed?

    event = @issue.events.last
    assert_equal "closed", event.event
    assert_equal @pull.issue, event.referencing_issue
  end

  test "keyword issue reference, cross repo" do
    @pull = @cross_pull

    @pull.issue.update(body: "Let's talk about how this fixes ##{@issue.number}")

    assert_difference "@issue.events.reload.size" do
      perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.closed?

    event = @issue.events.last
    assert_equal "closed", event.event
    assert_equal @pull.issue, event.referencing_issue
  end

  test "keyword issue reference, same repo, colon" do
    @pull = @same_pull

    @pull.issue.update(body: "Let's talk about how this thing.\n\nFixes: ##{@issue.number}")

    assert_difference "@issue.events.reload.size" do
      perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.closed?

    event = @issue.events.last
    assert_equal "closed", event.event
    assert_equal @pull.issue, event.referencing_issue
  end

  test "keyword issue reference, cross repo, colon" do
    @pull = @cross_pull

    @pull.issue.update(body: "Let's talk about how this thing.\n\nFixes: ##{@issue.number}")

    assert_difference "@issue.events.reload.size" do
      perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.closed?

    event = @issue.events.last
    assert_equal "closed", event.event
    assert_equal @pull.issue, event.referencing_issue
  end

  test "keyword multiple issue reference, same repo" do
    @pull = @same_pull

    other_issue = create(:issue, repository: @source)

    @pull.issue.update(body: "Let's talk about how this fixes ##{@issue.number} and also resolved ##{other_issue.number}")

    issues = [@issue, other_issue]
    sizes  = issues.collect { |i|  i.events.reload.size }
    perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }

    issues.zip(sizes).each do |issue, size|
      refute_equal size, issue.events.reload.size
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    issues.each do |issue|
      issue.reload
      assert issue.closed?

      event = issue.events.last
      assert_equal "closed", event.event
      assert_equal @pull.issue, event.referencing_issue
    end
  end

  test "keyword multiple issue reference, cross repo" do
    @pull = @cross_pull

    other_issue = create(:issue, repository: @source)

    @pull.issue.update(body: "Let's talk about how this fixes ##{@issue.number} and also resolved ##{other_issue.number}")

    issues = [@issue, other_issue]
    sizes  = issues.collect { |i|  i.events.reload.size }

    perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge(@owner) }

    issues.zip(sizes).each do |issue, size|
      refute_equal size, issue.events.reload.size
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @owner, @pull.merged_by

    issues.each do |issue|
      issue.reload
      assert issue.closed?

      event = issue.events.last
      assert_equal "closed", event.event
      assert_equal @pull.issue, event.referencing_issue
    end
  end

  test "multiple issue reference, first keyword, same repo" do
    @pull = @same_pull

    other_issue = create(:issue, repository: @source)

    @pull.issue.update(body: "Let's talk about how this fixes ##{@issue.number} and also involves ##{other_issue.number}")

    issue_size = @issue.events.reload.size
    other_size = other_issue.events.reload.size
    perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }

    refute_equal issue_size, @issue.events.reload.size
    assert_equal other_size, other_issue.events.reload.size

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.closed?

    event = @issue.events.last
    assert_equal "closed", event.event
    assert_equal @pull.issue, event.referencing_issue

    other_issue.reload
    assert other_issue.open?
  end

  test "multiple issue reference, first keyword, cross repo" do
    @pull = @cross_pull

    other_issue = create(:issue, repository: @source)

    @pull.issue.update(body: "Let's talk about how this fixes ##{@issue.number} and also involves ##{other_issue.number}")

    issue_size = @issue.events.reload.size
    other_size = other_issue.events.reload.size
    perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge(@owner) }

    refute_equal issue_size, @issue.events.reload.size
    assert_equal other_size, other_issue.events.reload.size

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @owner, @pull.merged_by

    @issue.reload
    assert @issue.closed?

    event = @issue.events.last
    assert_equal "closed", event.event
    assert_equal @pull.issue, event.referencing_issue

    other_issue.reload
    assert other_issue.open?
  end

  test "multiple issue reference, last keyword, same repo" do
    @pull = @same_pull

    other_issue = create(:issue, repository: @source)

    @pull.issue.update(body: "Let's talk about how this involves ##{@issue.number} and also fixed ##{other_issue.number}")

    issue_size = @issue.events.reload.size
    other_size = other_issue.events.reload.size
    perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }

    assert_equal issue_size, @issue.events.reload.size
    refute_equal other_size, other_issue.events.reload.size

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.open?

    other_issue.reload
    assert other_issue.closed?

    event = other_issue.events.last
    assert_equal "closed", event.event
    assert_equal @pull.issue, event.referencing_issue
  end

  test "multiple issue reference, last keyword, cross repo" do
    @pull = @cross_pull

    other_issue = create(:issue, repository: @source)

    @pull.issue.update(body: "Let's talk about how this involves ##{@issue.number} and also fixed ##{other_issue.number}")

    issue_size = @issue.events.reload.size
    other_size = other_issue.events.reload.size
    perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge(@owner) }

    assert_equal issue_size, @issue.events.reload.size
    refute_equal other_size, other_issue.events.reload.size

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @owner, @pull.merged_by

    @issue.reload
    assert @issue.open?

    other_issue.reload
    assert other_issue.closed?

    event = other_issue.events.last
    assert_equal "closed", event.event
    assert_equal @pull.issue, event.referencing_issue
  end

  test "keyword issue reference without issue-close permission" do
    @pull = @cross_pull

    @issue = create(:issue, repository: @source)

    @pull.issue.update(body: "Let's talk about how this fixes ##{@issue.number}")

    assert_no_difference "@issue.events.reload.size" do
      perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.open?
  end

  test "keyword issue reference where base is not default branch, same repo" do
    master_oid = @source.heads.find("master").target_oid
    @source.heads.create("not-master", master_oid, @owner)

    @pull = PullRequest.create_for!(@source,
      base: "not-master",
      head: "master-forward-2",
      user: @source.user,
      title: "a same-repo PR",
      body: "nothing special",
    )

    @pull.issue.update(body: "Let's talk about how this fixes ##{@issue.number}")

    assert_no_difference "@issue.events.reload.size" do
      perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.open?
  end

  test "keyword issue reference where base is not default branch, cross repo" do
    master_oid = @source.heads.find("master").target_oid
    @source.heads.create("not-master", master_oid, @owner)

    @pull = PullRequest.create_for!(@source,
      base: "not-master",
      head: "#{@fork.user}:topic",
      user: @fork.user,
      title: "a cross-repo PR",
      body: "nothing special",
    )

    @pull.issue.update(body: "Let's talk about how this fixes ##{@issue.number}")

    assert_no_difference "@issue.events.reload.size" do
      perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.open?
  end

  test "keyword full-url issue reference" do
    @pull = @same_pull

    url = "#{GitHub.url}/#{@issue.repository.name_with_owner}/issues/#{@issue.number}"
    @pull.issue.update(body: "Let's talk about how this fixes #{url}")

    assert_difference "@issue.events.reload.size" do
      perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.closed?

    event = @issue.events.last
    assert_equal "closed", event.event
    assert_equal @pull.issue, event.referencing_issue
  end

  test "keyword full-url issue reference with colon" do
    @pull = @same_pull

    url = "#{GitHub.url}/#{@issue.repository.name_with_owner}/issues/#{@issue.number}"
    @pull.issue.update(body: "Let's talk about how this thing.\n\nFixes: #{url}")

    assert_difference "@issue.events.reload.size" do
      perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.closed?

    event = @issue.events.last
    assert_equal "closed", event.event
    assert_equal @pull.issue, event.referencing_issue
  end

  test "keyword full-url pull reference" do
    @pull = @same_pull

    url = "#{GitHub.url}/#{@issue.repository.name_with_owner}/pull/#{@issue.number}"
    @pull.issue.update(body: "Let's talk about how this closes #{url} because it's a better solution")

    assert_difference "@issue.events.reload.size" do
      perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) { @pull.merge }
    end

    @pull.reload
    assert @pull.merged?
    assert @pull.closed?
    assert_equal @pull.user, @pull.merged_by

    @issue.reload
    assert @issue.closed?

    event = @issue.events.last
    assert_equal "closed", event.event
    assert_equal @pull.issue, event.referencing_issue
  end

  test "rollback when merging PR" do
    @pull = @same_pull

    @pull.issue.update(body: "This fixes ##{@issue.number}")

    @pull.expects(:save!).raises(ActiveRecord::RecordInvalid.new(@pull))
    perform_enqueued_jobs(only: [PullRequestCloseReferencedIssuesJob]) do
      assert_raises ActiveRecord::RecordInvalid do
        @pull.merge
      end
    end

    @pull.reload

    refute @pull.merged?
    refute @pull.closed?
    assert_nil @pull.merged_by

    @issue.reload
    refute @issue.closed?

    refute_includes @pull.issue.events.map(&:event), "closed"
    refute_includes @issue.events.map(&:event), "closed"
  end
end
