# typed: true
# frozen_string_literal: true

require "test_helper"

class PrefillingIssueTimelineTest < GitHub::TestCase
  fixtures do
    make_public_repo
    example_repo :pull_request_fork, @pub_repo
    @collab = make_collab_for @pub_repo
    @remote_repo = create(:repository, owner: @collab, from_example: :simple)

    @pub_pull = PullRequest.create_for @pub_repo,
      user: @owner,
      base: "master",
      head: "#{@owner}:topic",
      title: "Fixing this public bug",
      body: "Finna fix this public bug"
    @pull_issue = @pub_pull.issue

    # Make sure the author email for commits in this PR map to an account, so that we can verify author prefill.
    email = @owner.add_email "rtomayko@gmail.com"
    email.verify!
  end

  test "prefills Commit authors" do
    timeline = @pub_pull.timeline_for(@owner)

    commits = timeline.select { |item| item.is_a? Commit }
    IssueTimeline.prefill(timeline)

    assert_query_count(0) do
      commits.each do |commit|
        # The example repo has commits with generic email addrs that we explicitly won't map to authors
        assert_equal @owner, commit.author unless UserEmail.generic_domain?(commit.author_email)
      end
    end
  end

  # Commit reference events get extra prefilling in IssueEventPrefiller.prefill
  test "prefills commit reference commit comment counts and commits" do
    Spokesd.enable_spokesd

    @pull_issue.reference_from_commit(@collab, "2c6363c328126bdee83e9f8dd55ad1db3a2aa160", @remote_repo)

    # Force push a thing
    head_ref    = @pub_repo.heads.find(@pub_pull.head_ref)
    orig_oid    = @pub_pull.head_sha
    orig_commit = @pub_repo.commits.find(orig_oid)
    commit_data = { message: "This was force-pushed", committer: @owner }
    new_commit  = @pub_repo.commits.create(commit_data, orig_commit.parent_oids.first) do |files|
      files.add("aquaman.txt", "this is\na bunch of new\ncontent\nand it's\ngreat\n")
      files.remove("file3") # prevent a merge conflict
    end
    head_ref.update(new_commit.oid, @owner)
    @pub_pull.synchronize!(user: @owner, repo: @pub_repo, forced: true, ref: @pub_pull.head_ref, before: orig_oid, after: new_commit.oid)

    timeline = @pub_pull.timeline_for(@owner)

    # TODO: refactor selecting commit refs from events in IssueEventPrefiller.prefill
    # so we're not copying the implementation here.
    commit_refs = timeline.select { |item| item.is_a?(IssueEvent) && (item.commit_id? || item.force_push?) }

    commit_refs.each do |ref|
      refute ref.instance_variable_defined?("@commit"), "Reference commit should not be loaded"
    end

    IssueTimeline.prefill(timeline)

    assert_query_count(0) do
      commit_refs.each do |ref|
        assert ref.instance_variable_defined?("@commit"), "Reference commit should be loaded"
        commit = ref.commit

        # There is no commit_id to prefill for a force push event
        if !ref.force_push?
          # Prefilled via GitRPC
          refute_nil commit
          assert commit.instance_variable_get("@repository"), "Commit repository should be loaded"
          refute_nil commit.repository

          # Prefilled via SQL
          assert commit.instance_variable_get("@comment_count"), "Commit comment count should be loaded"
          refute_nil commit.comment_count
        end
      end
    end
  end

  test "prefills IssueEvent actors, issues, and repositories" do
    @pull_issue.update_attribute(:title, "Adding this feature")

    timeline = @pub_pull.timeline_for(@owner)

    IssueTimeline.prefill(timeline)

    assert_query_count(0) do
      assert rename = timeline.detect { |item| item.is_a?(IssueEvent) && item.event == "renamed" },
        "Rename event is missing for PR"

      assert_equal @owner, rename.actor
      assert_equal @pull_issue, rename.issue
      assert_equal @pub_repo, rename.repository
    end
  end

  test "prefills cross-reference actors, sources, and source repositories" do
    remote_issue = create :issue, repository: @remote_repo, user: @collab, created_at: 2.hours.ago
    @pull_issue.record_reference_from(remote_issue, @collab, Time.now)

    timeline = @pub_pull.timeline_for(@owner)
    IssueTimeline.prefill(timeline)

    assert_query_count(0) do
      cross_ref = timeline.detect { |item| item.is_a? CrossReference }

      assert_equal @collab, cross_ref.actor
      assert_equal remote_issue, cross_ref.source
      assert_equal @remote_repo, cross_ref.source.repository
    end
  end

  test "prefills issue comment issue, repository, performed_via_integration, user" do
    integration = create(:integration)
    comment = @pull_issue.comments.create!(user: @owner, body: ":sparkles:", performed_via_integration: integration)
    comment.update_body(":sunglasses:", @owner)

    timeline = @pub_pull.timeline_for(@owner)
    IssueTimeline.prefill(timeline)

    assert_query_count(0) do
      comment = timeline.detect { |item| item.is_a? IssueComment }

      assert_equal @owner, comment.user
      assert_equal integration, comment.performed_via_integration
      assert_equal @pull_issue, comment.issue
      assert_equal @pub_repo, comment.repository

      comment_issue = comment.issue
      assert_equal @pub_pull, comment_issue.pull_request
      assert_equal @pub_repo, comment_issue.repository
    end
  end

  test "prefills PR review comments" do
    create :legacy_pull_request_review_comment, :with_edit, pull_request: @pub_pull, user: @owner

    timeline = Timecop.travel(1.minute.from_now) { @pub_pull.timeline_for(@owner) }

    IssueTimeline.prefill(timeline)

    assert_query_count(0) do
      review_thread = timeline.detect { |item| item.is_a? PullRequestReviewThread }
      pull_comments = review_thread.comments

      pull_comments.each do |comment|
        assert_equal @owner, comment.user
        comment_edits = comment.latest_user_content_edit
        assert_equal @owner, comment_edits.editor
      end
    end
  end
end
