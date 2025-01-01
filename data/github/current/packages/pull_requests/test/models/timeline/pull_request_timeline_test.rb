# typed: true
# frozen_string_literal: true

require "test_helper"

class TimelinePullRequestTimelineTest < GitHub::TestCase
  include GitHub::LoggerHelper

  setup do
    @owner = create(:user)
    @viewer = create(:user)
    @rando = create(:user)
    @collaborator = create(:user)

    @repo = create(:repository, owner: @owner, from_example: :simple)
    @repo.add_member(@collaborator)

    @org = create(:organization, admin: @owner)
    @org_repo = create(:private_repository, owner: @org, from_example: :simple)

    @migration = create(:migration, owner: @org)
    @mannequin = create(:mannequin, owner: @org)

    example_repo_snapshot

    # An arbitrary moment in time that is not near a DST transition.
    # If we freeze at the current time, DST transitions cause flakiness.
    @now = DateTime.parse("2021-11-15T13:14:15Z")

    Timecop.freeze(@now) do
      @ref = @repo.heads.create("topic", @repo.heads.find("master").target, @repo.owner)
      @commit1 = @ref.append_commit({ message: "Add file1", committer: @repo.owner, committed_date: 100.minutes.ago.iso8601 }, @repo.owner) do |files|
        files.add("file1.txt", "line1\nline2\nline3\n")
      end
      @commit2 = @ref.append_commit({ message: "Add file2", committer: @repo.owner, committed_date: 50.minutes.ago.iso8601 }, @repo.owner) do |files|
        files.add("file2.txt", "file2")
      end
      @commit3 = @ref.append_commit({ message: "Add file3", committer: @repo.owner, committed_date: 30.minutes.ago.iso8601 }, @repo.owner) do |files|
        files.add("file3.txt", "file3")
      end

      @issue = create(:issue, repository: @repo)
      @pull = PullRequest.create_for(
        @repo,
        base: "master",
        head: @ref.name,
        user: @owner,
        issue: @issue,
      )

      @org_repo_ref = @org_repo.heads.create("topic", @org_repo.heads.find("master").target, @owner)
      @org_repo_commit1 = @org_repo_ref.append_commit({ message: "Add file1", committer: @owner, committed_date: 100.minutes.ago.iso8601 }, @owner) do |files|
        files.add("file1.txt", "line1\nline2\nline3\n")
      end

      @org_repo_issue = create(:issue, repository: @org_repo)
      @org_repo_pull = PullRequest.create_for(
        @org_repo,
        base: "master",
        head: @org_repo_ref.name,
        user: @owner,
        issue: @org_repo_issue,
      )

      @pull_request_commit1 = Platform::Models::PullRequestCommit.new(@pull, @commit1)
      @pull_request_commit2 = Platform::Models::PullRequestCommit.new(@pull, @commit2)
      @pull_request_commit3 = Platform::Models::PullRequestCommit.new(@pull, @commit3)

      LastSeenPullRequestRevision.add_seen_rev(@pull, @viewer, @commit2.oid)
      @pull_request_revision_marker = PullRequestRevisionMarker.latest_for(@pull, @viewer)
      @pull_request_revision_marker.created_at = @commit3.created_at

      @issue_comment = create(:issue_comment,
        issue: @issue,
        body: "foo",
        created_at: 99.minutes.ago,
      )

      @review1 = @pull.reviews.create!(
        head_sha: @pull.head_sha,
        user: create(:user),
        created_at: 98.minutes.ago,
      )
      @review1.approve!
      @review1.update_column(:submitted_at, 98.minutes.ago)

      @review2 = @pull.reviews.create!(
        head_sha: @pull.head_sha,
        user: create(:user),
        body: "just a comment",
        created_at: 97.minutes.ago,
      )
      @review2.comment!
      @review2.update_column(:submitted_at, 97.minutes.ago)

      @review3 = @pull.reviews.create!(
        user: create(:user),
        head_sha: @pull.head_sha,
        created_at: 96.minutes.ago,
      )

      review_comment = create(:pull_request_review_comment,
        pull_request: @pull,
        body: ":+1: totally rad!",
        user: create(:user),
        commit_id: @pull.head_sha,
        path: "file1.txt",
        original_position: 1,
        pull_request_review: @review3,
      )
      @review3.comment!
      @review3.update_column(:submitted_at, 96.minutes.ago)

      review = @pull.reviews.create!(
        user: create(:user),
        head_sha: @pull.head_sha,
        created_at: 95.minutes.ago,
      )

      create(:pull_request_review_comment,
        pull_request: @pull,
        body: "just commented",
        user: create(:user),
        commit_id: @pull.head_sha,
        path: "file1.txt",
        original_position: 1,
        pull_request_review: review,
        reply_to_id: review_comment.id,
      )
      review.comment!
      review.update_column(:submitted_at, 95.minutes.ago)

      @legacy_review_comment = build(:legacy_pull_request_review_comment,
        body: "just commented",
        user: create(:user),
        commit_id: @pull.head_sha,
        path: "file1.txt",
        original_position: 1,
        pull_request: @pull,
        reply_to_id: nil,
        created_at: 94.minutes.ago,
      ).submit!

      @legacy_review_thread = @legacy_review_comment.pull_request_review_thread

      @hidden_referenced_event = @issue.reference_from_commit(@owner, @commit1.oid)
      @hidden_referenced_event.update_column(:created_at, 92.minutes.ago)

      @labeled_event = IssueEvent.create!(
        issue: @issue,
        actor: @owner,
        event: "labeled",
        label: create(:label, name: "bug"),
        created_at: 79.minutes.ago,
      )
      @renamed_event = IssueEvent.create!(
        issue: @issue,
        actor: @owner,
        event: "renamed",
        created_at: 78.minutes.ago,
      )

      @cross_reference = @issue.record_reference_from(
        create(:issue, repository: @repo),
        @owner,
        77.minutes.ago,
      )
      @cross_reference.update_column(:created_at, 77.minutes.ago)

      @commit_comment = create(:commit_comment,
        user: @rando,
        repository: @repo,
        commit_id: @commit1.oid,
        path: "file1.txt".dup,
        position: 0,
        created_at: 76.minutes.ago,
      )
      @commit_comment_reply = create(:commit_comment,
        user: @rando,
        repository: @commit_comment.repository,
        commit_id: @commit_comment.commit_id,
        path: @commit_comment.path,
        position: @commit_comment.position,
        created_at: 75.minutes.ago,
      )
      @commit_comment_thread = ::Platform::Models::PullRequestCommitCommentThread.new(
        @pull,
        @commit_comment.repository.id,
        @commit_comment.commit_id,
        @commit_comment.path,
        @commit_comment.position,
      )

      Timecop.freeze(70.minutes.ago) do
        @issue.lock(@issue.owner)
      end
      @locked_event = @issue.events.locks.last

      @hidden_cross_reference = @issue.record_reference_from(
        create(:issue, repository: @repo),
        @owner,
        65.minutes.ago,
      )
      @hidden_cross_reference.update_column(:created_at, 65.minutes.ago)

      @hidden_commit_comment = create(:commit_comment,
        user: @rando,
        repository: @repo,
        commit_id: @commit1.oid,
        path: "file1.txt".dup,
        position: 1,
        created_at: 60.minutes.ago,
      )
      @hidden_commit_comment_reply = create(:commit_comment,
        user: @rando,
        repository: @hidden_commit_comment.repository,
        commit_id: @hidden_commit_comment.commit_id,
        path: @hidden_commit_comment.path,
        position: @hidden_commit_comment.position,
        created_at: 60.minutes.ago,
      )
      @hidden_commit_comment_thread = ::Platform::Models::PullRequestCommitCommentThread.new(
        @pull,
        @hidden_commit_comment.repository.id,
        @hidden_commit_comment.commit_id,
        @hidden_commit_comment.path,
        @hidden_commit_comment.position,
      )

      @visible_commit_comment = create(:commit_comment,
        user: @owner,
        repository: @repo,
        commit_id: @commit1.oid,
        path: "file1.txt".dup,
        position: 2,
        created_at: 55.minutes.ago,
      )
      @visible_commit_comment_reply = create(:commit_comment,
        user: @owner,
        repository: @visible_commit_comment.repository,
        commit_id: @visible_commit_comment.commit_id,
        path: @visible_commit_comment.path,
        position: @visible_commit_comment.position,
        created_at: 55.minutes.ago,
      )
      @visible_commit_comment_thread = ::Platform::Models::PullRequestCommitCommentThread.new(
        @pull,
        @visible_commit_comment.repository.id,
        @visible_commit_comment.commit_id,
        @visible_commit_comment.path,
        @visible_commit_comment.position,
      )

      @other_visible_commit_comment = create(:commit_comment,
        user: @collaborator,
        repository: @repo,
        commit_id: @commit2.oid,
        path: "file2.txt".dup,
        position: 0,
        created_at: 54.minutes.ago,
      )
      @other_visible_commit_comment_reply = create(:commit_comment,
        user: @collaborator,
        repository: @other_visible_commit_comment.repository,
        commit_id: @other_visible_commit_comment.commit_id,
        path: @other_visible_commit_comment.path,
        position: @other_visible_commit_comment.position,
        created_at: 54.minutes.ago,
      )
      @other_visible_commit_comment_thread = ::Platform::Models::PullRequestCommitCommentThread.new(
        @pull,
        @other_visible_commit_comment.repository.id,
        @other_visible_commit_comment.commit_id,
        @other_visible_commit_comment.path,
        @other_visible_commit_comment.position,
      )

      @deploy = create(:deployment,
        repository:  @repo,
        creator:  @owner,
        sha:  @commit1.oid,
      )

      @deployed_event = create(:issue_event,
        repository:  @repo,
        issue:  @issue,
        event:  "deployed",
        deployment_id:  @deploy.id,
        ref:  @ref.name,
      )

      @deployment_environment_changed = create(:issue_event,
        repository: @repo,
        issue: @issue,
        event: "deployment_environment_changed",
        deployment_id:  @deploy.id,
        ref: @ref.name,
      )
    end
  end

  test "loads timeline items" do
    items = Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      timeline = Timeline::PullRequestTimeline.new(@pull, viewer: @viewer)
      timeline.async_values.sync
    end

    refute_includes items, @hidden_referenced_event
    refute_includes items, @hidden_cross_reference
    refute_includes items, @hidden_commit_comment

    expected_items = [
      @pull_request_commit1,
      @issue_comment,
      @review1,
      @review2,
      @review3,
      @legacy_review_thread,
      @labeled_event,
      @renamed_event,
      @cross_reference,
      @locked_event,
      @pull_request_commit2,
      @pull_request_revision_marker,
      @pull_request_commit3,
      @deployed_event,
      @deployment_environment_changed
    ]

    expected_items.each_with_index do |expected_item, index|
      assert_equal expected_item, items[index], "Failed at item #{index}"
    end

    assert_equal expected_items.length, items.length
  end

  test "ensure that get_type gracefully handles if the object doesn't exist" do
    ::Platform::Schema.stubs(:get_type).returns(nil)

    items = Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      timeline = Timeline::PullRequestTimeline.new(@pull, viewer: @viewer)
      timeline.async_values.sync
    end

    # PullRequestRevisionMarker is the only event
    assert_equal 1, items.count

    report = Failbot.reports.last
    assert /Couldn't find event with type name:/ =~ Failbot.exception_message_from_hash(report)
  end

  test "does hide revision markers if rest of commits are authored by viewer" do
    Timecop.freeze(@now + 10.seconds) do
      LastSeenPullRequestRevision.add_seen_rev(@pull, @viewer, @commit3.oid)

      @repo.add_member(@viewer)
      only = [AddToSearchIndexJob]
      commit4 = perform_enqueued_jobs(only: only) do
        @ref.append_commit({ message: "Add file4", committer: @viewer, committed_date: 5.minutes.ago.iso8601 }, @viewer) do |files|
          files.add("file4.txt", "file4")
        end
      end
      @pull.reload

      pull_request_revision_marker = PullRequestRevisionMarker.latest_for(@pull, @viewer)
      pull_request_revision_marker.created_at = commit4.created_at

      items = Platform::Security::RepositoryAccess.with_viewer(@viewer) do
        timeline = Timeline::PullRequestTimeline.new(@pull, viewer: @viewer)
        timeline.async_values.sync
      end

      refute_includes items, @pull_request_revision_marker
      refute_includes items, pull_request_revision_marker
    end
  end

  test "does hide deployed event if not backed by a deployment" do
    deployed_event = create(:issue_event,
      repository:  @repo,
      issue:  @issue,
      event:  "deployed",
      deployment_id:  0,
      ref:  @ref.name,
    )
    @pull.reload

    items = Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      timeline = Timeline::PullRequestTimeline.new(@pull, viewer: @viewer)
      timeline.async_values.sync
    end

    refute_includes items, deployed_event
  end

  test "does hide deployed event by a spammy actor" do
    deployed_event = create(:issue_event,
      repository: @repo,
      issue: @issue,
      event: "deployed",
      actor: create(:spammy_user),
      ref: @ref.name,
    )
    @pull.reload

    items = Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      timeline = Timeline::PullRequestTimeline.new(@pull, viewer: @viewer)
      timeline.async_values.sync
    end

    refute_includes items, deployed_event
  end

  test "does hide deployed event by an actor blocked by the viewer" do
    deployed_event = create(:issue_event,
      repository: @repo,
      issue: @issue,
      event: "deployed",
      ref: @ref.name,
    )
    @pull.reload

    @viewer.block(deployed_event.actor)

    items = Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      timeline = Timeline::PullRequestTimeline.new(@pull, viewer: @viewer)
      timeline.async_values.sync
    end

    refute_includes items, deployed_event
  end

  test "does hide deployment_environment_changed event without a linked deployment" do
    @deployment_environment_changed2 = create(:issue_event,
      repository: @repo,
      issue: @issue,
      event: "deployment_environment_changed",
      ref: @ref.name,
    )

    items = Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      timeline = Timeline::PullRequestTimeline.new(@pull, viewer: @viewer)
      timeline.async_values.sync
    end

    assert_includes items, @deployment_environment_changed
    refute_includes items, @deployment_environment_changed2
  end

  test "allows restricting values to `since` timestamp" do
    since = @pull_request_commit2.created_at

    items = Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      timeline = Timeline::PullRequestTimeline.new(
        @pull, viewer: @viewer, filter_options: { since: since }
      )

      timeline.async_values.sync
    end

    unexpected_items = [
      @pull_request_commit1,
      @issue_comment,
      @review1,
      @review2,
      @review3,
      @legacy_review_thread,
      @labeled_event,
      @renamed_event,
      @cross_reference,
      @commit_comment_thread,
      @locked_event,
      @visible_commit_comment_thread,
      @other_visible_commit_comment_thread,
      @pull_request_commit2,
    ]

    expected_items = [
      @pull_request_revision_marker,
      @pull_request_commit3,
      @deployed_event,
      @deployment_environment_changed,
    ]

    expected_items.each_with_index do |expected_item, index|
      assert_equal expected_item, items[index], "Failed at item #{index}"
    end

    assert_equal expected_items.length, items.length

    unexpected_items.each do |item|
      refute_includes items, item
    end
  end

  test "filter merged and closed event together" do
    merged_event = T.let(nil, T.untyped)
    closed_event = T.let(nil, T.untyped)
    head_ref_deleted_event = T.let(nil, T.untyped)

    Timecop.freeze do
      merged_event = IssueEvent.create!(
        issue: @issue,
        actor: @owner,
        event: "merged",
        created_at: 10.minutes.ago,
      )
      closed_event = IssueEvent.create!(
        issue: @issue,
        actor: @owner,
        event: "closed",
        created_at: 10.minutes.ago + 1.second,
      )
      head_ref_deleted_event = IssueEvent.create!(
        issue: @issue,
        actor: @owner,
        event: "head_ref_deleted",
        created_at: 9.minutes.ago,
      )
    end

    since = merged_event.created_at

    items = Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      timeline = Timeline::PullRequestTimeline.new(
        @pull, viewer: @viewer, filter_options: {
          since: since, filter_closed_if_preceded_by_merged: true
        }
      )

      timeline.async_values.sync
    end

    refute_includes items, merged_event
    refute_includes items, closed_event
    assert_includes items, head_ref_deleted_event
  end

  test "does not return a submitted review twice" do
    @issue.unlock(@issue.owner)

    review = @pull.reviews.create!(
      user: @viewer,
      head_sha: @pull.head_sha,
    )
    create(:pull_request_review_comment,
      pull_request: @pull,
      body: "pending comment",
      user: @viewer,
      commit_id: @pull.head_sha,
      path: "file1.txt",
      original_position: 1,
      pull_request_review_id: review.id,
    )
    Timecop.freeze { review.update_column(:created_at, 10.minutes.ago) }

    items = Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      timeline = Timeline::PullRequestTimeline.new(@pull, viewer: @viewer)
      timeline.async_values.sync
    end
    assert_includes items, review

    review.comment!
    Timecop.freeze { review.update_column(:submitted_at, 1.minute.ago) }

    since = review.submitted_at + 1.second

    items = Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      timeline = Timeline::PullRequestTimeline.new(
        @pull, viewer: @viewer, filter_options: { since: since }
      )

      timeline.async_values.sync
    end
    refute_includes items, review
  end

  test "filter item types wanted together" do
    label_event = T.let(nil, T.untyped)
    assignee_event = T.let(nil, T.untyped)
    review_request_event = T.let(nil, T.untyped)

    Timecop.freeze do
      label_event = IssueEvent.create!(
        issue: @issue,
        actor: @owner,
        event: "labeled",
        label: create(:label, name: "bug"),
        created_at: 10.minutes.ago,
      )
      assignee_event = IssueEvent.create!(
        issue: @issue,
        actor: @owner,
        event: "assigned",
        created_at: 10.minutes.ago + 1.second,
      )
      review_request_event = IssueEvent.create!(
        issue: @issue,
        actor: @owner,
        event: "review_requested",
        created_at: 9.minutes.ago,
      )
    end

    items = Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      timeline = Timeline::PullRequestTimeline.new(
        @pull, viewer: @viewer, filter_options: {
          item_types: [Platform::Objects::ReviewRequestedEvent],
        }
      )

      timeline.async_values.sync
    end

    refute_includes items, assignee_event
    refute_includes items, label_event
    assert_includes items, review_request_event
  end

  test "fetch review request event attributed to mannequin" do
    review_request_event = T.let(nil, T.untyped)
    Timecop.freeze do
      review_request_event = IssueEvent.create!(
        issue: @org_repo_issue,
        actor: @mannequin,
        event: "review_requested",
        created_at: 9.minutes.ago,
      )
    end

    items = Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      timeline = Timeline::PullRequestTimeline.new(
        @org_repo_pull, viewer: @viewer, filter_options: {
          item_types: [Platform::Objects::ReviewRequestedEvent],
        }
      )

      timeline.async_values.sync
    end

    assert_includes items, review_request_event
  end

  test "respects commit topological order when using rev-list ordering" do
    repo = create(:repository, owner: @owner, from_example: :rebase_pull_request)

    pull = PullRequest.create_for!(repo,
      title: "test PR",
      body: "test PR",
      user: @owner,
      base: "master",
      head: "wacky",
    )

    expected_oids = %w(
      06936d8fc81e2eff94a8e85c08c643a4ebc549f8
      b6a9cfb9505d032f34a4dff46a4ffc8381ece1b4
      0e0d1f3a3a6beeb44a8d495c060a8807a9df9aac
    )

    items = Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      timeline = Timeline::PullRequestTimeline.new(pull, viewer: @viewer)
      timeline.async_values.sync
    end

    actual_oids = items.select do |item|
      item.is_a?(Platform::Models::PullRequestCommit)
    end.map { |prc| prc.commit.oid }

    assert_equal expected_oids, actual_oids
  end

  test "does not leak commit information in exception" do
    Timeline::PullRequestTimeline
      .any_instance.stubs(:build_pull_request_commit_placeholders)
      .raises(StandardError, "This error message has sensitive commit information")

    Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      timeline = Timeline::PullRequestTimeline.new(@pull, viewer: @viewer)

      error = assert_raises StandardError do
        timeline.async_values.sync
      end

      assert_equal "Something went wrong", error.message
    end
  end

  test "PR timeline does not show issue-project events" do
    disable_feature_flag(:show_pull_request_project_events)
    issue = create(:issue, repository: @repo)
    memex = create(:memex_project, owner: @owner)

    IssueEvent.create!(issue_id: issue.id, event: "added_to_project_v2", actor_id: @owner.id, project_id: memex.id)
    IssueEvent.create!(
      {
        issue_id: issue.id,
        event: "project_v2_item_status_changed",
        actor_id: @owner.id,
        source_id: "source_id",
        project_id: memex.id,
        project_status: "DONE",
        project_previous_status: "TODO",
      }
    )

    issue_timeline_events  = Platform::Security::RepositoryAccess.with_viewer(@owner) do
      issue_timeline = issue.timeline_model_for(@owner, {
        show_project_events: true
      })
      issue_timeline.async_filtered_placeholders.sync
    end

    # issue timeline has 2 items
    assert_equal 2, issue_timeline_events.size

    ref = @repo.heads.create("some_topic", @repo.heads.find("master").target, @repo.owner)
    commit = ref.append_commit({ message: "Add a file", committer: @repo.owner, committed_date: 30.minutes.ago.iso8601 }, @repo.owner) do |files|
      files.add("file.txt", "file")
    end

    # Create a PR from the issue
    pull = PullRequest.create_for!(@repo,
      user: @owner,
      base: "master",
      head: ref.name,
      issue: issue,
      body: "blah",
    )
    pull_request_commit = Platform::Models::PullRequestCommit.new(pull, commit)

    items = Platform::Security::RepositoryAccess.with_viewer(@owner) do
      timeline = Timeline::PullRequestTimeline.new(pull, viewer: @owner, filter_options: {
        show_project_events: true,
      })
      timeline.async_values.sync
    end

    # The PR timeline should not have the project events.
    # It should only have the commit event.
    assert_equal items.size, 1
    assert_equal items[0],  pull_request_commit
  end

  test "PR timeline does show issue-project events behind show_pull_request_project_events flag" do
    enable_feature_flag(:show_pull_request_project_events)
    issue = create(:issue, repository: @repo)
    memex = create(:memex_project, owner: @owner)

    IssueEvent.create!(issue_id: issue.id, event: "added_to_project_v2", actor_id: @owner.id, project_id: memex.id, repository_id: @repo.id)
    IssueEvent.create!(
      {
        issue_id: issue.id,
        event: "project_v2_item_status_changed",
        actor_id: @owner.id,
        source_id: "source_id",
        project_id: memex.id,
        project_status: "DONE",
        project_previous_status: "TODO",
        repository_id: @repo.id,
      }
    )

    issue_timeline_events  = Platform::Security::RepositoryAccess.with_viewer(@owner) do
      issue_timeline = issue.timeline_model_for(@owner, {
        show_project_events: true
      })
      issue_timeline.async_filtered_placeholders.sync
    end

    # issue timeline has 2 items
    assert_equal 2, issue_timeline_events.size

    ref = @repo.heads.create("some_topic", @repo.heads.find("master").target, @repo.owner)
    commit = ref.append_commit({ message: "Add a file", committer: @repo.owner, committed_date: 30.minutes.ago.iso8601 }, @repo.owner) do |files|
      files.add("file.txt", "file")
    end

    # Create a PR from the issue
    pull = PullRequest.create_for!(@repo,
      user: @owner,
      base: "master",
      head: ref.name,
      issue: issue,
      body: "blah",
    )
    pull_request_commit = Platform::Models::PullRequestCommit.new(pull, commit)

    items = Platform::Security::RepositoryAccess.with_viewer(@owner) do
      timeline = Timeline::PullRequestTimeline.new(pull, viewer: @owner, filter_options: {
        show_project_events: true,
      })
      values = timeline.async_values.sync
      values
    end

    # The PR timeline should have the project events and commit events behind the flag.
    assert_equal items.size, 3
    assert_equal items[0],  pull_request_commit
    assert_equal "added_to_project_v2", items[1].event
    assert_equal "project_v2_item_status_changed", items[2].event
  end
end
