# typed: true
# frozen_string_literal: true

require "test_helper"

class CloseIssueReferenceTest < GitHub::TestCase
  include BackgroundDeletesTestHelpers

  context ".by_user scope" do
    test "includes only references where the close issue reference was created by the given user" do
      user = create(:user)
      repo = create(:repository, owner: user)
      other_user = create(:user)

      pull1 = create(:pull_request, :disable_disk_access, repository: repo, user: user)
      pull2 = create(:pull_request, :disable_disk_access, repository: repo, user: user, head_ref: "bloop")
      ref1 = create(:close_issue_reference, pull_request: pull1, actor_id: user.id)
      ref2 = create(:close_issue_reference, pull_request: pull2, actor_id: other_user.id)

      result = CloseIssueReference.by_user(user)

      assert_includes result, ref1
      refute_includes result, ref2
    end
  end

  context ".closes scope" do
    test "includes only references that close the given issue" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)
      ref1 = create(:close_issue_reference)
      ref2 = create(:close_issue_reference, issue: issue)

      result = CloseIssueReference.closes(issue)

      refute_includes result, ref1
      assert_includes result, ref2
    end
  end

  context ".possible_closing_references_for" do

    test "returns possible references, ordered by relevance and state" do
      user = create(:user)
      repo = create(:repository, owner: user)
      relevant_issue = create(:issue, repository: repo, user: user)
      make_searchable(relevant_issue)

      closed_issue = create(:issue, repository: repo, state: "closed")
      open_issue = create(:issue, repository: repo)

      pull = create(:pull_request, :disable_disk_access, repository: repo)

      result = CloseIssueReference.possible_closing_references_for(issue_or_pr: pull, viewer: user, limit: 10, repository: repo)
      assert_equal [relevant_issue, open_issue, closed_issue], result
    end

    test "excludes existing xrefed items" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)

      pull = create(:pull_request, :disable_disk_access, repository: repo, user: user)
      ref = create(:close_issue_reference, pull_request: pull, issue: issue)

      result = CloseIssueReference.possible_closing_references_for(issue_or_pr: pull, viewer: user, limit: 10, repository: repo)

      refute_includes result, issue
    end

    test "excludes issues from another repository" do
      user = create(:user)
      repo = create(:repository, owner: user)
      pull = create(:pull_request, :disable_disk_access, repository: repo)

      issue = create(:issue, user: user)

      result = CloseIssueReference.possible_closing_references_for(issue_or_pr: pull, viewer: user, limit: 10, repository: repo)

      refute_includes result, issue
    end

    test "includes issues by blocked users" do
      user = create(:user)
      repo = create(:repository, owner: user)
      pull = create(:pull_request, :disable_disk_access, repository: repo, user: user)

      issue = create(:issue, repository: repo)
      user.block issue.user

      result = CloseIssueReference.possible_closing_references_for(issue_or_pr: pull, viewer: user, limit: 10, repository: repo)
      assert_includes result, issue
    end

    if GitHub.spamminess_check_enabled?
      test "excludes spammy issues" do
        user = create(:user)
        repo = create(:repository, owner: user)
        pull = create(:pull_request, :disable_disk_access, repository: repo, user: user)

        spammy_issue = create(:spammy_issue, repository: repo)

        result = CloseIssueReference.possible_closing_references_for(issue_or_pr: pull, viewer: user, limit: 10, repository: repo)
        refute_includes result, spammy_issue
      end

    end

  end

  context ".synchronize_issue_and_pr_search_index" do

    test "updates search index on issue and pr when created" do
      user = create(:user)
      repo = create(:repository, owner: user)
      pull = create(:pull_request, :disable_disk_access, repository: repo, user: user)

      issue = create(:issue, repository: repo)

      Issue.any_instance.expects(:synchronize_search_index).once
      PullRequest.any_instance.expects(:synchronize_search_index).once

      create(:close_issue_reference, issue: issue, pull_request: pull)
    end

    test "updates search index on issue and pr when destroyed" do
      ref = create(:close_issue_reference)

      Issue.any_instance.expects(:synchronize_search_index).once
      PullRequest.any_instance.expects(:synchronize_search_index).once

      ref.destroy
    end

  end

  context "validations" do
    test "requires PR author" do
      ref = CloseIssueReference.new
      refute_predicate ref, :valid?
      assert_includes ref.errors[:pull_request_author], "can't be blank"
    end

    test "requires issue" do
      ref = CloseIssueReference.new
      refute_predicate ref, :valid?
      assert_includes ref.errors[:issue], "can't be blank"
    end

    test "requires issue repository" do
      ref = CloseIssueReference.new
      refute_predicate ref, :valid?
      assert_includes ref.errors[:issue_repository], "can't be blank"
    end

    test "sets issue repository to match issue" do
      issue = create(:issue)
      ref = CloseIssueReference.new(issue: issue)

      ref.valid?

      assert_equal issue.repository, ref.issue_repository
    end

    test "sets pull request author based on pull request" do
      pull = create(:pull_request, :disable_disk_access)
      ref = CloseIssueReference.new(pull_request: pull)

      ref.valid?

      assert_equal pull.user, ref.pull_request_author
    end

    test "requires pull request" do
      ref = CloseIssueReference.new
      refute_predicate ref, :valid?
      assert_includes ref.errors[:pull_request], "can't be blank"
    end

    # skipping for enterprise because we do not control who they want to be spammy
    test "does not set pull request author if pull request author is spammy", skip_enterprise: true do
      spammy_user = create :spammy_user
      pull = create(:pull_request, :disable_disk_access, user: spammy_user)
      ref = CloseIssueReference.new(pull_request: pull)

      refute_predicate ref, :valid?
      assert_nil ref.pull_request_author
    end

    test "requires a unique issue + pull request pair" do
      ref1 = create(:close_issue_reference)
      ref2 = build(:close_issue_reference, issue: ref1.issue, pull_request: ref1.pull_request)
      refute_predicate ref2, :valid?
      assert_includes ref2.errors[:issue_id], "has already been taken"
    end

    test "PR cannot reference its own issue" do
      pull1 = create(:pull_request, :disable_disk_access)
      ref2 = build(:close_issue_reference, issue: pull1.issue, pull_request: pull1)
      refute_predicate ref2, :valid?
      assert_includes ref2.errors[:issue_id], "must not be a pull request"
    end

    test "PR cannot reference a PR issue" do
      pull1 = create(:pull_request, :disable_disk_access)
      pull2 = create(:pull_request, :disable_disk_access)
      ref2 = build(:close_issue_reference, issue: pull2.issue, pull_request: pull1, actor_id: pull1.user.id)
      refute_predicate ref2, :valid?
      assert_includes ref2.errors[:issue_id], "must not be a pull request"
    end

    test "sets actor_id from context if not provided" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)

      pull = create(:pull_request, :disable_disk_access, repository: repo, user: user)

      GitHub.context.push(actor_id: user.id)

      assert_equal user.id, CloseIssueReference.create(pull_request: pull, issue: issue).actor_id
    end

    test "creates issue events on issue and pr when created manually" do
      user = create(:user)

      assert_difference "IssueEvent.count", 2 do
        ref = create(:manual_close_issue_reference, actor_id: user.id)
        pr = ref.pull_request
        pr_event = pr.reload.issue.events.connects.first
        assert_equal ref.issue, pr_event.subject
        assert_equal user, pr_event.actor

        issue_event = ref.issue.reload.events.connects.first
        assert_equal ref.pull_request.issue, issue_event.subject
        assert_equal user, issue_event.actor
      end
    end

    test "creates issue events on issue and pr when ref is destroyed" do
      user = create(:user)
      ref = create(:manual_close_issue_reference, actor_id: user.id)
      pr = ref.pull_request
      issue = ref.issue

      assert_difference "IssueEvent.count", 2 do
        GitHub.context.push(actor_id: user.id)
        ref.destroy
        pr_event = pr.reload.issue.events.disconnects.first
        assert_equal issue, pr_event.subject
        assert_equal user, pr_event.actor

        issue_event = issue.reload.events.disconnects.first
        assert_equal pr.issue, issue_event.subject
        assert_equal user, issue_event.actor
      end
    end

    test "creates issue event only on objects that still exist" do
      user = create(:user)
      ref = create(:manual_close_issue_reference, actor_id: user.id)
      pr = ref.pull_request

      # We don't create any events, because if the issue or PR no longer exists,
      # there is no meaningful concept of "connection" (or disconnection)
      assert_no_difference "IssueEvent.count", 1 do
        GitHub.context.push(actor_id: user.id)
        ref.issue.destroy
        ref.reload.destroy
      end
    end

    test "does not create events on both timelines when using a closing keyword" do
      user = create(:user)

      assert_no_difference "IssueEvent.count" do
        ref = create(:close_issue_reference, source: :xref, actor_id: user.id)
        assert_empty ref.pull_request.reload.issue.events.connects
        assert_empty ref.issue.reload.events.connects
      end
    end

    test "limits to MAX_MANUAL_REFERENCES per PR" do
      ref = create(:manual_close_issue_reference)
      issue = create(:issue)

      CloseIssueReference.stub_const(:MAX_MANUAL_REFERENCES, 1) do
        new_ref = issue.close_issue_references.build(pull_request: ref.pull_request, source: :manual)

        refute new_ref.valid?
        assert_equal "exceeds manual reference limit", new_ref.errors.messages[:pull_request_id].first
      end
    end

    test "limits to MAX_MANUAL_REFERENCES per issue" do
      ref = create(:manual_close_issue_reference)
      pull_request = create(:pull_request, :disable_disk_access)

      CloseIssueReference.stub_const(:MAX_MANUAL_REFERENCES, 1) do
        new_ref = pull_request.close_issue_references.build(issue: ref.issue, source: :manual)

        refute new_ref.valid?
        assert_equal "exceeds manual reference limit", new_ref.errors.messages[:issue_id].first
      end
    end

    test "does not permit users to create refs to repos they can't read" do
      user = create(:user)
      user_repo = create(:repository, owner: user)
      private_repo = create(:private_repository)

      issue = create(:issue, user: user, repository: user_repo)
      pr = create(:pull_request, :disable_disk_access, repository: private_repo, user: private_repo.owner)

      ref = CloseIssueReference.new(issue: issue, pull_request: pr, actor_id: user.id)
      refute_predicate ref, :valid?
      assert_match /access/, ref.errors.full_messages_for(:actor_id).join(",")
    end

    test "does not permit blocked users to ref issue from blockee" do
      author = create(:user)
      blocked_user = create(:user)
      author.block(blocked_user)

      repo = create(:repository)
      repo.add_member(author)
      repo.add_member(blocked_user)

      issue = create(:issue, user: author, repository: repo)
      pr = create(:pull_request, :disable_disk_access, user: blocked_user, repository: repo)

      ref = CloseIssueReference.new(issue: issue, pull_request: pr, actor_id: blocked_user.id)
      refute_predicate ref, :valid?
      assert_match /access/, ref.errors.full_messages_for(:actor_id).join(",")
    end

    test "does not permit blocked users to ref pull_request from blockee" do
      author = create(:user)
      blocked_user = create(:user)
      author.block(blocked_user)

      repo = create(:repository)
      repo.add_member(author)
      repo.add_member(blocked_user)

      issue = create(:issue, user: blocked_user, repository: repo)
      pr = create(:pull_request, :disable_disk_access, user: author, repository: repo)

      ref = CloseIssueReference.new(issue: issue, pull_request: pr, actor_id: blocked_user.id)
      refute_predicate ref, :valid?
      assert_match /access/, ref.errors.full_messages_for(:actor_id).join(",")
    end

    test "permits mannequins to create refs if they are part of the organization" do
      organization = create(:organization)
      mannequin = create(:mannequin, owner: organization)
      private_repo = create(:private_repository, owner: organization)

      importable_issue = create(:importable_issue, repository: private_repo, user: mannequin)
      importable_pr = create(:importable_pull_request, :disable_disk_access, repository: private_repo, user: mannequin)

      issue = Issue.find(importable_issue.id)
      pr = PullRequest.find(importable_pr.id)

      assert_equal mannequin.id, CloseIssueReference.create(issue: issue, pull_request: pr, actor_id: mannequin.id).actor_id
    end

    test "does not permit mannequins from outside the organization to create a ref" do
      organization = create(:organization)
      second_organization = create(:organization)
      mannequin = create(:mannequin, owner: second_organization)
      private_repo = create(:private_repository, owner: organization)

      importable_issue = create(:importable_issue, repository: private_repo, user: mannequin)
      importable_pr = create(:importable_pull_request, :disable_disk_access, repository: private_repo, user: mannequin)

      issue = Issue.find(importable_issue.id)
      pr = PullRequest.find(importable_pr.id)

      ref = CloseIssueReference.new(issue: issue, pull_request: pr, actor_id: mannequin.id)
      refute_predicate ref, :valid?
      assert_match /organization/, ref.errors.full_messages_for(:actor_id).join(",")
    end
  end

  context ".viewable_for" do
    context "with a linked public pull request " do
      test "returns the linked reference" do
        viewer = create :user
        issue = create(:issue)
        ref = create(:close_issue_reference, issue: issue)

        viewable_refs = CloseIssueReference.viewable_for(viewer: viewer, issue: issue)
        assert_includes viewable_refs, ref
      end
    end

    context "with a linked public issue" do
      test "returns the linked reference" do
        viewer = create :user
        pull = create(:pull_request, :disable_disk_access)
        ref = create(:close_issue_reference, pull_request: pull)

        viewable_refs = CloseIssueReference.viewable_for(viewer: viewer, issue: pull.issue)
        assert_includes viewable_refs, ref
      end
    end

    context "with a linked pull request that is readable and visible by viewer" do
      test "returns the linked reference" do
        viewer = create :user
        private_repo = create(:private_repository, owner: viewer)
        private_pr = create(:pull_request, :disable_disk_access, repository: private_repo, user: viewer)

        issue = create(:issue)
        ref = create(:close_issue_reference, issue: issue, pull_request: private_pr, actor_id: viewer.id)

        viewable_refs = CloseIssueReference.viewable_for(viewer: viewer, issue: issue)
        assert_includes viewable_refs, ref
      end
    end

    context "with a linked issue that is readable and visible by viewer" do
      test "returns the linked reference" do
        viewer = create :user
        private_repo = create(:private_repository, owner: viewer)
        private_issue = create(:issue, repository: private_repo)

        pull = create(:pull_request, :disable_disk_access)
        ref = create(:close_issue_reference, issue: private_issue, pull_request: pull, actor_id: viewer.id)

        viewable_refs = CloseIssueReference.viewable_for(viewer: viewer, issue: pull.issue)
        assert_includes viewable_refs, ref
      end
    end

    context "without a linked issue" do
      test "returns nothing if an issue with an associated xref has been deleted" do
        viewer = create :user
        pull = create(:pull_request, :disable_disk_access)
        issue = create(:issue)
        ref = create(:close_issue_reference, issue: issue, pull_request: pull, actor_id: viewer.id)

        viewable_refs = CloseIssueReference.viewable_for(viewer: viewer, issue: pull.issue)
        assert_includes viewable_refs, ref

        issue.delete

        viewable_refs = CloseIssueReference.viewable_for(viewer: viewer, issue: pull.issue)
        assert_empty viewable_refs
      end
    end

    context "without a linked pull request" do
      test "returns nothing if a pull request with an associated xref has been deleted" do
        viewer = create :user
        pull = create(:pull_request, :disable_disk_access)
        issue = create(:issue)
        ref = create(:close_issue_reference, issue: issue, pull_request: pull, actor_id: viewer.id)

        viewable_refs = CloseIssueReference.viewable_for(viewer: viewer, issue: issue)
        assert_includes viewable_refs, ref

        pull.delete

        viewable_refs = CloseIssueReference.viewable_for(viewer: viewer, issue: issue)
        assert_empty viewable_refs
      end
    end

    context "with a linked pull request that is not readable/visible by viewer" do
      test "does not return any close references" do
        viewer = create :user
        issue = create(:issue)

        private_user = create :user
        private_repo = create(:private_repository, owner: private_user)
        private_pr = create(:pull_request, :disable_disk_access, repository: private_repo, user: private_user)
        create(:close_issue_reference, issue: issue, pull_request: private_pr, actor_id: private_user.id)

        assert_empty CloseIssueReference.viewable_for(viewer: viewer, issue: issue)
      end
    end

    context "with a linked issue that is not readable/visible by viewer" do
      test "does not return any close references" do
        viewer = create :user
        pull = create(:pull_request, :disable_disk_access)

        private_user = create :user
        private_repo = create(:private_repository, owner: private_user)
        private_issue = create(:issue, repository: private_repo)

        create(:close_issue_reference, issue: private_issue, pull_request: pull, actor_id: private_user.id)

        assert_empty CloseIssueReference.viewable_for(viewer: viewer, issue: pull.issue)
      end
    end

    context "pull request user is spammy" do
      test "does not return any close references" do
        viewer = create :user
        issue = create(:issue)
        ref = create(:close_issue_reference, issue: issue)
        ref.pull_request.update_column(:user_hidden, true)

        assert_empty CloseIssueReference.viewable_for(viewer: viewer, issue: issue)
      end
    end

    context "issue user is spammy" do
      test "does not return any close references" do
        viewer = create :user
        pull = create(:pull_request, :disable_disk_access)
        ref = create(:close_issue_reference, pull_request: pull)
        ref.issue.update_column(:user_hidden, true)

        assert_empty CloseIssueReference.viewable_for(viewer: viewer, issue: pull.issue)
      end
    end

    context "viewer blocked pull request user" do
      test "returns any close references" do
        viewer = create :user
        blocked_user = create :user
        viewer.block(blocked_user)

        issue = create(:issue)
        blocked_user_pr = create(:pull_request, :disable_disk_access, user: blocked_user)
        ref = create(:close_issue_reference, issue: issue, pull_request: blocked_user_pr)

        viewable_refs = CloseIssueReference.viewable_for(viewer: viewer, issue: issue)
        assert_includes viewable_refs, ref
      end
    end

    context "viewer blocked issue user" do
      test "returns any close references" do
        viewer = create :user
        blocked_user = create :user
        viewer.block(blocked_user)

        blocked_user_issue = create(:issue, user: blocked_user)
        pull = create(:pull_request, :disable_disk_access)
        ref = create(:close_issue_reference, issue: blocked_user_issue, pull_request: pull)

        viewable_refs = CloseIssueReference.viewable_for(viewer: viewer, issue: pull.issue)
        assert_includes viewable_refs, ref
      end
    end
  end

  context "#notify_socket_subscribers" do
    test "should be triggered on create and trigger issue and pr updates" do
      Timecop.freeze do
        user = create(:user)
        repo = create(:repository, owner: user).reload
        issue = create(:issue, repository: repo, user: user).reload
        pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: user).reload

        GitHub.flipper[:pr_channel_event_payload_builder].disable(repo)

        frozen_time = Time.now.to_i

        xref_data = {
          timestamp: frozen_time,
          reason: "close issue references updated for issue ##{issue.id}",
          wait: issue.default_live_updates_wait,
        }

        issue_data = {
          timestamp: frozen_time,
          wait: issue.default_live_updates_wait,
          reason: "issue ##{issue.id} updated",
          gid: issue.global_relay_id,
        }

        pr_data = {
          timestamp: frozen_time,
          wait: pull_request.default_live_updates_wait,
          reason: "pull request ##{pull_request.id} updated",
          gid: pull_request.global_relay_id,
        }

        channel = GitHub::WebSocket::Channels.close_issue_references(issue)

        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, channel, xref_data).returns([]).once
        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, "issue:#{issue.id}", issue_data).returns([]).once
        GitHub::WebSocket.expects(:notify_pull_request_channel).with(pull_request, "pull_request:#{pull_request.id}", pr_data).returns([]).once

        create(:close_issue_reference, issue: issue, pull_request: pull_request)
      end
    end

    test "should be triggered on create and trigger issue and pr updates with event_updates including timeline_updated when FF enabled" do
      Timecop.freeze do
        user = create(:user)
        repo = create(:repository, owner: user).reload
        issue = create(:issue, repository: repo, user: user).reload
        pull_request = create(:pull_request, :disable_disk_access, repository: repo, user: user).reload

        GitHub.flipper[:pr_channel_event_payload_builder].enable(repo)

        frozen_time = Time.now.to_i

        xref_data = {
          timestamp: frozen_time,
          reason: "close issue references updated for issue ##{issue.id}",
          wait: issue.default_live_updates_wait,
        }

        issue_data = {
          timestamp: frozen_time,
          wait: issue.default_live_updates_wait,
          reason: "issue ##{issue.id} updated",
          gid: issue.global_relay_id,
        }

        event_updates = GitHub.flipper[:skip_full_sidebar_updates].enabled? ? { timeline_updated: true } : { sidebar_updated: true, timeline_updated: true }
        pr_data = {
          timestamp: frozen_time,
          wait: pull_request.default_live_updates_wait,
          reason: "pull request ##{pull_request.id} updated",
          gid: pull_request.global_relay_id,
          event_updates:,
        }

        channel = GitHub::WebSocket::Channels.close_issue_references(issue)

        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, channel, xref_data).returns([]).once
        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, "issue:#{issue.id}", issue_data).returns([]).once
        GitHub::WebSocket.expects(:notify_pull_request_channel).with(pull_request, "pull_request:#{pull_request.id}", pr_data).returns([]).once

        create(:close_issue_reference, issue: issue, pull_request: pull_request)
      end
    end

    test "should not be triggered on update" do
      Timecop.freeze do
        reference = create(:close_issue_reference)
        ref_issue = reference.issue
        new_issue = create(:issue, repository: ref_issue.repository, user: ref_issue.user)

        GitHub.flipper[:pr_channel_event_payload_builder].disable(ref_issue.repository)

        data = {
          timestamp: Time.now.to_i,
          wait: new_issue.default_live_updates_wait,
          reason: "close issue references updated for issue ##{new_issue.id}",
        }

        channel = GitHub::WebSocket::Channels.close_issue_references(new_issue)

        GitHub::WebSocket.stubs(:notify_issue_channel)
        GitHub::WebSocket.expects(:notify_issue_channel).with(new_issue, channel, data).never

        reference.update!(issue: new_issue)
      end
    end

    test "should not be triggered on update with event_updates including timeline_updated" do
      Timecop.freeze do
        reference = create(:close_issue_reference)
        ref_issue = reference.issue
        new_issue = create(:issue, repository: ref_issue.repository, user: ref_issue.user)

        GitHub.flipper[:pr_channel_event_payload_builder].enable(ref_issue.repository)

        data = {
          timestamp: Time.now.to_i,
          wait: new_issue.default_live_updates_wait,
          reason: "close issue references updated for issue ##{new_issue.id}",
          event_updates: { timeline_updated: true, sidebar_updated: true },
        }

        channel = GitHub::WebSocket::Channels.close_issue_references(new_issue)

        GitHub::WebSocket.stubs(:notify_issue_channel)
        GitHub::WebSocket.expects(:notify_issue_channel).with(new_issue, channel, data).never

        reference.update!(issue: new_issue)
      end
    end

    test "should be triggered on delete" do
      Timecop.freeze do
        reference = create(:close_issue_reference)
        issue = reference.issue.reload
        pull_request = reference.pull_request.reload

        GitHub.flipper[:pr_channel_event_payload_builder].disable(pull_request.repository)

        frozen_time = Time.now.to_i

        xref_data = {
          timestamp: frozen_time,
          wait: issue.default_live_updates_wait,
          reason: "close issue references updated for issue ##{issue.id}",
        }

        issue_data = {
          timestamp: frozen_time,
          wait: issue.default_live_updates_wait,
          reason: "issue ##{issue.id} updated",
          gid: issue.global_relay_id,
        }

        pr_data = {
          timestamp: frozen_time,
          wait: pull_request.default_live_updates_wait,
          reason: "pull request ##{pull_request.id} updated",
          gid: pull_request.global_relay_id,
        }

        channel = GitHub::WebSocket::Channels.close_issue_references(issue)

        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, channel, xref_data).returns([]).once
        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, "issue:#{issue.id}", issue_data).returns([]).once
        GitHub::WebSocket.expects(:notify_pull_request_channel).with(pull_request, "pull_request:#{pull_request.id}", pr_data).returns([]).once

        reference.destroy!
      end
    end

    test "should be triggered on delete with event_updates" do
      Timecop.freeze do
        reference = create(:close_issue_reference)
        issue = reference.issue.reload
        pull_request = reference.pull_request.reload

        GitHub.flipper[:pr_channel_event_payload_builder].enable(pull_request.repository)

        frozen_time = Time.now.to_i

        xref_data = {
          timestamp: frozen_time,
          wait: issue.default_live_updates_wait,
          reason: "close issue references updated for issue ##{issue.id}",
        }

        issue_data = {
          timestamp: frozen_time,
          wait: issue.default_live_updates_wait,
          reason: "issue ##{issue.id} updated",
          gid: issue.global_relay_id,
        }

        event_updates = GitHub.flipper[:skip_full_sidebar_updates].enabled? ? { timeline_updated: true } : { sidebar_updated: true, timeline_updated: true }
        pr_data = {
          timestamp: frozen_time,
          wait: pull_request.default_live_updates_wait,
          reason: "pull request ##{pull_request.id} updated",
          gid: pull_request.global_relay_id,
          event_updates:,
        }

        channel = GitHub::WebSocket::Channels.close_issue_references(issue)

        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, channel, xref_data).returns([]).once
        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, "issue:#{issue.id}", issue_data).returns([]).once
        GitHub::WebSocket.expects(:notify_pull_request_channel).with(pull_request, "pull_request:#{pull_request.id}", pr_data).returns([]).once

        reference.destroy!
      end
    end
  end

  test "is deleted with repository" do
    ref = create(:close_issue_reference)
    other_ref = create(:close_issue_reference)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = ref.issue_repository
      config.expect_destroyed = [ref]
      config.expect_not_destroyed = [other_ref]
    end
  end
end
