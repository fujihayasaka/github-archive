# typed: true
# frozen_string_literal: true

require "test_helper"

class CrossReferenceTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  setup do
    GitHub.context.push(actor_id: @owner.id)
  end

  fixtures do
    @owner        = create :user, login: "owner", plan: "large"
    @authed       = create :user, login: "authed"
    @spammer      = create :user, login: "spammer", spammy: true
    @forker       = create :user, login: "forker"

    @repo         = create :private_repository, owner: @owner, from_example: :pull_request_source
    create(:collaborator, collaborator: @authed, repository: @repo)
    @repo.add_member(@forker)
    @issue        = create :issue, repository: @repo, user: @repo.owner
    @issue2       = create :issue, repository: @repo, user: @authed
    @issue3       = create :issue, repository: @repo, user: @authed

    @public_repo  = create(:public_repository, owner: @owner)

    fork = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :pull_request_fork)

    @pull = create(:pull_request,
        repository: @repo,
        base_repository: @repo,
        base_user: @repo.owner,
        base_ref: "master",
        head_repository: fork,
        head_user: fork.owner,
        head_ref: "topic",
        issue: create(:issue, repository: @repo, user: @forker),
        user: @forker,
      )

    @reference_from_pr_to_issue = @issue2.record_reference_from(@pull.issue, @forker, Time.now)
    @reference_from_issue_to_pr = @pull.issue.record_reference_from(@issue2, @owner, Time.now)
  end

  test "referenced_at falls back to created_at" do
    t   = Time.at(Time.now.to_i - 12345)  # no usec, thank you
    ref = create(:cross_reference, referenced_at: t)
    assert_equal t, ref.referenced_at

    ref = create(:cross_reference, referenced_at: nil)
    assert_equal ref.created_at, ref.referenced_at
  end

  test "not recording duplicate references" do
    record = @issue2.record_reference_from(@issue, @owner, Time.now)
    assert record.id

    record = @issue2.record_reference_from(@issue, @owner, Time.now)
    assert record.nil?
  end

  test "not recording self references" do
    record = @issue.record_reference_from(@issue, @owner, Time.now)
    assert_nil record
  end

  if GitHub.spamminess_check_enabled?
    test "spammy references not viewable to regular users", skip_with_all_emus: true do
      reference = @issue.record_reference_from(@issue2, @spammer, Time.now)
      refute_nil reference

      assert_equal [], @issue.references.filter_spam_for(nil)
      assert_equal [], @issue.references.filter_spam_for(@owner)
    end

    test "spammy references are viewable to the spammer" do
      reference = @issue.record_reference_from(@issue2, @spammer, Time.now)

      assert_equal [reference], @issue.references.filter_spam_for(@spammer)
    end

    test "spammy references are viewable to staff" do
      reference = @issue.record_reference_from(@issue2, @spammer, Time.now)

      staffer = create(:staff_admin_user)
      assert_equal [reference], @issue.references.filter_spam_for(staffer)
    end
  end

  test "async_source_issue_or_pull_request returns the correct type (Issue/PullRequest)" do
    assert_equal @pull, @reference_from_pr_to_issue.async_source_issue_or_pull_request.sync
    assert_equal @issue2, @reference_from_issue_to_pr.async_source_issue_or_pull_request.sync
  end

  test "async_source won't fail if source link is broken (bad data)" do
    @reference_from_pr_to_issue.source = nil

    assert_nil @reference_from_pr_to_issue.async_source_issue_or_pull_request.sync
  end

  test "async_target_issue_or_pull_request returns the correct type (Issue/PullRequest)" do
    assert_equal @issue2, @reference_from_pr_to_issue.async_target_issue_or_pull_request.sync
    assert_equal @pull, @reference_from_issue_to_pr.async_target_issue_or_pull_request.sync
  end

  test "async_target won't fail if target link is broken (bad data)" do
    @reference_from_pr_to_issue.target = nil

    assert_nil @reference_from_pr_to_issue.async_target_issue_or_pull_request.sync
  end

  test "async_path_uri links to target's path, with anchor based on reference source ('ref-<type>-<issue_db_id>')" do
    target_path = @issue2.async_path_uri.sync
    source_db_id = @pull.issue.id
    assert_equal "#{target_path}#ref-pullrequest-#{source_db_id}", @reference_from_pr_to_issue.async_path_uri.sync.to_s

    target_path = @pull.async_path_uri.sync
    source_db_id = @issue2.id
    assert_equal "#{target_path}#ref-issue-#{source_db_id}", @reference_from_issue_to_pr.async_path_uri.sync.to_s
  end

  test "async_path_uri won't fail if either source or target link is broken (bad data)" do
    @reference_from_issue_to_pr.source = nil
    assert_nil @reference_from_issue_to_pr.async_path_uri.sync

    @reference_from_pr_to_issue.target = nil
    assert_nil @reference_from_pr_to_issue.async_path_uri.sync
  end

  test "async_cross_repository? is false if source and target share the same repository" do
    reference = @issue2.record_reference_from(@issue, @owner, Time.now)

    refute reference.async_cross_repository?.sync
  end

  test "async_cross_repository? is true if source and target are in different repositories" do
    other_repo = create :repository, owner: @owner
    issue_in_other_repo = create :issue, repository: other_repo, user: @owner
    reference = @issue2.record_reference_from(issue_in_other_repo, @owner, Time.now)

    assert reference.async_cross_repository?.sync
  end

  test "async_cross_repository? won't fail if either source or target link is broken (bad data)" do
    @reference_from_issue_to_pr.source = nil
    refute @reference_from_issue_to_pr.async_cross_repository?.sync

    @reference_from_pr_to_issue.target = nil
    refute @reference_from_pr_to_issue.async_cross_repository?.sync
  end

  # These tests exercise all known reference paths. Not every possible
  # combination but the ones that are actively supported by the application.

  test "issue referencing issue" do
    issue = create(:issue)
    record = @issue.record_reference_from(issue, @owner, Time.now)
    assert record.id
    assert_equal "Issue", record.source_type
    assert_equal "Issue", record.target_type
    assert_equal  issue, record.source
    assert_equal @issue, record.target
  end

  context ".with_valid_target_issue" do
    test "returns only cross references with an existing target issue" do
      reference = @issue2.record_reference_from(@issue, @owner, Time.now)

      assert_includes CrossReference.all, reference
      assert_includes CrossReference.with_valid_target_issue.all, reference

      reference.target.delete

      assert_includes CrossReference.all, reference
      refute_includes CrossReference.with_valid_target_issue.all, reference
    end
  end

  context ".with_spammy_source_issues_hidden_for" do
    if GitHub.spamminess_check_enabled?
      test "returns only cross references which have a non-spammy source issue" do
        reference = @issue2.record_reference_from(@issue, @owner, Time.now)

        assert_includes CrossReference.all, reference
        assert_includes CrossReference.with_spammy_source_issues_hidden_for(@authed).all, reference

        reference.source.update_attribute(:user_hidden, true)

        assert_includes CrossReference.all, reference
        refute_includes CrossReference.with_spammy_source_issues_hidden_for(@authed).all, reference
      end
    else
      test "returns cross references even if they have a spammy source issue" do
        reference = @issue2.record_reference_from(@issue, @owner, Time.now)

        assert_includes CrossReference.all, reference
        assert_includes CrossReference.with_spammy_source_issues_hidden_for(@authed).all, reference

        reference.source.update_attribute(:user_hidden, true)

        assert_includes CrossReference.all, reference
        assert_includes CrossReference.with_spammy_source_issues_hidden_for(@authed).all, reference
      end
    end

    test "returns cross references to spammy source issues when viewed by the issue author", skip_with_all_emus: true do
      reference = @issue2.record_reference_from(@issue, @owner, Time.now)

      assert_includes CrossReference.all, reference
      assert_includes CrossReference.with_spammy_source_issues_hidden_for(@owner).all, reference

      reference.source.update_attribute(:user_hidden, true)

      assert_includes CrossReference.all, reference
      assert_includes CrossReference.with_spammy_source_issues_hidden_for(@owner).all, reference
    end
  end

  context ".with_valid_source_issue" do
    test "returns only cross references with an existing source issue" do
      reference = @issue2.record_reference_from(@issue, @owner, Time.now)

      assert_includes CrossReference.all, reference
      assert_includes CrossReference.with_valid_source_issue.all, reference

      reference.source.delete

      assert_includes CrossReference.all, reference
      refute_includes CrossReference.with_valid_source_issue.all, reference
    end
  end

  context ".created_before_target_conversation_was_locked" do
    test "does not include cross references created after their target issue was locked" do
      Timecop.travel do
        reference = @issue2.record_reference_from(@issue, @owner, Time.now)
        Timecop.travel(5)
        @issue2.lock(@owner)

        assert_includes CrossReference.all, reference
        assert_includes CrossReference.created_before_target_conversation_was_locked.all, reference
      end
    end

    test "includes cross references created before their target issue was locked" do
      Timecop.travel do
        @issue2.lock(@owner)
        Timecop.travel(5)
        reference = @issue2.record_reference_from(@issue, @owner, Time.now)

        assert_includes CrossReference.all, reference
        refute_includes CrossReference.created_before_target_conversation_was_locked.all, reference
      end
    end

    test "only hides references created after their target issue was locked last" do
      Timecop.travel do
        @issue2.lock(@owner)
        Timecop.travel(5)
        reference = @issue2.record_reference_from(@issue, @owner, Time.now)
        Timecop.travel(5)
        @issue2.unlock(@owner)
        Timecop.travel(5)
        @issue2.lock(@owner)

        other_reference = @issue2.record_reference_from(@issue3, @owner, Time.now)

        assert_includes CrossReference.all, reference
        assert_includes CrossReference.all, other_reference
        assert_includes CrossReference.created_before_target_conversation_was_locked.all, reference
        refute_includes CrossReference.created_before_target_conversation_was_locked.all, other_reference
      end
    end

    test "includes all events if the target issue gets unlocked again" do
      Timecop.travel do
        @issue2.lock(@owner)
        Timecop.travel(5)
        reference = @issue2.record_reference_from(@issue, @owner, Time.now)
        Timecop.travel(5)
        @issue2.unlock(@owner)

        assert_includes CrossReference.all, reference
        assert_includes CrossReference.created_before_target_conversation_was_locked.all, reference
      end
    end
  end

  context "async_will_close_target?" do
    test "false if not a PR->Issue ref" do
      reference = create :cross_reference
      reference.target = create(:issue)
      reference.source = create(:issue)
      refute reference.async_will_close_target?.sync
    end

    test "false if a PR->PR ref" do
      reference = create :cross_reference
      target = make_pull_request
      source = make_pull_request
      reference.target = target.issue
      reference.source = source.issue
      refute reference.async_will_close_target?.sync
    end

    test "false if a PR->Issue ref that does not close-ref target issue" do
      reference = create :cross_reference
      pull = make_pull_request
      issue = create(:issue, repository: pull.repository)
      reference.target = issue

      pull.issue.update(body: "let's talk about ##{issue.number}")
      pull.reload
      reference.source = pull.issue

      refute reference.async_will_close_target?.sync

      pull.issue.update(body: "This fixes ##{issue.number + 1} and oh let's talk about ##{issue.number}")
      pull.reload
      reference.source = pull.issue

      refute reference.async_will_close_target?.sync

      pull.issue.update(body: "let's talk about ##{issue.number} and oh this fixes ##{issue.number + 1}")
      pull.reload
      reference.source = pull.issue

      refute reference.async_will_close_target?.sync
    end

    test "false if a PR->Issue ref that does close-ref target issue, but issue is closed" do
      reference = create :cross_reference
      pull = make_pull_request
      issue = create(:issue, repository: pull.repository)
      issue.close
      refute issue.open?
      reference.target = issue

      pull.issue.update(body: "let's fix ##{issue.number}")
      pull.reload
      reference.source = pull.issue

      refute reference.async_will_close_target?.sync

      pull.issue.update(body: "This fixes ##{issue.number} and oh let's talk about ##{issue.number + 1}")
      pull.reload
      reference.source = pull.issue

      refute reference.async_will_close_target?.sync

      pull.issue.update(body: "let's talk about ##{issue.number + 1} and oh this fixes ##{issue.number}")
      pull.reload
      reference.source = pull.issue

      refute reference.async_will_close_target?.sync
    end

    test "true if a PR->Issue ref that does close-ref target issue and issue is open" do
      reference = create :cross_reference
      pull = make_pull_request
      issue = create(:issue, repository: pull.repository)
      assert issue.open?
      reference.target = issue

      perform_enqueued_jobs(only: [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]) do
        pull.issue.update!(body: "let's fix ##{issue.number}")
      end

      pull.reload
      reference.source = pull.issue

      assert reference.async_will_close_target?.sync
      pull.issue.update!(body: "This fixes ##{issue.number} and oh let's talk about ##{issue.number + 1}")
      pull.reload
      reference.source = pull.issue

      assert reference.async_will_close_target?.sync

      pull.issue.update!(body: "let's talk about ##{issue.number + 1} and oh this fixes ##{issue.number}")
      pull.reload
      reference.source = pull.issue

      assert reference.async_will_close_target?.sync
    end

    test "false if a PR->Issue ref that does close-ref target issue and PR is merged" do
      reference = create :cross_reference
      pull = make_pull_request
      issue = create(:issue, repository: pull.repository)
      reference.target = issue

      pull.issue.update(body: "let's fix ##{issue.number}")

      pull.reload
      pull.merge
      reference.source = pull.issue

      issue.open
      issue.reload
      assert issue.open?

      refute reference.async_will_close_target?.sync
    end

    test "false if a PR->Issue ref that does close-ref target issue and PR is closed" do
      reference = create :cross_reference
      pull = make_pull_request
      issue = create(:issue, repository: pull.repository)
      reference.target = issue

      pull.issue.update(body: "let's fix ##{issue.number}")

      pull.reload
      pull.close
      reference.source = pull.issue

      issue.open
      issue.reload
      assert issue.open?

      refute reference.async_will_close_target?.sync
    end

    test "false if a PR->Issue ref that does close-ref target issue and base ref is not default branch" do
      reference = create :cross_reference
      pull = make_pull_request
      issue = create(:issue, repository: pull.repository)
      assert issue.open?
      reference.target = issue

      pull.update(base_ref: "not-master")

      pull.issue.update(body: "let's fix ##{issue.number}")

      pull.reload
      reference.source = pull.issue

      refute reference.async_will_close_target?.sync
    end

    test "false if source or target can't be found (e.g., bad data)" do
      reference = create :cross_reference
      pull = make_pull_request
      issue = create(:issue, repository: pull.repository)

      perform_enqueued_jobs(only: [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]) do
        pull.issue.update(body: "let's fix ##{issue.number}")
      end

      pull.reload

      reference.source = pull.issue
      reference.target = issue
      assert reference.async_will_close_target?.sync

      reference.source = nil
      reference.target = issue
      refute reference.async_will_close_target?.sync

      reference.source = pull.issue
      reference.target = nil
      refute reference.async_will_close_target?.sync
    end

    test "false if source repository can't be found (e.g., bad data)" do
      reference = create :cross_reference
      pull = make_pull_request
      issue = create(:issue, repository: pull.repository)

      perform_enqueued_jobs(only: [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]) do
        pull.issue.update(body: "let's fix ##{issue.number}")
      end
      pull.reload

      reference.source = pull.issue
      reference.target = issue
      assert reference.async_will_close_target?.sync

      pull.repository_id = 9999999
      refute reference.reload.async_will_close_target?.sync
    end

    test "true if source repository is different from target and target is referenced within body" do
      reference = create :cross_reference
      pull = make_pull_request
      repository = create :repository
      issue = create(:issue, repository: repository)

      perform_enqueued_jobs(only: [UpdateCloseIssueReferencesJob, IssueOrchestration.job_class]) do
        pull.issue.update(body: "let's fix #{issue.url}")
      end
      pull.reload

      reference.source = pull.issue
      reference.target = issue
      assert reference.async_will_close_target?.sync
    end
  end

  context "set source and target `repository_id` when applicable" do
    test "set source `repository_id` when source is an issue" do
      repository = create :repository
      issue = create(:issue, repository: repository)

      cross_reference = create(:cross_reference, source: issue)

      refute_nil cross_reference.source_repository_id
      assert_equal repository.id, cross_reference.source_repository_id
    end

    test "set source `repository_id` when source is a discussion" do
      # repository = create :repository
      discussion = create(:discussion)
      repository = discussion.repository

      cross_reference = create(:cross_reference, source: discussion)

      refute_nil cross_reference.source_repository_id
      assert_equal repository.id, cross_reference.source_repository_id
    end

    test "set target `repository_id` when target has such a property" do
      repository = create :repository
      issue = create(:issue, repository: repository)

      cross_reference = create(:cross_reference, target: issue)

      refute_nil cross_reference.target_repository_id
      assert_equal repository.id, cross_reference.target_repository_id
    end

    test "handle case when target doesn't have a `repository_id` gracefully" do
      team = create :team

      cross_reference = create(:cross_reference, target: team)

      assert_nil cross_reference.target_repository_id
    end
  end
end
