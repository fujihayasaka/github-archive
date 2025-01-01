# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"
require "test_helpers/issue_event_test_helper"
require "test_helpers/query_identifier_helper"

class ShowLoaderNoAutoPreload < Issue::ShowLoader
  def preload
    # do nothing
  end
end

class Issue::ShowLoaderTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include IssueEventTestHelper
  include GitHub::PullRequestTestHelpers
  include QueryIdentifierHelper
  include IssuesGraphTestHelpers
  include UnlockedRepositoryCheckTestHelper

  fixtures do
    @integration = create(:integration, name: "app")
    @bot = @integration.bot
  end

  setup do
    clear_memoized_unlocked_repository_check
  end

  def compare_queries(expected_queries, actual_queries, message: nil)
    assert_equal parse_queries(expected_queries), identify_queries(actual_queries).sort, message
  end

  def assert_queries(expected_queries)
    clear_memoized_unlocked_repository_check

    # loader
    loader, queries = log_cleaned_queries do
      yield
    end
    compare_queries expected_queries, queries, message: "Unexpected queries while loading data"

    # adapter
    _, queries = log_cleaned_queries do
      Issue::ShowLoader.issue_adapter(loader)
    end
    compare_queries "", queries, message: "Expected no queries when creating an IssueAdapter"
  end

  context "preload" do
    context "empty timeline" do
      test "preloading does not execute unexpected queries" do
        viewer = create(:user)
        repo = create(:repository, owner: viewer)
        issue = create(:issue, repository: repo, user: viewer)
        assert_queries %{
          close_issue_references
          commit_contributions
          cross_references.has_timeline_items?
          issue_comments.has_timeline_items?
          issue_events.has_timeline_items?
          issue_reactions
          issue_transfers
          primary_avatars
          profiles
          repository_unlocks !dotcom
          sponsors check
          user_settings
          users
        } do
          Issue::ShowLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
        end
      end

      context "created by a bot" do
        test "preloading does not execute unexpected queries" do
          viewer = create(:user)
          repo = create(:repository, owner: viewer)
          issue = create(:issue, repository: repo, user: @bot)

          # Refetch Bot to dump memoized primary_avatar_path
          issue.user = Bot.find(@bot.id)

          assert_queries %{
            close_issue_references
            commit_contributions
            cross_references.has_timeline_items?
            integrations (load_for_bots)
            issue_comments.has_timeline_items?
            issue_events.has_timeline_items?
            issue_reactions
            issue_transfers
            marketplace_listings !enterprise
            primary_avatars
            primary_avatars (bots)
            profiles
            profiles (bots)
            repository_unlocks !dotcom
            sponsors check
            user_blocked_check
            user_emails !enterprise
            user_emails !enterprise
            user_settings
            users
            users (bot / integration owner)
          } do
            Issue::ShowLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
          end
        end
      end
    end

    context "with current issue reactions" do
      test "preloading does not execute unexpected queries" do
        viewer = create(:user)
        repo = create(:repository, owner: viewer)
        issue = create(:issue, repository: repo, user: viewer)

        # current issue reactions
        reacting_user_1 = create(:user)
        reacting_user_2 = create(:user)
        Reaction.react(user: reacting_user_1, subject_id: issue.id, subject_type: "Issue", content: "+1")
        Reaction.react(user: reacting_user_2, subject_id: issue.id, subject_type: "Issue", content: "+1")

        assert_queries %{
          close_issue_references
          commit_contributions
          cross_references.has_timeline_items?
          issue_comments.has_timeline_items?
          issue_events.has_timeline_items?
          issue_reactions
          issue_reactions
          issue_reactions
          issue_transfers
          primary_avatars
          profiles
          repository_unlocks !dotcom
          sponsors check
          user_settings
          users
        } do
          Issue::ShowLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
        end
      end
    end

    context "with comments" do
      test "preloading does not execute unexpected queries" do
        viewer = create(:user)
        repo = create(:repository, owner: viewer)
        issue = create(:issue, repository: repo, user: viewer)

        10.times do |i|
          user = create(:user)
          create(:profile, user: user, name: "User #{i}")

          issue.comments.create(user: user, body: "user comment #{i}")
        end

        10.times do |i|
          integration = create(:integration, name: "Integration #{i}")
          bot = integration.bot
          create(:profile, user: bot, name: "Bot #{i}")

          issue.comments.create(user: @bot, body: "bot comment #{i}")
        end

        # reload is required as the updates above trigger side-effects that attach associations
        issue.reload
        # simulate current_issue state
        issue.repository = repo
        issue.user = viewer

        assert_queries %{
          abilities
          abilities
          close_issue_references
          commit_contributions
          cross_references.load_timeline
          integrations
          issue_comment_edits
          issue_comment_reactions
          issue_comment_reactions
          issue_comments.has_timeline_items?
          issue_comments.load_timeline
          issue_comments.load_timeline
          issue_edits
          issue_events.load_timeline
          issue_reactions
          issue_transfers
          issues
          marketplace_listings !enterprise
          primary_avatars
          primary_avatars
          profiles
          profiles (bots)
          repositories
          repository_unlocks !dotcom
          sponsors check
          user_blocked_check
          user_settings
          users
          users (bots / integration owner)
        } do
          Issue::ShowLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
        end
      end

      test "handles when the integration owner is not available - https://github.com/github/issues/issues/12831" do
        viewer = create(:user)

        # In a private repository
        repo = create(:private_repository, owner: viewer)
        issue = create(:issue, repository: repo, user: viewer)

        # For a private integration
        integration = create(:integration, visibility: "private_visibility")

        create(:issue_comment, issue: issue, body: "bot comment", performed_by_integration_id: integration.id)

        # If the owner is not available
        integration.class.any_instance.stubs(:async_owner).returns(Promise.resolve(false))

        GitHub.flipper[:handle_integration_owner_nil].enable

        Failbot.expects(:report).with(instance_of(StandardError))

        Issue::ShowLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
      end
    end

    context "with everything" do
      test "does not execute unexpected queries" do
        user = create(:user)
        repo = create(:repository, owner: user, from_example: :simple)

        # see issue_event_test_helper for definitions
        issue = create_transfer_event(user, repo)
        create_connected_events(issue)
        create_reaction_events(issue)
        create_comment_events(issue)
        create_label_events(user, repo, issue)
        create_milestone_events(user, repo, issue)
        create_project_events(user, repo, issue)
        create_assignment_events(user, repo, issue)
        create_cross_reference_events(user, repo, issue)
        create_rename_events(issue)
        create_pinned_events(user, issue)
        create_blocked_user_events(user, repo, issue)

        # TODO issue_timeline:
        # Placeholder Platform Loader issues:
        #   * UserBlockedCheck is called many times deep in platform loader stacks and usually in a .sync'd block
        #   leading to over-querying ignored_users (4 times as of this writing)
        #
        #   * IssueEventSpammySubjectVisibleCheck & ProjectEventVisibleCheck both query isue_event_details in separate .sync'd blocks breaking batching
        #
        #   * 2 queries against abilities from ProjectEventVisibleCheck
        assert_queries %{
          (# TODO issue_timeline: can this be simplified?)
          abilities (ProjectEventVisibleCheck loading issue event placeholders)
          abilities ((children) for ProjectEventVisibleCheck loading issue event placeholders)
          abilities
          abilities
          close_issue_references
          commit_contributions (via CommitContributorCheck)
          configuration_entries (RepositoryProjectsEnabledCheck via ProjectEventVisibleCheck loading issue event placeholders)
          cross_references.load_timeline
          cross_references.load_timeline
          #{ GitHub.spamminess_check_enabled? ? "cross_references.load_timeline" : "" }
          internal_repositories
          issue_comment_edits
          issue_comment_reactions
          issue_comment_reactions
          issue_comments.load_timeline
          issue_comments.load_timeline
          issue_event_details (IssueEventSpammySubjectVisibleCheck loading user_blocked placeholders) !enterprise
          (# TODO issue_timeline: project visibility check needs some love most of these checks are .sync'd leaving little room for batching in platform code)
          issue_event_details (ProjectEventVisibleCheck loading issue event placeholders)
          issue_event_details (when loading timeline)
          issue_event_details
          issue_events.load_timeline
          issue_events.load_timeline
          issue_reactions
          issue_reactions
          issue_reactions
          issue_transfers (is_transfer_in_progress)
          issues (when loading timeline)
          issues
          issues (from IssueEvent::Loader)
          issues (from xrefs loading)
          labels
          milestones
          primary_avatars
          profiles
          project_cards
          projects ((owner Organization) for ProjectEventVisibleCheck loading issue event placeholders)
          projects ((projects with owners) for ProjectEventVisibleCheck loading issue event placeholders)
          projects
          pull_requests
          repositories (placeholder access checks in Platform::Loaders::Timeline::Placeholders:CrossReference)
          repositories (when loading timeline)
          repositories (RepositoryProjectsEnabledCheck via ProjectEventVisibleCheck loading issue event placeholders)
          repositories
          repositories (from IssueEvent::Loader)
          #{ GitHub.spamminess_check_enabled? ? "repositories" : "" }
          repository_unlocks !dotcom
          sponsors check
          user_blocked_check (UserBlockedCheck in Platform::Loaders::Timeline::Placeholders:CrossReference)
          user_blocked_check (UserBlockedCheck loading issue event placeholders)
          user_blocked_check (for UserBlockedCheck in prelude_viewer_can_react)
          user_settings
          user_spammy_check (UserSpammyCheck loading issue event placeholders)
          users (IssueEventSpammySubjectVisibleCheck loading user_blocked placeholders) !enterprise
          users
          users
        } do
          Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
        end
      end
    end
  end

  context "with comment deleted events" do
    test "preloading does not execute unexpected queries" do
      viewer = create(:user)
      spammy_user = create(:user, name: "spammy-user")
      spammy_user_2 = create(:user, name: "spammy-user-2")
      spammy_user.mark_as_spammy
      spammy_user_2.mark_as_spammy


      repo = create(:repository, owner: viewer)
      issue = create(:issue, repository: repo, user: viewer)
      comment1 = issue.comments.create(user: create(:user), body: "comment 1")
      comment2 = issue.comments.create(user: create(:user), body: "comment 2")
      comment3 = issue.comments.create(user: create(:user), body: "comment 3")
      comment4 = issue.comments.create(user: create(:user), body: "comment 4")

      comment1.stubs(:modifying_user).returns(create(:user))
      comment2.stubs(:modifying_user).returns(create(:user))
      comment3.stubs(:modifying_user).returns(spammy_user)
      comment4.stubs(:modifying_user).returns(spammy_user_2)
      comment1.destroy
      comment2.destroy
      comment3.destroy
      comment4.destroy

      assert_equal 4, issue.events.to_a.count { |e| e.event == "comment_deleted" }
      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.load_timeline
        issue_event_details
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        primary_avatars
        profiles
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "with labels" do
    test "preloading does not execute unexpected queries when label is applied by issue user" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)
      label = create(:label, name: "bug label", repository: repo)
      labeled_event = create(:issue_event, event: "labeled", issue: issue, actor: user, label: label)
      unlabeled_event = create(:issue_event, event: "unlabeled", issue: issue, actor: user, label: label)

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        labels
        primary_avatars
        profiles
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end

    test "preloading does not execute unexpected queries when label is applied by non issue user" do
      user = create(:user)
      other_user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)
      label = create(:label, name: "bug label", repository: repo)
      labeled_event = create(:issue_event, event: "labeled", issue: issue, actor: other_user, label: label)
      unlabeled_event = create(:issue_event, event: "unlabeled", issue: issue, actor: other_user, label: label)

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        labels
        primary_avatars
        profiles
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "with closed" do
    expected_queries = %{
      close_issue_references
      commit_contributions
      cross_references.load_timeline
      issue_comments.has_timeline_items?
      issue_comments.load_timeline
      issue_event_details
      issue_events.has_timeline_items?
      issue_events.load_timeline
      issue_events.load_timeline
      issue_reactions
      issue_transfers
      issues
      primary_avatars
      profiles
      repository_unlocks !dotcom
      sponsors check
      user_blocked_check
      user_settings
      user_spammy_check
      users
    }

    test "preloading does not execute unexpected queries" do
      user = create(:user)
      other_user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, body: "issue body", user: user)
      create(:issue_event, event: "closed", issue: issue, actor: other_user)

      assert_queries expected_queries do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end

    test "preloading with multiple closed events from different users does not introduce N+1 queries" do
      user = create(:user)
      other_user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)

      20.times do
        create(:issue_event, event: "closed", issue: issue, actor: other_user)
        create(:issue_event, event: "reopened", issue: issue, actor: other_user)
      end

      assert_queries expected_queries do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end

    test "preloading with multiple closed events from different commits does not introduce N+1 queries" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)

      2.times do |_i|
        pull = make_pr_and_repos
        pull_repo = pull.repository
        head_ref = pull.repository.heads.find_or_build(pull.head_ref)
        commit = append_dummy_commit(head_ref, commit_message: "Closes ##{issue.number}")

        create(:issue_event, event: "closed", issue: issue, actor: user, commit_id: commit.oid)
        create(:issue_event, event: "reopened", issue: issue, actor: user)
      end

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events (closed_by_commit_oids preloading)
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        primary_avatars
        profiles
        repositories
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "with connected events" do
    test "preloading connected events do not execute unexpected queries" do
      user = create(:user)
      other_user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)
      10.times do
        create_connected_events(issue)
      end

      assert_queries %{
        business_user_accounts
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details (when loading placeholders)
        issue_event_details (when load_issue_events)
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues (when loading placeholders)
        issues
        issues (from IssueEvent::Loader)
        issues (from xrefs loading)
        primary_avatars
        profiles
        pull_requests
        repositories (when loading placeholders)
        repositories (repo loader)
        repositories (from IssueEvent::Loader)
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
        users
        users
        users
        users
        users
        users
        users
        users
        users
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "with milestones" do
    test "preloading does not execute unexpected queries" do
      user = create(:user)
      other_user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)
      milestone = create(:milestone, repository: repo, title: "Release 2.0")
      create(:issue_event, event: "milestoned", issue: issue, actor: other_user, milestone_id: milestone.id, milestone_title: milestone.title, subject: user)
      create(:issue_event, event: "demilestoned", issue: issue, actor: other_user, milestone_id: milestone.id, milestone_title: milestone.title, subject: user)

      # TODO issue_timeline: we should migrate all milestone events to include the milestone_id so we can fetch all milestones in 1 query rather than 2
      # legacy milestone events (no id only title)
      milestone2 = create(:milestone, repository: repo, title: "Release Alpha")
      create(:issue_event, event: "milestoned", issue: issue, actor: other_user, milestone_title: milestone2.title, subject: user)
      create(:issue_event, event: "demilestoned", issue: issue, actor: other_user, milestone_title: milestone2.title, subject: user)

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        milestones
        milestones
        primary_avatars
        profiles
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "with references" do
    test "preloading does not execute unexpected queries" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)

      issue = create(:issue, repository: repo, title: "issue title", body: "issue body", user: user)
      commit = repo.commits.create({ message: "closes ##{issue.number}", committer: issue.user }, nil) { |_files| }

      event = create(:issue_event, event: "referenced", issue: issue, repository: repo, commit_id: commit.oid)

      assert_queries  %{
        business_user_accounts
        check_suites
        close_issue_references
        commit_comments
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events (closed_by_commit_oids preloading)
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        issues
        primary_avatars
        profiles
        repositories
        repositories
        repository_unlocks !dotcom
        sponsors check
        statuses
        user_blocked_check
        user_settings
        user_spammy_check
        users
        users
        users
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end

    test "preloading does not break on bad commits" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)

      issue = create(:issue, repository: repo, title: "issue title", body: "issue body", user: user)
      commit = repo.commits.create({ message: "closes ##{issue.number}", committer: issue.user }, nil) { |_files| }
      create(:issue_event, event: "referenced", issue: issue, repository: repo, commit_id: commit.oid)
      create(:issue_event, event: "referenced", issue: issue, repository: repo, commit_id: GitHub::NULL_OID)

      assert_queries %{
        business_user_accounts
        check_suites
        close_issue_references
        commit_comments
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events (closed_by_commit_oids preloading)
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        issues
        primary_avatars
        profiles
        repositories
        repositories
        repository_unlocks !dotcom
        sponsors check
        statuses
        user_blocked_check
        user_settings
        user_spammy_check
        users
        users
        users
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end

    test "preloading does not break if repositories_actions_checks cluster is not loading" do
      [ActiveRecord::StatementInvalid, ActiveRecord::ConnectionFailed].each do |error_class|
        CheckSuite.stubs(:connection).raises(error_class, "RAC is down!").once

        user = create(:user)
        repo = create(:repository, owner: user, from_example: :simple)

        issue = create(:issue, repository: repo, title: "issue title", body: "issue body", user: user)
        commit = repo.commits.create({ message: "closes ##{issue.number}", committer: issue.user }, nil) { |_files| }

        event = create(:issue_event, event: "referenced", issue: issue, repository: repo, commit_id: commit.oid)

        loader = Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter

        refute_nil loader

        preloaded_commit = loader.context.events.first.commit
        refute_nil preloaded_commit
        refute preloaded_commit.has_status_check_rollup?
      end
    end

    test "preloading does not execute unexpected queries with a bot" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)

      issue = create(:issue, repository: repo, title: "issue title", body: "issue body", user: user)

      5.times do
        other_issue = create(:issue, repository: repo, title: "issue title", body: "issue body", user: user)
        commit = repo.commits.create({ message: "closes ##{other_issue.number}", author: other_issue.user, committer: @bot }, nil) { |_files| }
        event = create(:issue_event, event: "referenced", issue: issue, repository: repo, commit_id: commit.oid)
      end

      assert_queries %{
        business_user_accounts
        check_suites
        close_issue_references
        commit_comments
        commit_contributions
        cross_references.load_timeline
        integrations
        integrations
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events (closed_by_commit_oids preloading)
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        issues
        permissions
        permissions
        primary_avatars
        profiles
        repositories
        repositories
        repository_unlocks !dotcom
        sponsors check
        statuses
        user_blocked_check
        user_settings
        user_spammy_check
        users
        users
        users
        users
        users
        users (bot / integration owner)
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end

    test "preloading with many commit references doesn't generate an N+1" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)

      issue = create(:issue, repository: repo, title: "issue title", body: "issue body", user: user)

      10.times do |i|
        commit = repo.commits.create({ message: "text " + i.to_s, committer: issue.user }, nil) { |_files| }
        create(:issue_event, event: "referenced", issue: issue, repository: repo, commit_id: commit.oid)
      end

      assert_queries %{
        business_user_accounts
        check_suites
        close_issue_references
        commit_comments
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events (closed_by_commit_oids preloading)
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        primary_avatars
        profiles
        repositories
        repository_unlocks !dotcom
        sponsors check
        statuses
        user_blocked_check
        user_settings
        user_spammy_check
        users
        users
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end

    test "preloading with many commit references from different users doesn't generate an N+1" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)

      issue = create(:issue, repository: repo, title: "issue title", body: "issue body", user: user)

      10.times do |i|
        commit = repo.commits.create({ message: "text " + i.to_s, committer: create(:user) }, nil) { |_files| }
        create(:issue_event, event: "referenced", issue: issue, repository: repo, commit_id: commit.oid)
      end

      assert_queries %{
        business_user_accounts
        check_suites
        close_issue_references
        commit_comments
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events (closed_by_commit_oids preloading)
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        primary_avatars
        profiles
        repositories
        repository_unlocks !dotcom
        sponsors check
        statuses
        user_blocked_check
        user_blocked_check (commit authors) !enterprise
        user_settings
        user_spammy_check
        users
        users
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end

    test "preloading with many commit references from different users that have already commented doesn't generate an N+1" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)

      issue = create(:issue, repository: repo, title: "issue title", body: "issue body", user: user)

      10.times do |i|
        new_user = create(:user)
        comment1 = issue.comments.create(user: new_user,  body: "comment")
        commit = repo.commits.create({ message: "text " + i.to_s, committer: new_user }, nil) { |_files| }
        create(:issue_event, event: "referenced", issue: issue, repository: repo, commit_id: commit.oid)
      end

      assert_queries %{
        abilities
        abilities
        business_user_accounts
        check_suites
        close_issue_references
        commit_comments
        commit_contributions
        cross_references.load_timeline
        issue_comment_edits
        issue_comment_reactions
        issue_comment_reactions
        issue_comments.load_timeline
        issue_comments.load_timeline
        issue_event_details
        issue_events (closed_by_commit_oids preloading)
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        primary_avatars
        profiles
        repositories
        repository_unlocks !dotcom
        sponsors check
        statuses
        user_blocked_check
        user_blocked_check
        user_blocked_check (commit authors) !enterprise
        user_settings
        user_spammy_check
        users
        users
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end

    test "preloading does not execute unexpected queries when commited from fork" do
      Spokesd.enable_spokesd
      user = create(:user)
      repo = create(:repository, owner: user)

      forker = create(:user, name: "forker")
      create(:primary_avatar, owner: forker, updater: forker)

      fork = create(:fork_repository, forker: forker, fork_repo: repo, from_example: :simple)

      issue = create(:issue, repository: repo, title: "Old Title", body: "issue body", user: user)
      commit = fork.commits.create({ message: "text", committer: issue.user }, nil) { |_files| }

      event = create(:issue_event,
        repository:  repo,
        issue:  issue,
        event:  "referenced",
        commit_id:  commit.oid,
        commit_repository_id: fork.id,
        created_at: DateTime.new(2021, 07, 28),
      )

      assert_queries %{
        business_user_accounts
        check_suites
        close_issue_references
        commit_comments
        commit_contributions
        cross_references.load_timeline
        internal_repositories
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events (closed_by_commit_oids preloading)
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        key_links
        primary_avatars
        profiles
        repositories
        repositories
        repositories (from IssueEvent::Loader)
        repository_networks
        repository_unlocks !dotcom
        sponsors check
        statuses
        user_blocked_check
        user_blocked_check (commit authors) !enterprise
        user_settings
        user_spammy_check
        users
        users
        users
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "with projects" do
    test "preloading does not execute unexpected queries" do
      user = create(:user)
      other_user = create(:user)

      repo1 = create(:repository, owner: user)
      repo2 = create(:repository, owner: user)

      issue = create(:issue, repository: repo1, user: user)

      project1 = create(:project, name: "project", owner: repo1)
      project2 = create(:project, name: "project", owner: repo2)
      project_card1 = create(:pending_project_card, project: project1)
      project_card2 = create(:pending_project_card, project: project2)
      project_card3 = create(:pending_project_card, project: project1)
      project_card4 = create(:pending_project_card, project: project2)

      create(:issue_event,
        event: "added_to_project",
        issue: issue,
        actor: user,
        subject: project1,
        card_id: project_card1.id,
        column_name: "column name")
      create(:issue_event,
        event: "moved_columns_in_project",
        issue: issue,
        actor: user,
        subject: project1,
        card_id: project_card3.id,
        previous_column_name: "foo",
        column_name: "bar")
      create(:issue_event,
        event: "removed_from_project",
        issue: issue,
        actor: user,
        subject: project1,
        card_id: project_card1.id,
        column_name: "bar")
      create(:issue_event,
        event: "converted_note_to_issue",
        issue: issue,
        actor: user,
        subject: project1,
        card_id: project_card1.id,
        column_name: "bar")
      create(:issue_event,
        event: "added_to_project",
        issue: issue,
        actor: user,
        subject: project2,
        card_id: project_card2.id,
        column_name: "column name")
      create(:issue_event,
        event: "moved_columns_in_project",
        issue: issue,
        actor: user,
        subject: project2,
        card_id: project_card4.id,
        column_name: "column name")

      # TODO issue_timeline: we could probably optimize/batch some of those queries
      # especially around those needed to check the project event visiblity
      assert_queries %{
        abilities (for project visibility check)
        abilities (for project visibility check)
        close_issue_references
        commit_contributions
        configuration_entries
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details (for project visibility check)
        issue_event_details
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        primary_avatars
        profiles
        project_cards
        projects
        projects
        projects
        repositories (for project visibility check)
        repositories (configurations for project visibility check)
        repositories
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new issue, repo1, user, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "with memex projects" do
    test "preloading does not execute unexpected queries" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)
      project = create(:memex_project, owner: user)

      2.times do |i|
        IssueEvent.create!(
          issue_id: issue.id,
          event: "added_to_project_v2",
          actor_id: user.id,
          source_id: "source_id_#{i}",
          project_id: project.id
        )
      end

      assert_queries %{
        business_user_accounts
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        memex_projects
        memex_projects
        primary_avatars
        profiles
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "with assignees" do
    test "preloading does not execute unexpected queries" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)
      assignee = create(:user)
      repo.add_member(assignee)
      create(:issue_event, event: "assigned", issue: issue, actor: assignee, subject: user)
      create(:issue_event, event: "unassigned", issue: issue, actor: assignee, subject: user)
      # Test polymorphic association with a nil value
      create(:issue_event, event: "assigned", issue: issue, actor: assignee, subject: nil)

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        primary_avatars
        profiles
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end

    test "preloading with multiple assigned events from different users does not introduce N+1 queries" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)

      20.times do
        subject = create(:user)
        assignee = create(:user)
        repo.add_member(subject)
        repo.add_member(assignee)
        create(:issue_event, event: "assigned", issue: issue, actor: assignee, subject: subject)
        create(:issue_event, event: "unassigned", issue: issue, actor: assignee, subject: subject)
      end

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        primary_avatars
        profiles
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "with cross references" do
    test "preloading does not execute unexpected queries" do
      user = create(:user)
      repo = create(:repository, owner: user, from_example: :simple)
      # issue to issue
      issue1 = create(:issue, repository: repo, user: user)
      issue2 = create(:issue, repository: repo, user: user)
      issue1.record_reference_from(issue2, user, Time.now)
      # pull to issue
      pull = PullRequest.create_for!(repo,
        user: user,
        base: "master",
        head: "cr-line-endings",
        title: "blah",
        body: "blah")
      issue1.record_reference_from(pull.issue, user, Time.now)

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        cross_references.load_timeline
        #{ GitHub.spamminess_check_enabled? ? "cross_references.load_timeline" : "" }
        internal_repositories
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        issues (from xrefs loading)
        primary_avatars
        profiles
        pull_requests
        repositories
        repositories
        #{ GitHub.spamminess_check_enabled? ? "repositories" : "" }
        sponsors check
        user_blocked_check
        user_settings
        users
      } do
        Platform::Security::RepositoryAccess.with_viewer(user) do
          Issue::ShowLoader.new issue1, repo, user, cap_filter: cap_authorizing_filter
        end
      end
    end
  end

  context "with rename" do
    test "preloading does not execute unexpected queries" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, title: "Old Title", body: "issue body", user: user)
      issue.title = "New Title"
      issue.save!

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers (is_transfer_in_progress?)
        issues
        primary_avatars
        profiles
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end

    test "preloading with multiple renamed events does not introduce N+1 queries" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, title: "Old Title", body: "issue body", user: user)

      20.times do
        issue.title = "New Title"
        issue.save!
      end

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers (is_transfer_in_progress?)
        issues
        primary_avatars
        profiles
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "with issue transfer event" do
    test "does not execute unexpected queries" do
      user = create(:user)
      repo = create(:repository, owner: user)
      new_repo = create(:repository, owner: repo.owner)
      old_issue = create(:issue, repository: repo, user: user)
      transfer = IssueTransfer.new(old_issue: old_issue, old_repository: old_issue.repository, new_repository: new_repo, actor: old_issue.repository.owner, reason: "Other")
      transfer.transfer!
      new_issue = transfer.new_issue

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.load_timeline
        issue_event_details
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers (is_transfer_in_progress?)
        issues
        primary_avatars
        profiles
        repositories
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new new_issue, new_repo, user, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "with user blocked event" do
    test "no unexpected queries" do
      GitHub::Experiment.any_instance.stubs(:enabled?).returns(false)
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, title: "Old Title", body: "issue body", user: user)

      10.times do
        blocked_user = create(:user)
        create(:issue_event,
          repository:  repo,
          issue:  issue,
          event:  "user_blocked",
          block_duration_days: 7,
          actor: user,
          subject: blocked_user,
        )
      end

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details (from IssueEvent::Loader)
        issue_event_details !enterprise
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues
        primary_avatars
        profiles
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users !enterprise
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "with pinned/unpinned" do
    test "does not execute unexpected queries" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)

      10.times do
        create(:issue_event, issue: issue, event: "pinned", actor: user)
        create(:issue_event, issue: issue, event: "unpinned", actor: user)
      end

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers (is_transfer_in_progress)
        issues
        primary_avatars
        profiles
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "with duplicates" do
    test "preloading does not execute unexpected queries" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue1 = create(:issue, repository: repo, user: user)

      10.times do
        # issue1 is being marked as duplicate of other issues
        other_issue = create(:issue, repository: repo, body: "issue body", user: user)
        create(:issue_event, event: "marked_as_duplicate", issue: issue1, subject: other_issue, actor: user)
        DuplicateIssue.find_or_build_for(issue: issue1, canonical_issue: other_issue, user: user).save
      end

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        duplicate_issues
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details (when loading timeline placeholders)
        issue_event_details (when preloading issue events)
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers
        issues (when loading timeline placeholders)
        issues (from IssueEvent::Loader)
        issues
        issues (from xrefs loading)
        primary_avatars
        profiles
        repositories (when loading timeline placeholders)
        repositories
        repositories (from IssueEvent::Loader)
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new issue1, repo, user, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "async_preload_issue" do
    test "preloading an issue does not execute unexpected queries" do
      viewer = create(:user)
      repo = create(:repository, owner: viewer)
      issue = create(:issue, repository: repo, user: viewer)
      loader = ShowLoaderNoAutoPreload.new issue, repo, viewer, cap_filter: cap_authorizing_filter
      _, queries = log_cleaned_queries do
        loader.preload_issue
      end

      compare_queries %{
        close_issue_references
        issue_transfers (is_transfer_in_progress?)
        repository_unlocks !dotcom
      }, queries
    end
  end

  context "async_preload_repository" do
    test "preloading an issue does not execute unexpected queries" do
      viewer = create(:user)
      repo = create(:repository, owner: viewer)
      issue = create(:issue, repository: repo, user: viewer)
      loader = ShowLoaderNoAutoPreload.new issue, repo, viewer
      result, queries = log_cleaned_queries do
        loader.preload_repository
      end

      # associations for user and issue should all be preloaded by this point
      compare_queries "", queries
    end
  end

  context "locked and unlocked issue events" do
    test "locking and unlocking does not execute unexpected queries" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, body: "issue body", user: user)
      issue.lock(user)
      create(:issue_event, event: "locked", issue: issue, actor: user, subject: user)

      issue.unlock(user)
      create(:issue_event, event: "unlocked", issue: issue, actor: user, subject: user)

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers (is_transfer_in_progress?)
        issues
        primary_avatars
        profiles
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end


    test "locking and unlocking by other user does not introduce N+1 queries" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, body: "issue body", user: user)

      20.times do
        other_user = create(:user)
        repo.add_member(other_user)
        issue.lock(other_user)
        create(:issue_event, event: "locked", issue: issue, actor: other_user, subject: other_user)
        issue.unlock(other_user)
        create(:issue_event, event: "unlocked", issue: issue, actor: other_user, subject: other_user)
      end

      assert_queries %{
        close_issue_references
        commit_contributions
        cross_references.load_timeline
        issue_comments.has_timeline_items?
        issue_comments.load_timeline
        issue_event_details
        issue_events.has_timeline_items?
        issue_events.load_timeline
        issue_events.load_timeline
        issue_reactions
        issue_transfers (is_transfer_in_progress?)
        issues
        primary_avatars
        profiles
        repository_unlocks !dotcom
        sponsors check
        user_blocked_check
        user_settings
        user_spammy_check
        users
      } do
        Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
      end
    end
  end

  context "issue transition events" do
    context "reopened issue" do
      test "reopened does not execute unexpected queries" do
        user = create(:user)
        repo = create(:repository, owner: user)
        issue = create(:issue, repository: repo, body: "issue body", user: user)
        issue.reopen!(user)
        create(:issue_event, event: "reopened", issue: issue, actor: user, subject: user)

        assert_queries %{
          close_issue_references
          commit_contributions
          cross_references.load_timeline
          issue_comments.has_timeline_items?
          issue_comments.load_timeline
          issue_event_details
          issue_events.has_timeline_items?
          issue_events.load_timeline
          issue_events.load_timeline
          issue_reactions
          issue_transfers (is_transfer_in_progress?)
          issues
          primary_avatars
          profiles
          sponsors check
          user_blocked_check
          user_settings
          user_spammy_check
          users
        } do
          Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
        end
      end

      test "reopened by other user does not execute unexpected queries" do
        user = create(:user)
        repo = create(:repository, owner: user)
        issue = create(:issue, repository: repo, body: "issue body", user: user)
        other_user = create(:user)
        repo.add_member(other_user)
        issue.reopen!(other_user)
        create(:issue_event, event: "reopened", issue: issue, actor: other_user, subject: other_user)

        assert_queries %{
          close_issue_references
          commit_contributions
          cross_references.load_timeline
          issue_comments.has_timeline_items?
          issue_comments.load_timeline
          issue_event_details
          issue_events.has_timeline_items?
          issue_events.load_timeline
          issue_events.load_timeline
          issue_reactions
          issue_transfers (is_transfer_in_progress?)
          issues
          primary_avatars
          profiles
          repository_unlocks !dotcom
          sponsors check
          user_blocked_check
          user_settings
          user_spammy_check
          users
        } do
          Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
        end
      end

      test "reopened by other user does not introduce N+1 queries" do
        user = create(:user)
        repo = create(:repository, owner: user)
        issue = create(:issue, repository: repo, body: "issue body", user: user)

        20.times do
          other_user = create(:user)
          issue.reopen!(other_user)
          repo.add_member(other_user)

          create(:issue_event, event: "reopened", issue: issue, actor: other_user, subject: other_user)
        end

        assert_queries %{
          close_issue_references
          commit_contributions
          cross_references.load_timeline
          issue_comments.has_timeline_items?
          issue_comments.load_timeline
          issue_event_details
          issue_events.has_timeline_items?
          issue_events.load_timeline
          issue_events.load_timeline
          issue_reactions
          issue_transfers (is_transfer_in_progress?)
          issues
          primary_avatars
          profiles
          repository_unlocks !dotcom
          sponsors check
          user_blocked_check
          user_settings
          user_spammy_check
          users
        } do
          Issue::ShowLoader.new issue, repo, user, cap_filter: cap_authorizing_filter
        end
      end
    end
  end

  context "preload_hierarchy" do
    test "loading calls preload command" do
      viewer = create(:user)
      repo = create(:repository, owner: viewer)
      issue = create(:issue, repository: repo, user: viewer)
      HierarchyCommands::Preload.any_instance.expects(:call).once
      issue.stubs(:hierarchy_raw).returns(IssuesGraph::Result.new(data: Struct.new(:tracking, :issue).new([], build_proto_issue)))
      Issue::ShowLoader.new issue, repo, viewer, cap_filter: cap_authorizing_filter
    end
  end

  context "load_timeline" do
    context "empty timeline" do
      test "loading does not execute unexpected queries" do
        viewer = create(:user)
        repo = create(:repository, owner: viewer)
        issue = create(:issue, repository: repo, user: viewer)
        loader = ShowLoaderNoAutoPreload.new issue, repo, viewer
        _, queries = log_cleaned_queries do
          loader.load_timeline
        end

        compare_queries %{
          cross_references.has_timeline_items?
          issue_comments.has_timeline_items?
          issue_events.has_timeline_items?
        }, queries
      end
    end

    context "with comments" do
      test "loading does not execute unexpected queries" do
        viewer = create(:user)
        repo = create(:repository, owner: viewer)
        issue = create(:issue, repository: repo, user: viewer)
        comment1 = issue.comments.create(user: create(:user), body: "comment 1")
        comment2 = issue.comments.create(user: create(:user), body: "comment 2")
        loader = ShowLoaderNoAutoPreload.new issue, repo, viewer
        result, queries = log_cleaned_queries do
          loader.load_timeline
        end

        # the following queries all originate from app/models/timeline/issue_timeline.async_placeholders
        compare_queries %{
          cross_references.load_timeline
          issue_comments.load_timeline
          issue_comments.load_timeline
          issue_events.load_timeline
          issues
        }, queries
      end
    end
  end
end

class ShowLoaderSiteAdminTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper
  include UnlockedRepositoryCheckTestHelper

  setup do
    @viewer = create(:staff_admin_user)
    clear_memoized_unlocked_repository_check
  end

  teardown do
    remove_as_employee(@viewer)
    @viewer.destroy!
  end

  context "async_preload_issue" do
    context "site admin" do
      test "preloading an issue does not execute unexpected queries" do
        repo = create(:repository, owner: @viewer)
        issue = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: repo, user: @viewer)
        loader = ShowLoaderNoAutoPreload.new issue, repo, @viewer, cap_filter: cap_authorizing_filter
        result, queries = log_cleaned_queries do
          loader.preload_issue
        end

        # 1 query to see if the user has unlocked the repo (only for enterprise)
        # 1 query for issue_transfers for is_transfer_in_progress?
        # 3 queries for report reason and last reported at for abuse_reports (only for site admins)
        # 1 query for closed_issue_references
        expected_count = GitHub.enterprise? ? 6 : 5

        assert_equal expected_count, queries.count
      end
    end
  end
end
