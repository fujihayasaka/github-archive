# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class NotifydIssueEventAdapterTest < GitHub::TestCase
    include NotifydTestHelper

    fixtures do
      @repo = create(:repository)
      @user = create(:user)
      @mentioned_user = create(:user)
      @repo.add_member(@user)
      @repo.add_member(@mentioned_user)

      @issue = create(:issue, user: @user, body: "@#{@mentioned_user} yeah?")
      @actor = create(:user)
      @event = create(:issue_event, issue: @issue, event: "assigned", subject: @user, actor: @actor)
    end

    setup do
      example_repo(:simple, @repo)
      @pr = PullRequest.create_for!(@repo,
        user: @user,
        base: "master",
        head: "cr-line-endings",
        title: "A title",
        body: "Hi @#{@mentioned_user}"
      )
      @pr_event = create(:issue_event, issue: @pr.issue, event: "assigned", subject: @user, actor: @actor)
    end

    context "issue events" do
      test "matches for issue events" do
        assert adapter(@event).matches?
      end

      test "does not match if repository is missing" do
        @event.repository.destroy
        @event.reload

        refute adapter(@event).matches?
      end

      test "does not match if repository owner is missing" do
        @event.repository.owner.delete
        @event.reload

        refute adapter(@event).matches?
      end

      test "does return notify feature flag value" do
        assert_equal GitHub.flipper[:notifyd_issue_event_notify], adapter(@event).notify_feature_flag
      end

      test "does return notification_id for issue events" do
        assert_equal adapter(@event).notification_id,
          "/#{@issue.repository.name_with_owner}/issues/#{@issue.number}#event-#{@event.id}"
      end

      test "repository_id" do
        assert_equal adapter(@event).repository_id, @event.repository_id
      end

      test "owner_id" do
        refute_nil adapter(@event).owner_id
        assert_equal adapter(@event).owner_id, @event.repository.owner.id
      end

      test "owner_id is nil when owner is missing" do
        @event.repository.owner.delete
        @event.reload

        assert_nil adapter(@event).owner_id
      end

      context "owner type" do
        test "for an organization is :organization" do
          org = create(:organization)
          repo = create(:repository, owner: org)
          issue = create(:issue, repository: repo)
          event = create(:issue_event, issue: issue, event: "assigned", subject: @user, actor: @actor)
          assert_equal adapter(event).owner_type, :organization
        end

        test "for a user is :user" do
          assert_equal adapter(@event).owner_type, :user
        end
      end

      test "authzd_attributes" do
        assert_equal adapter(@event).authzd_attributes, @issue.permissions_wrapper.serialized_subject_attributes
      end

      context "saml_enforcement" do
        test "for user without org" do
          assert_equal adapter(@event).saml_enforcement, { skip_enforcement: true }
        end

        test "for user with org" do
          org = create(:organization)
          repo = create(:repository, owner: org)
          issue = create(:issue, repository: repo)
          event = create(:issue_event, issue: issue, event: "assigned", subject: @user, actor: @actor)
          assert_equal adapter(event).saml_enforcement, { organization_id: org.id }
        end
      end

      context "mobile_layout" do
        test "without an actor" do
          @event.actor.delete
          @event.reload

          assert_nil adapter(
            @event,
            operation: Operations::IssueOperation::Assigned.serialize
          ).mobile_layout
        end

        test "with an actor, assigned operation gives a AssignedIssue render" do
          assert adapter(@event, { operation: "assigned", actor_id: @event.actor.id }).mobile_layout.title.include?("assigned you")
        end
      end

      test "email_layout" do
        refute_nil adapter(@event).email_layout
      end

      test "actor" do
        operations = %w(labeled unlabeled assigned reopened converted_to_discussion).each do |operation|
          actor = adapter(@event, { operation: operation, actor_id: @event.actor.id }).actor
          assert_equal @actor, actor
        end
      end

      context "related_topics" do
        test "returns added label for labeled operations" do
          label = create(:label, repository: @issue.repository)
          event = create(:issue_event, issue: @issue, event: "labeled", actor: @actor, label: label)

          assert_equal adapter(event, { operation: "labeled" }).related_topics,
          [{ type: "repository", value: @issue.repository.id.to_s },
            { type: "issue", value: @issue.id.to_s },
            { type: "label", value: label.id.to_s }]
        end

        test "returns removed label for unlabeled operations" do
          label = create(:label, repository: @issue.repository)
          event = create(:issue_event, issue: @issue, event: "unlabeled", actor: @actor, label: label)

          assert_equal adapter(event, { operation: "unlabeled" }).related_topics,
          [{ type: "repository", value: @issue.repository.id.to_s },
          { type: "issue", value: @issue.id.to_s },
          { type: "label", value: label.id.to_s }]
        end

        test "returns related_topics for other operations when" do
          label_one = create(:label, repository: @issue.repository)
          label_two = create(:label, repository: @issue.repository)
          @issue.add_labels([label_one, label_two])
          expected_related_topics = [
            { type: "repository", value: @issue.repository.id.to_s },
            { type: "issue", value: @issue.id.to_s },
            { type: "label", value: label_one.id.to_s },
            { type: "label", value: label_two.id.to_s },
          ]
          assert_equal adapter(@event, { operation: "assigned" }).related_topics, expected_related_topics
        end
      end

      context "attributes" do
        test "returns added label for labeled operations" do
          label_one = create(:label, repository: @issue.repository)
          label_two = create(:label, repository: @issue.repository)
          @issue.add_labels([label_one, label_two])
          label = create(:label, repository: @issue.repository)
          event = create(:issue_event, issue: @issue, event: "labeled", actor: @actor, label: label)

          assert_equal adapter(event, { operation: "labeled" }).attributes,
          [
            { name: "thread_participant_activity", value: "true" },
            { name: "thread_type", value: "issue" },
            { name: "has_label", value: label_one.id.to_s },
            { name: "has_label", value: label_two.id.to_s },
            { name: "added_label", value: label.id.to_s }
          ]
        end

        test "returns removed label for unlabeled operations" do
          label_one = create(:label, repository: @issue.repository)
          label_two = create(:label, repository: @issue.repository)
          @issue.add_labels([label_one, label_two])
          label = create(:label, repository: @issue.repository)
          event = create(:issue_event, issue: @issue, event: "unlabeled", actor: @actor, label: label)

          assert_equal adapter(event, { operation: "unlabeled", removed_label_id: label.id }).attributes,
          [
            { name: "thread_participant_activity", value: "true" },
            { name: "thread_type", value: "issue" },
            { name: "has_label", value: label_one.id.to_s },
            { name: "has_label", value: label_two.id.to_s },
            { name: "removed_label", value: label.id.to_s }
          ]
        end

        test "returns attributes for other operations when" do
          label_one = create(:label, repository: @issue.repository)
          label_two = create(:label, repository: @issue.repository)
          @issue.add_labels([label_one, label_two])
          expected_attributes = [
            { name: "thread_participant_activity", value: "true" },
            { name: "thread_type", value: "issue" },
            { name: "has_label", value: label_one.id.to_s },
            { name: "has_label", value: label_two.id.to_s },
            { name: "watch_activity", value: "true" },
          ]
          assert_equal adapter(@event, { operation: "assigned" }).attributes, expected_attributes
        end
      end

      context "explicit_recipients" do
        test "for closed, reopened, converted_to_discussion actions" do
          repo = create(:repository)
          owner = repo.owner
          assignee1 = create(:user)
          assignee2 = create(:user)
          commenter = create(:user)
          closer = create(:user)
          reopener = create(:user)
          repo.add_member(assignee1)
          repo.add_member(assignee2)
          repo.add_member(commenter)
          repo.add_member(closer)
          repo.add_member(reopener)
          issue = create(:issue, user: owner, repository: repo, assignees: [assignee1, assignee2])
          issue_comment = create(:issue_comment, user: commenter, repository: repo, issue: issue)
          issue.close(closer)
          issue.open(reopener)

          operations = %w[closed reopened converted_to_discussion].each do |operation|
            event = create(:issue_event, issue: issue, event: operation, subject: owner, actor: reopener)
            assert_same_explicit_recipients adapter(event, { operation: operation }).explicit_recipients,
              [{ reason: "author", users: [owner] },
              { reason: "comment", users: [commenter] },
              { reason: "assign", users: [assignee1, assignee2] },
              { reason: "state_change", users: [closer, reopener] }]
          end
        end

        test "for assigned" do
          repo = create(:repository)
          owner = repo.owner
          assignee = create(:user)
          repo.add_member(assignee)
          issue = create(:issue, user: owner, repository: repo, assignees: [assignee])
          event = create(:issue_event, issue: issue, event: "assigned", subject: owner, actor: assignee)
          assert_same_explicit_recipients adapter(event, { operation: "assigned", assignee_id: assignee.id }).explicit_recipients,
            [{ reason: "assign", users: [assignee] }]
        end

        test "for unknown action" do
          assert_same_explicit_recipients adapter(@event, { operation: "unknown" }).explicit_recipients, []
        end
      end

      context "feature switches" do
        test "disable subscribers for assigned" do
          assert_equal adapter(@event, { operation: "assigned" }).feature_switches, { notify_subscribers: false }
        end

        test "return default otherwise" do
          assert_equal adapter(@event, { operation: "closed" }).feature_switches, {}
        end
      end
    end

    context "pull request events" do
      test "matches for pull request events" do
        assert adapter(@pr_event).matches?
      end

      test "does not match if repository is missing" do
        @pr_event.repository.destroy
        @pr_event.reload

        refute adapter(@pr_event).matches?
      end

      test "does not match if repository owner is missing" do
        @pr_event.repository.owner.delete
        @pr_event.reload

        refute adapter(@pr_event).matches?
      end

      test "does return notification_id for pull_request events" do
        assert_equal adapter(@pr_event).notification_id,
          "/#{@pr.repository.name_with_owner}/pull/#{@pr.number}#event-#{@pr_event.id}"
      end

      test "repository_id" do
        assert_equal adapter(@pr_event).repository_id, @pr_event.repository_id
      end

      test "owner_id" do
        refute_nil adapter(@pr_event).owner_id
        assert_equal adapter(@pr_event).owner_id, @pr_event.repository.owner.id
      end

      test "owner_id is nil when owner is missing" do
        @pr_event.repository.owner.delete
        @pr_event.reload

        assert_nil adapter(@pr_event).owner_id
      end

      context "owner type" do
        test "for an organization is :organization" do
          org = create(:organization)
          org.add_member(@user, action: :admin)
          repo = create(:repository, owner: org, from_example: :simple)
          pr = PullRequest.create_for!(repo,
            user: @user,
            base: "master",
            head: "cr-line-endings",
            title: "A title",
            body: "Hi @#{@mentioned_user}"
          )
          pr_event = create(:issue_event, issue: pr.issue, event: "assigned", subject: @user, actor: @actor)
          assert_equal adapter(pr_event).owner_type, :organization
        end

        test "for a user is :user" do
          assert_equal adapter(@pr_event).owner_type, :user
        end
      end

      test "authzd_attributes" do
        assert_equal adapter(@pr_event).authzd_attributes, @pr.permissions_wrapper.serialized_subject_attributes
      end

      context "saml_enforcement" do
        test "for user without org" do
          assert_equal adapter(@pr_event).saml_enforcement, { skip_enforcement: true }
        end

        test "for user with org" do
          org = create(:organization)
          org.add_member(@user, action: :admin)
          repo = create(:repository, owner: org, from_example: :simple)
          pr = PullRequest.create_for!(repo,
            user: @user,
            base: "master",
            head: "cr-line-endings",
            title: "A title",
            body: "Hi @#{@mentioned_user}"
          )
          pr_event = create(:issue_event, issue: pr.issue, event: "assigned", subject: @user, actor: @actor)
          assert_equal adapter(pr_event).saml_enforcement, { organization_id: org.id }
        end
      end

      context "mobile_layout" do
        test "without an actor" do
          @pr_event.actor.delete
          @pr_event.reload

          assert_nil adapter(
            @pr_event,
            operation: Operations::PullRequestOperation::Assigned.serialize
          ).mobile_layout
        end

        test "with an actor" do
          refute_nil adapter(@pr_event, { actor_id: @pr_event.actor.id }).mobile_layout
        end

        test "with an actor, assigned operation gives a AssignedIssue render" do
          assert adapter(@pr_event, { operation: "assigned", actor_id: @pr_event.actor.id }).mobile_layout.title.include?("assigned you")
        end

        test "with an actor, review_requested operation gives a ReviewRequested render" do
          pr_event = create(:issue_event, issue: @pr.issue, event: "review_requested", subject: @user, actor: @actor)
          assert adapter(pr_event, { operation: "review_requested", actor_id: pr_event.actor.id }).mobile_layout.title.include?("requested your review")
        end
      end

      test "email_layout" do
        assert_nil adapter(@pr_event).email_layout
      end

      test "actor" do
        %w(assigned review_requested).each do |operation|
          actor = adapter(@pr_event, { operation: operation, actor_id: @pr_event.actor.id }).actor
          assert_equal @actor, actor
        end
      end

      test "related_topics" do
        %w(assigned review_requested).each do |operation|
          expected_related_topics = [
            { type: "repository", value: @pr.repository.id.to_s },
            { type: "issue", value: @pr.issue.id.to_s },
            { type: "pull_request", value: @pr.id.to_s },
          ]
          assert_equal adapter(@pr_event, { operation: operation }).related_topics, expected_related_topics
        end
      end

      test "attributes" do
        %w(assigned review_requested).each do |operation|
          expected_attributes = [
            { name: "thread_participant_activity", value: "true" },
            { name: "thread_type", value: "pull_request" },
            { name: "watch_activity", value: "true" },
          ]
          assert_equal adapter(@pr_event, { operation: operation }).attributes, expected_attributes
        end
      end

      context "explicit_recipients" do
        test "for assign" do
          assert_same_explicit_recipients adapter(@pr_event, { operation: "assigned", assignee_id: @pr_event.actor.id }).explicit_recipients,
            [{ reason: "assign", users: [@actor] }]
        end

        test "for user review request" do
          assert_same_explicit_recipients adapter(@pr_event, { operation: "review_requested", reviewer_id: @user.id }).explicit_recipients,
            [{ reason: "review_requested", users: [@user] }]
        end

        test "for team review request" do
          team = create(:team)
          pr_event = create(:issue_event, issue: @pr.issue, event: "review_requested", subject: team, actor: @actor)
          assert_same_explicit_recipients adapter(pr_event, { operation: "review_requested" }).explicit_recipients, []
        end

        test "for unknown action" do
          assert_same_explicit_recipients adapter(@pr_event, { operation: "unknown" }).explicit_recipients, []
        end
      end

      test "feature switches" do
        %w(assigned review_requested).each do |operation|
          assert_equal adapter(@pr_event, { operation: operation }).feature_switches, { notify_subscribers: false }
        end
      end
    end

    private

    def adapter(event, context = {})
      Notifyd::IssueEventAdapter.new(event, context)
    end
  end
end
