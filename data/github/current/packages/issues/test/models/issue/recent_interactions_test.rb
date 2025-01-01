# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueRecentInteractionsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    @org = create(:organization)
    @org.add_member(@user)

    @org_repo = create(:repository, owner: @org)
    @org_repo.add_member(@user)

    unless GitHub.enterprise?
      @emu = create :emu
      @emu_business = @emu.enterprise_managed_business
      GitHub.flipper[:ip_allowlist_user_level_enforcement].enable(@emu_business)
      create :ip_allowlist_entry, owner: @emu_business
      @emu_business.enable_ip_allowlist actor: @emu_business.owners.first
      @emu_business.enable_ip_allowlist_user_level_enforcement actor: @emu_business.owners.first
      @other_emu = create :emu, business: @emu_business
      @emu_repo = create :repository, owner: @other_emu
      @emu_repo.add_member(@emu)
    end
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "#fetch" do
    test "excludes issue whose repository has been deleted" do
      issue = create(:issue, user: @user)
      issue.repository.delete
      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])

      assert_empty fetcher.fetch(limit: 10)
    end

    test "returns an empty list when no types are given" do
      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [])
      assert_empty fetcher.fetch(limit: 10)
    end

    test "times each SQL query when organization ID is not given" do
      create(:issue, user: @user)
      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago,
                                              types: [:issue, :pull_request])

      fetcher.fetch(limit: 10)

      assert_equal 1, GitHub.dogstats.timings("recent-activity.issue-events").size
      assert_equal 1, GitHub.dogstats.timings("recent-activity.review-requests").size
      assert_equal 1, GitHub.dogstats.timings("recent-activity.created-issue-comments").size
      assert_equal 1, GitHub.dogstats.timings("recent-activity.received-issue-comments").size
      assert_equal 1, GitHub.dogstats.timings("recent-activity.opened-issues").size
      assert_equal 1, GitHub.dogstats.timings("recent-activity.assigned-issues").size
      assert_equal 0, GitHub.dogstats.timings("recent-activity.issue-events.in-org").size
      assert_equal 0, GitHub.dogstats.timings("recent-activity.review-requests.in-org").size
      assert_equal 0, GitHub.dogstats.timings("recent-activity.created-issue-comments.in-org").size
      assert_equal 0, GitHub.dogstats.timings("recent-activity.received-issue-comments.in-org").size
      assert_equal 0, GitHub.dogstats.timings("recent-activity.opened-issues.in-org").size
      assert_equal 0, GitHub.dogstats.timings("recent-activity.assigned-issues.in-org").size
    end

    test "times each SQL query when organization ID is given" do
      create(:issue, user: @user)
      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, organization_id: @org.id,
                                              types: [:issue, :pull_request])

      fetcher.fetch(limit: 10)

      assert_equal 0, GitHub.dogstats.timings("recent-activity.issue-events").size
      assert_equal 0, GitHub.dogstats.timings("recent-activity.review-requests").size
      assert_equal 0, GitHub.dogstats.timings("recent-activity.created-issue-comments").size
      assert_equal 0, GitHub.dogstats.timings("recent-activity.received-issue-comments").size
      assert_equal 0, GitHub.dogstats.timings("recent-activity.opened-issues").size
      assert_equal 0, GitHub.dogstats.timings("recent-activity.assigned-issues").size
      assert_equal 1, GitHub.dogstats.timings("recent-activity.issue-events.in-org").size
      assert_equal 1, GitHub.dogstats.timings("recent-activity.review-requests.in-org").size
      assert_equal 1, GitHub.dogstats.timings("recent-activity.created-issue-comments.in-org").size
      assert_equal 1, GitHub.dogstats.timings("recent-activity.received-issue-comments.in-org").size
      assert_equal 1, GitHub.dogstats.timings("recent-activity.opened-issues.in-org").size
      assert_equal 1, GitHub.dogstats.timings("recent-activity.assigned-issues.in-org").size
    end

    test "excludes record created before cutoff time" do
      old_issue = Timecop.freeze(2.weeks.ago) { create(:issue, user: @user) }
      new_issue = Timecop.freeze(1.day.ago) { create(:issue, user: @user) }

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
      result = fetcher.fetch(limit: 10)

      assert_includes result.map(&:interactable), new_issue
      refute_includes result.map(&:interactable), old_issue
    end

    test "includes issue when :issue is in types" do
      issue = create(:issue, user: @user)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
      result = fetcher.fetch(limit: 10)

      assert_includes result.map(&:interactable), issue
    end

    test "truncates to 20 issues when not filtering by org ID" do
      30.times do |i|
        Timecop.freeze((30 - i).seconds.ago) do
          issue = create(:issue, user: @user)
        end
      end

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
      result = fetcher.fetch(limit: 30)
      assert_equal 20, result.count
    end

    test "excludes issue when in a repo owned by an org in excluded list" do
      excluded_issue = create(:issue, user: @user, repository: @org_repo)
      create(:assignment, assignee: @user, issue: excluded_issue)
      included_issue = create(:issue, user: @user)
      create(:assignment, assignee: @user, issue: included_issue)
      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue],
                                              excluded_account_ids: [@org.id])

      results = fetcher.fetch(limit: 10).map(&:interactable)
      refute_includes results, excluded_issue
      assert_includes results, included_issue
    end

    test "excludes issue when in a repo owned by specified org that is also in excluded list" do
      issue = create(:issue, user: @user, repository: @org_repo)
      create(:assignment, assignee: @user, issue: issue)
      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue],
                                              excluded_account_ids: [@org.id],
                                              organization_id: @org.id)

      assert_empty fetcher.fetch(limit: 10)
    end

    test "includes pull request when :pull_request is in types" do
      pull = make_pull_request_by(@user)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:pull_request])
      result = fetcher.fetch(limit: 10)

      assert_includes result.map(&:interactable), pull
    end

    test "excludes pull request when owned by an org in excluded list" do
      pull = make_pull_request_by(@user, repo: @org_repo)
      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:pull_request],
                                              excluded_account_ids: [@org.id])

      assert_empty fetcher.fetch(limit: 10)
    end

    test "excludes pull request when owned by specified org that is also in excluded list" do
      pull = make_pull_request_by(@user, repo: @org_repo)
      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:pull_request],
                                              excluded_account_ids: [@org.id],
                                              organization_id: @org.id)

      assert_empty fetcher.fetch(limit: 10)
    end

    test "excludes issue when owned by an EMU in excluded list", skip_enterprise: true do
      issue = create(:issue, user: @emu, repository: @emu_repo)
      create(:assignment, assignee: @emu, issue: issue)

      fetcher = Issue::RecentInteractions.new(
        @user,
        since: 1.week.ago,
        types: [:issue],
        excluded_account_ids: [@other_emu.id]
      )

      assert_empty fetcher.fetch(limit: 10)
    end

    test "excludes pull request when owned by an EMU in excluded list", skip_enterprise: true do
      pull = make_pull_request_by(@emu, repo: @emu_repo)
      fetcher = Issue::RecentInteractions.new(
        @user,
        since: 1.week.ago,
        types: [:pull_request],
        excluded_account_ids: [@other_emu.id]
      )

      assert_empty fetcher.fetch(limit: 10)
    end

    test "excludes pull request when types does not include :pull_request" do
      pull = make_pull_request_by(@user)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
      result = fetcher.fetch(limit: 10)

      refute_includes result.map(&:interactable), pull
    end

    test "excludes issue when types does not include :issue" do
      issue = create(:issue, user: @user)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:pull_request])
      result = fetcher.fetch(limit: 10)

      refute_includes result.map(&:interactable), issue
    end

    test "includes user created comment" do
      issue = create(:issue, user: @user)
      comment = create(:issue_comment, issue: issue, user: @user)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
      result = fetcher.fetch(limit: 10)

      assert_includes result.map(&:commenter), @user
      assert_equal "commented", result.first.interaction
    end

    test "includes commenter when user receives comment" do
      issue = create(:issue, user: @user)
      commenter = create(:user)
      comment = create(:issue_comment, issue: issue, user: commenter)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
      result = fetcher.fetch(limit: 10)

      assert_includes result.map(&:commenter), commenter
      assert_equal "received_comment", result.first.interaction
    end

    test "includes editor as commenter when created comment is edited" do
      issue = create(:issue, user: @user)
      editor = create(:user)

      issue.repository.add_member editor

      comment = create(:issue_comment, issue: issue, user: @user)
      user_content_edit = create(
        :user_content_edit,
        user: editor,
        user_content: comment,
        edited_at: Time.zone.now,
      )

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
      result = fetcher.fetch(limit: 10)

      assert_includes result.map(&:commenter), editor
      assert_equal "comment_edited", result.first.interaction
    end

    test "includes editor as commenter when received comment is edited" do
      issue = create(:issue, user: @user)
      editor = create(:user)

      issue.repository.add_member editor

      comment = create(:issue_comment, issue: issue, user: editor)
      user_content_edit = create(
        :user_content_edit,
        user: editor,
        user_content: comment,
        edited_at: Time.zone.now,
      )

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
      result = fetcher.fetch(limit: 10)

      assert_includes result.map(&:commenter), editor
      assert_equal "received_comment_edited", result.first.interaction

      commenter_fetcher = Issue::RecentInteractions.new(editor, since: 1.week.ago, types: [:issue])
      commenter_result = commenter_fetcher.fetch(limit: 10)

      assert_includes commenter_result.map(&:commenter), editor
      assert_equal "comment_edited", commenter_result.first.interaction
    end

    test "excludes issue when user can't access repository" do
      repo = create(:private_repository)
      repo.add_member @user
      issue = create(:issue, user: @user, repository: repo)
      repo.remove_member @user

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
      result = fetcher.fetch(limit: 10)

      refute_includes result.map(&:interactable), issue
    end

    test "excludes pull request when user can't access repository" do
      repo = create(:private_repository)
      repo.add_member @user
      pull = make_pull_request_by(@user, repo: repo)
      repo.remove_member @user

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:pull_request])
      result = fetcher.fetch(limit: 10)

      refute_includes result.map(&:interactable), pull
    end

    test "prefers most recent interaction when there are multiple  for a given issue or PR" do
      # Opened issue
      issue = Timecop.freeze(3.days.ago) { create(:issue, user: @user) }

      # Commented on issue
      comment = create(:issue_comment, issue: issue, user: @user)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
      result = fetcher.fetch(limit: 10)

      assert_equal 1, result.size
      assert_equal issue, result.first.interactable
      assert_equal "commented", result.first.interaction
      assert_equal comment.updated_at.to_i, result.first.occurred_at.to_i
    end

    test "considers issue comment from the user as an interaction" do
      issue = create(:issue)
      comment = create(:issue_comment, issue: issue, user: @user)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
      result = fetcher.fetch(limit: 10)

      assert_equal 1, result.size
      assert_equal "commented", result.first.interaction
      assert_equal issue, result.first.interactable
      assert_equal comment.updated_at.to_i, result.first.occurred_at.to_i
    end

    test "includes issue comment from the user on an org issue when org ID is given" do
      issue = create(:issue, repository: @org_repo)
      comment = create(:issue_comment, issue: issue, user: @user)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue],
                                              organization_id: @org.id)
      result = fetcher.fetch(limit: 10)

      assert_equal 1, result.size
      assert_equal "commented", result.first.interaction
      assert_equal issue, result.first.interactable
      assert_equal comment.updated_at.to_i, result.first.occurred_at.to_i
    end

    test "omits issue comment from the user on a non-org issue when org ID is given" do
      issue = create(:issue)
      comment = create(:issue_comment, issue: issue, user: @user)
      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue],
                                              organization_id: @org.id)

      assert_empty fetcher.fetch(limit: 10)
    end

    test "considers issue comment from someone else on items authored by the user as an interaction" do
      issue = create(:issue, user: @user)
      comment = create(:issue_comment, issue: issue, user: create(:user))

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
      result = fetcher.fetch(limit: 10)

      assert_equal 1, result.size
      assert_equal "received_comment", result.first.interaction
      assert_equal issue, result.first.interactable
      assert_equal comment.updated_at.to_i, result.first.occurred_at.to_i
    end

    test "includes issue comment on the user's issue owned by the org when org ID is given" do
      issue = create(:issue, user: @user, repository: @org_repo)
      comment = create(:issue_comment, issue: issue, user: create(:user))

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue],
                                              organization_id: @org.id)
      result = fetcher.fetch(limit: 10)

      assert_equal 1, result.size
      assert_equal "received_comment", result.first.interaction
      assert_equal issue, result.first.interactable
      assert_equal comment.updated_at.to_i, result.first.occurred_at.to_i
    end

    test "omits issue comment on the user's issue not owned by the org when org ID is given" do
      issue = create(:issue, user: @user)
      comment = create(:issue_comment, issue: issue, user: create(:user))
      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue],
                                              organization_id: @org.id)

      assert_empty fetcher.fetch(limit: 10)
    end

    test "considers assignment of a record to the user as an interaction" do
      time = Time.zone.now
      repo = create(:repository)
      issue = create(:issue, repository: repo)
      repo.add_member @user
      assignment = create(:assignment, issue: issue, assignee: @user, updated_at: time)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
      result = fetcher.fetch(limit: 10)

      assert_equal 1, result.size
      assert_equal "assigned", result.first.interaction
      assert_equal issue, result.first.interactable
      refute_nil result.first.occurred_at
    end

    test "includes assignment of a record to the user when record part of org and org ID given" do
      issue = create(:issue, repository: @org_repo)
      assignment = create(:assignment, issue: issue, assignee: @user)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue],
                                              organization_id: @org.id)
      result = fetcher.fetch(limit: 10)

      assert_equal 1, result.size
      assert_equal "assigned", result.first.interaction
      assert_equal issue, result.first.interactable
      refute_nil result.first.occurred_at
    end

    test "omits assignment of a record to the user when record not part of org and org ID given" do
      repo = create(:repository)
      issue = create(:issue, repository: repo)
      repo.add_member @user
      assignment = create(:assignment, issue: issue, assignee: @user)
      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue],
                                              organization_id: @org.id)

      assert_empty fetcher.fetch(limit: 10)
    end

    Issue::RecentInteractions::EVENT_ACTIONS.each do |event_type|
      test "considers #{event_type} event from the user an interaction" do
        issue = create(:issue)
        event = create(:issue_event, event: event_type, issue: issue, actor: @user)

        fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
        result = fetcher.fetch(limit: 10)

        assert_equal 1, result.size
        assert_equal event_type, result.first.interaction
        assert_equal issue, result.first.interactable
        assert_equal event.created_at.to_i, result.first.occurred_at.to_i
      end

      test "includes #{event_type} event from user within an org when that org ID is given" do
        issue = create(:issue, repository: @org_repo)
        event = create(:issue_event, event: event_type, issue: issue, actor: @user)

        fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue],
                                                organization_id: @org.id)
        result = fetcher.fetch(limit: 10)

        assert_equal 1, result.size
        assert_equal event_type, result.first.interaction
        assert_equal issue, result.first.interactable
        assert_equal event.created_at.to_i, result.first.occurred_at.to_i
      end

      test "omits #{event_type} event from the user when not tied to specified organization" do
        issue = create(:issue)
        event = create(:issue_event, event: event_type, issue: issue, actor: @user)
        fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue],
                                                organization_id: @org.id)

        assert_empty fetcher.fetch(limit: 10)
      end
    end

    test "considers received review from someone on the user's PR as an interaction" do
      repo = create(:repository)
      teammate = create(:user)
      pull = Timecop.freeze(2.weeks.ago) do # so it isn't included for being 'authored' recently
        make_pull_request_by(@user, repo: repo)
      end
      repo.add_member teammate
      review = create(:pull_request_review, :commented, user: teammate, pull_request: pull)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:pull_request])
      result = fetcher.fetch(limit: 10)

      assert_equal 1, result.size
      assert_equal "review_received", result.first.interaction
      assert_equal pull, result.first.interactable
      assert_equal review.submitted_at.to_i, result.first.occurred_at.to_i
      assert_equal teammate, result.first.commenter
      assert_nil result.first.comment_id
    end

    test "considers requested review from the user an interaction" do
      repo = create(:repository)
      pull = make_pull_request_by(create(:user), repo: repo)
      repo.add_member @user
      request = create(:review_request, reviewer_id: @user, pull_request: pull)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:pull_request])
      result = fetcher.fetch(limit: 10)

      assert_equal 1, result.size
      assert_equal "review_requested", result.first.interaction
      assert_equal pull, result.first.interactable
      assert_equal request.created_at.to_i, result.first.occurred_at.to_i
    end

    test "omits requested review when request has been dismissed" do
      repo = create(:repository)
      pull = make_pull_request_by(create(:user), repo: repo)
      repo.add_member @user
      request = create(:review_request, reviewer_id: @user, pull_request: pull)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:pull_request])
      result = fetcher.fetch(limit: 10)

      assert_equal 1, result.size
      assert_equal "review_requested", result.first.interaction

      request.dismiss
      request.save

      result = fetcher.fetch(limit: 10)
      assert_equal 0, result.size
    end

    test "includes received review from someone on the user's org PR when org ID is given" do
      teammate = create(:user)
      pull = Timecop.freeze(2.weeks.ago) do # so it isn't included for being 'authored' recently
        make_pull_request_by(@user, repo: @org_repo)
      end
      @org_repo.add_member teammate
      review = create(:pull_request_review, :commented, user: teammate, pull_request: pull)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:pull_request],
                                              organization_id: @org.id)
      result = fetcher.fetch(limit: 10)

      assert_equal 1, result.size
      assert_equal "review_received", result.first.interaction
      assert_equal pull, result.first.interactable
      assert_equal review.submitted_at.to_i, result.first.occurred_at.to_i
    end

    test "includes received pull request review comment" do
      teammate = create(:user)
      pull = travel_to(2.weeks.ago) do # so it isn't included for being 'authored' recently
        make_pull_request_by(@user, repo: @org_repo)
      end
      @org_repo.add_member teammate
      review_comment = create(:pull_request_review_comment, :submitted,
                              pull_request: pull,
                              user: teammate,
                              commit_id: pull.head_sha,
                              original_position: 1
                             )

      fetcher = Issue::RecentInteractions.new(teammate, since: 1.week.ago, types: [:pull_request],
        organization_id: @org.id)
      result = fetcher.fetch(limit: 10)

      assert_equal 1, result.size
      assert_equal "pull_request_review_commented", result.first.interaction
      assert_equal review_comment.id, result.first.comment_id
      assert_equal teammate, result.first.commenter
    end

    test "includes requested review from the user on org repo when org ID is given" do
      pull = make_pull_request_by(create(:user), repo: @org_repo)
      request = create(:review_request, reviewer_id: @user, pull_request: pull)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:pull_request],
                                              organization_id: @org.id)
      result = fetcher.fetch(limit: 10)

      assert_equal 1, result.size
      assert_equal "review_requested", result.first.interaction
      assert_equal pull, result.first.interactable
      assert_equal request.created_at.to_i, result.first.occurred_at.to_i
    end

    test "omits recently received review from someone on the user's non-org PR when org ID given" do
      repo = create(:repository)
      teammate = create(:user)
      pull = make_pull_request_by(@user, repo: repo)
      repo.add_member teammate
      create(:pull_request_review, :commented, user: teammate, pull_request: pull)

      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:pull_request],
                                              organization_id: @org.id)
      assert_empty fetcher.fetch(limit: 10)
    end

    test "omits requested review from the user on non-org repo when org ID is given" do
      repo = create(:repository)
      pull = make_pull_request_by(create(:user), repo: repo)
      repo.add_member @user
      request = create(:review_request, reviewer_id: @user, pull_request: pull)
      fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:pull_request],
                                              organization_id: @org.id)

      assert_empty fetcher.fetch(limit: 10)
    end

    if GitHub.spamminess_check_enabled?
      test "excludes issue from spammy user's repository" do
        spammer = create(:user, spammy: true)
        spam_repo = create(:repository, owner: spammer)
        issue = create(:issue, user: @user, repository: spam_repo)

        fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])
        result = fetcher.fetch(limit: 10)

        refute_includes result.map(&:interactable), issue
      end

      test "excludes pull request from spammy user's repository" do
        future_spammer = create(:user)
        repo_that_will_be_spammy = create(:repository, owner: future_spammer)
        pull = make_pull_request_by(@user, repo: repo_that_will_be_spammy)
        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { future_spammer.mark_as_spammy }

        fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:pull_request])
        result = fetcher.fetch(limit: 10)

        refute_includes result.map(&:interactable), pull
      end

      test "omits issue comments from spammy users" do
        issue = create(:issue, user: @user)
        spammer = create(:spammy_user)
        create(:issue_comment, issue: issue, user: spammer)
        fetcher = Issue::RecentInteractions.new(@user, since: 1.week.ago, types: [:issue])

        assert_empty fetcher.fetch(limit: 10)
      end
    end
  end

  def make_pull_request_by(user, repo: nil)
    repo ||= create(:repository)
    example_repo :simple, repo
    issue = create(:issue, user: user, repository: repo)
    create(:pull_request, user: user, repository: repo, head_ref: "cr-line-endings", issue: issue)
  end
end
