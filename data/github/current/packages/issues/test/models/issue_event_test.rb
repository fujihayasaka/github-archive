# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class IssueEventTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::PullRequestTestHelpers
  include GitHub::UTF8

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user, email: "rtomayko@gmail.com", login: "rtomayko")
    @mannequin = create(:mannequin, source_login: "user-placeholder")
    @ari     = create(:user, login: "ari", plan: "micro")
    @bwalsh  = create(:user, login: "bwalsh")
    @drama   = create(:user, login: "drama")
    @spammer = create(:user, spammy: true)
    @repo    = create(:private_repository, owner: @ari, name: "Kunze-Smith", from_example: :pull_request_fork)
    @repo.add_member @bwalsh, action: :write
    @repo.add_member @drama, action: :write

    @spammy_repo = create(:repository, owner: @spammer)

    @issue  = create(:issue, user: @bwalsh, repository: @repo)
    @issue2 = create(:issue, user: @bwalsh, repository: @repo)
    @spammy_issue = create(:issue, user: @spammer, repository: @spammy_repo)
    @spammer_issue = create(:issue, user: @spammer, repository: @repo)

    @org = create(:organization, login: "myorg")
    @org_repo = create(:repository, owner: @org, from_example: :pull_request_source)
    @org_repo.add_member @drama, action: :write
    @org_repo.add_member @ari, action: :write
    @org_repo.add_member @bwalsh, action: :write
    @org_repo.add_member @user, action: :write
    @team = create(:team, organization: @org, privacy: :closed, name: "myteam")
    @team.add_member @drama
    @team.add_member @ari
    @team.add_member @bwalsh
    @team.add_repository(@org_repo, :push)

    @org_issue = create(:issue, user: @ari, repository: @org_repo)
    @org_pull =
      create(:pull_request,
        repository:      @org_repo,
        base_repository: @org_repo,
        base_user:       @org_repo.owner,
        base_ref:        "master",
        head_repository: @org_repo,
        head_user:       @org_repo.owner,
        head_ref:        "master-forward-2",
        issue:           @org_issue,
        user:            @ari,
      )
    @org_issue.pull_request = @org_pull

    @label = create(:label, name: "bug", repository: @repo)
    @milestone = create :milestone, created_by: @ari, repository: @repo

    # Auto-close Memex project workflow setup
    @collaborator = create(:user).tap { |u| @org.add_member(u) }
    create(:collaborator, collaborator: @collaborator, repository: @org_repo)
    @outside_collaborator = create(:collaborator, repository: @org_repo)

    @project = create(:memex_project, owner: @org)
    MemexHelpers.setup_organization_wide_access_for_projects("project_reader")
    @project.grant_role(@outside_collaborator, "project_reader")

    @workflow = create(:memex_project_workflow, memex_project: @project)
    @workflow_action = @workflow.actions.first

    @pull =
      create(:pull_request,
        repository:      @repo,
        base_repository: @repo,
        base_user:       @ari,
        base_ref:        "master",
        head_repository: @repo,
        head_user:       @ari,
        head_ref:        "topic",
        issue:           @issue,
        user:            @bwalsh,
      )
    @issue.pull_request = @pull
    @issue.save!

    @issue_with_pull = @issue
    @issue_without_pull = @issue2

    message = <<~MSG
      multiple authored commit

      Co-authored-by: #{@user.name} <#{@user.email}>
    MSG
    @commit = @repo.commits.create({ author: @ari, committer: @bwalsh, message: message }, nil) do |_files|
    end
  end

  setup do
    refute_nil @pull.issue
  end

  context "#destroy" do
    test "deletes the associated issue_event_detail record" do
      event = create(:issue_event, actor: @ari, event: "marked_as_duplicate", issue: @issue2,
                subject: @issue)

      details = event.issue_event_detail
      assert details.persisted?

      event.destroy

      assert_nil IssueEventDetail.find_by(id: details.id)
    end

    test "deletes the associated issue_event_author record in the background" do
      event = create(:issue_event, actor: @ari, event: "mentioned", author: @user, issue: @issue2, subject: @issue)

      author = event.issue_event_author
      assert author.persisted?

      event.destroy

      assert IssueEventAuthor.exists?(author.id)

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob])

      assert_nil IssueEventAuthor.find_by(id: author.id)
    end
  end

  # TODO: Remove this when `issue_events.raw_data` has been removed (post data
  # transition).
  context "transitional state for serialized_attributes" do
    test "uses existing serialized_attributes for event details when present" do
      events = [
        IssueEvent.create!(issue: @issue, actor: @user, event: "subscribed"),
        IssueEvent.create!(issue: @issue, actor: @user, event: "milestoned"),
        IssueEvent.create!(issue: @issue, actor: @user, event: "demilestoned"),
      ]

      raw_data = {
        label_id: "123",
        label_name: "my-label",
        label_color: "blue",
        milestone_title: "Next Major Release",
        invalid_attr: "irrelevant",
      }

      events.each do |event|
        # Manually simulate existing production serialized attributes inside
        # the IssueEvent model by inserting raw_data
        # See: https://github.com/github/github/issues/56092
        IssueEvent.where(id: event.id).update_all(raw_data: raw_data)

        # Delete the issue_event_details row to simulate pre-transition production
        # where only the serialized attributes from the issue event model exist
        event.issue_event_detail.delete
        event.reload

        assert_equal 123, T.unsafe(event).label_id
        assert_equal "my-label", T.unsafe(event).label_name
        assert_equal "blue", T.unsafe(event).label_color
        assert_equal "Next Major Release", T.unsafe(event).milestone_title
      end
    end

    test "'raw_data' with non UTF-8 encoding doesn't throw an exception" do
      event = IssueEvent.create!(issue: @issue, actor: @user, event: "subscribed")

      non_unicode = "\xc2\xc2".b.force_encoding("ASCII-8BIT")
      as_unicode = utf8(non_unicode.b)

      raw_data = {
        label_id: 123,
        label_name: non_unicode
      }

      IssueEvent.where(id: event.id).update_all(raw_data: raw_data)
      event.issue_event_detail.delete
      event.reload

      assert_equal 123, T.unsafe(event).label_id
      assert_equal as_unicode, T.unsafe(event).label_name
    end
  end

  context "#async_can_be_undone_by?" do
    test "true for user who triggered the marked_as_duplicate event" do
      event = create(:issue_event, actor: @ari, event: "marked_as_duplicate", issue: @issue2,
                              subject: @issue)
      create(:duplicate_issue, actor: @ari, issue: @issue2, canonical_issue: @issue)

      assert event.async_can_be_undone_by?(@ari).sync
    end

    test "false when issue has been marked as not a duplicate" do
      event = create(:issue_event, actor: @ari, event: "marked_as_duplicate", issue: @issue2,
                              subject: @issue)
      create(:issue_event, actor: @ari, event: "unmarked_as_duplicate", issue: @issue2, subject: @issue)
      create(:duplicate_issue, actor: @ari, issue: @issue2, canonical_issue: @issue, duplicate: false)

      refute event.async_can_be_undone_by?(@ari).sync
    end

    test "true for user with write access to the repo of the marked_as_duplicate event" do
      event = create(:issue_event, event: "marked_as_duplicate", issue: @issue2, subject: @issue)
      create(:duplicate_issue, issue: @issue2, canonical_issue: @issue)

      assert event.async_can_be_undone_by?(@bwalsh).sync
    end

    test "false for user without write access to the repo of the marked_as_duplicate event" do
      user = create(:user)
      @repo.add_member(user, action: :read)
      event = create(:issue_event, event: "marked_as_duplicate", issue: @issue2, subject: @issue)
      create(:duplicate_issue, issue: @issue2, canonical_issue: @issue)

      refute event.async_can_be_undone_by?(user).sync
    end

    test "false for user not connected to the marked_as_duplicate event" do
      user = create(:user)
      event = create(:issue_event, event: "marked_as_duplicate", issue: @issue2, subject: @issue)
      create(:duplicate_issue, issue: @issue2, canonical_issue: @issue)

      refute event.async_can_be_undone_by?(user).sync
    end

    test "false for event other than marked_as_duplicate" do
      event = create(:issue_event, actor: @ari, event: "locked")

      refute event.async_can_be_undone_by?(@ari).sync
    end
  end

  context "#async_can_view_actor?" do
    test "true when actor is a bot" do
      bot_without_permissions = create(:integration, default_permissions: { "issues" => :read }).bot
      bot_with_permissions = create(:integration, default_permissions: { "issues" => :write }).bot
      org_event = create(:issue_event, actor: create(:integration).bot, repository: @org_repo, event: "locked", issue: @org_issue)
      repo_event = create(:issue_event, actor: create(:integration).bot, repository: @repo, event: "locked", issue: @issue)

      assert org_event.async_can_view_actor?(create(:user)).sync
      assert org_event.async_can_view_actor?(GitHub::NullUser.new).sync
      assert org_event.async_can_view_actor?(@drama).sync
      assert org_event.async_can_view_actor?(bot_without_permissions).sync
      assert org_event.async_can_view_actor?(bot_with_permissions).sync

      assert repo_event.async_can_view_actor?(create(:user)).sync
      assert repo_event.async_can_view_actor?(GitHub::NullUser.new).sync
      assert repo_event.async_can_view_actor?(@drama).sync
      assert repo_event.async_can_view_actor?(@ari).sync
      assert repo_event.async_can_view_actor?(bot_without_permissions).sync
      assert repo_event.async_can_view_actor?(bot_with_permissions).sync
    end

    test "true for non-protected events" do
      bot_without_permissions = create(:integration, default_permissions: { "issues" => :read }).bot
      bot_with_permissions = create(:integration, default_permissions: { "issues" => :write }).bot
      non_protected_event = "closed"
      refute IssueEvent::PROTECTED_EVENTS.include?(non_protected_event)
      org_event = create(:issue_event, repository: @org_repo, issue: @org_issue, event: non_protected_event)
      repo_event = create(:issue_event, repository: @repo, issue: @issue, event: non_protected_event)

      assert repo_event.async_can_view_actor?(create(:user)).sync
      assert repo_event.async_can_view_actor?(GitHub::NullUser.new).sync
      assert repo_event.async_can_view_actor?(@drama).sync
      assert repo_event.async_can_view_actor?(@ari).sync
      assert repo_event.async_can_view_actor?(bot_without_permissions).sync
      assert repo_event.async_can_view_actor?(bot_with_permissions).sync

      assert org_event.async_can_view_actor?(create(:user)).sync
      assert org_event.async_can_view_actor?(GitHub::NullUser.new).sync
      assert org_event.async_can_view_actor?(@drama).sync
      assert org_event.async_can_view_actor?(bot_without_permissions).sync
      assert org_event.async_can_view_actor?(bot_with_permissions).sync
    end

    test "determines if a user can view protected events" do
      bot_without_permissions = create(:integration, default_permissions: { "issues" => :read }).bot
      bot_without_permissions.integration.install_on(@ari, repositories: [@repo], installer: @ari, entry_point: :test_case)
      bot_without_permissions.async_load_installation_for(@repo).sync
      bot_with_permissions = create(:integration, default_permissions: { "issues" => :write }).bot
      bot_with_permissions.integration.install_on(@ari, repositories: [@repo], installer: @ari, entry_point: :test_case)
      bot_with_permissions.async_load_installation_for(@repo).sync

      protected_event = IssueEvent::PROTECTED_EVENTS.first
      org_event = create(:issue_event, repository: @org_repo, issue: @org_issue, event: protected_event)
      repo_event = create(:issue_event, repository: @repo, issue: @issue, event: protected_event)

      refute repo_event.async_can_view_actor?(create(:user)).sync
      refute repo_event.async_can_view_actor?(GitHub::NullUser.new).sync
      assert repo_event.async_can_view_actor?(@drama).sync
      assert repo_event.async_can_view_actor?(@ari).sync
      refute repo_event.async_can_view_actor?(bot_without_permissions).sync
      assert repo_event.async_can_view_actor?(bot_with_permissions).sync

      refute org_event.async_can_view_actor?(create(:user)).sync
      refute org_event.async_can_view_actor?(GitHub::NullUser.new).sync
      assert org_event.async_can_view_actor?(@drama).sync
      refute org_event.async_can_view_actor?(bot_without_permissions).sync
      assert org_event.async_can_view_actor?(bot_with_permissions).sync
    end
  end

  context "#async_milestone" do
    %w(milestoned demilestoned).each do |event_name|
      test "works with a valid milestone for #{event_name} event" do
        milestone = create(:milestone, repository: @repo, title: "morty")
        event = IssueEvent.create(repository: @repo, issue: @issue2, actor: @user, event: event_name, milestone_id: milestone.id, milestone_title: milestone.title)

        assert_equal milestone, event.async_milestone.sync
      end
    end

    test "works when a milestone's title has been changed" do
      milestone = create(:milestone, repository: @repo, title: "morty")
      event = IssueEvent.create(repository: @repo, issue: @issue2, actor: @user, event: "milestoned", milestone_id: milestone.id, milestone_title: milestone.title + " before change")

      assert_equal milestone, event.async_milestone.sync
    end

    test "works when a milestone_title was saved but a milestone_id wasn't" do
      milestone = create(:milestone, repository: @repo, title: "morty")
      event = IssueEvent.create(repository: @repo, issue: @issue2, actor: @user, event: "milestoned", milestone_title: milestone.title)

      assert_equal milestone, event.async_milestone.sync
    end

    test "is nil with a non milestoned event" do
      milestone = create(:milestone, repository: @repo, title: "morty")
      event = IssueEvent.create(repository: @repo, issue: @issue2, actor: @user, event: "assigned", milestone_id: milestone.id, milestone_title: milestone.title)

      assert_nil event.async_milestone.sync
    end

    test "is nil with a deleted milestone" do
      event = IssueEvent.create(repository: @repo, issue: @issue2, actor: @user, event: "milestoned", milestone_id: nil, milestone_title: "rick")
      assert_nil event.async_milestone.sync
    end
  end

  context "#milestone" do
    %w(milestoned demilestoned).each do |event_name|
      test "works with a valid milestone for #{event_name} event" do
        milestone = create(:milestone, repository: @repo, title: "morty")
        event = IssueEvent.create(repository: @repo, issue: @issue2, actor: @user, event: event_name, milestone_id: milestone.id, milestone_title: milestone.title)

        assert_equal milestone, event.milestone
      end
    end

    test "works when a milestone's title has been changed" do
      milestone = create(:milestone, repository: @repo, title: "morty")
      event = IssueEvent.create(repository: @repo, issue: @issue2, actor: @user, event: "milestoned", milestone_id: milestone.id, milestone_title: milestone.title + " before change")

      assert_equal milestone, event.milestone
    end

    test "works when a milestone_title was saved but a milestone_id wasn't" do
      milestone = create(:milestone, repository: @repo, title: "morty")
      event = IssueEvent.create(repository: @repo, issue: @issue2, actor: @user, event: "milestoned", milestone_title: milestone.title)

      assert_equal milestone, event.milestone
    end

    test "is nil with a non milestoned event" do
      milestone = create(:milestone, repository: @repo, title: "morty")
      event = IssueEvent.create(repository: @repo, issue: @issue2, actor: @user, event: "assigned", milestone_id: milestone.id, milestone_title: milestone.title)

      assert_nil event.milestone
    end

    test "is nil with a deleted milestone" do
      milestone = create(:milestone, repository: @repo, title: "morty")
      event = IssueEvent.create(repository: @repo, issue: @issue2, actor: @user, event: "milestoned", milestone_id: milestone.id, milestone_title: milestone.title)

      assert_equal milestone, event.milestone

      milestone.destroy!

      event.reload

      assert_nil event.milestone
    end
  end

  context "#async_authored_by_pusher" do
    test "true when author is pusher" do
      @issue.reference_from_commit(@ari, @commit.oid)
      event = @issue.events.last
      assert event.async_authored_by_pusher?.sync
    end

    test "true when committer is pusher" do
      @issue.reference_from_commit(@bwalsh, @commit.oid)
      event = @issue.events.last
      assert event.async_authored_by_pusher?.sync
    end

    test "true when co-author is pusher" do
      #look it up again now that the feature is enabled, so that trailers are parsed
      @commit = @repo.commits.find(@commit.oid)

      @issue.reference_from_commit(@user, @commit.oid)
      event = @issue.events.last
      assert event.async_authored_by_pusher?.sync
    end

    test "false when pusher is uninvolved with the creation of the commit" do
      @issue.reference_from_commit(create(:user), @commit.oid)
      event = @issue.events.last
      refute event.async_authored_by_pusher?.sync
    end
  end

  test "#async_title methods" do
    event = create(:issue_event, title_was: "old_title", title_is: "new_title")

    # reload to avoid any cached associations
    event.reload
    assert_equal "old_title", event.async_title_was.sync

    event.reload
    assert_equal "new_title", event.async_title_is.sync
  end

  context "commits methods" do
    test "returns the commit" do
      @issue.reference_from_commit(@ari, @commit.oid)
      event = @issue.events.reload.first { |ev| ev.event == "referenced" }
      commit = event.commit

      assert commit
      assert_equal @commit.oid, commit.oid
    end

    test "returns nil if the commit is not found" do
      @issue.reference_from_commit(@ari, GitHub::NULL_OID)
      event = @issue.events.reload.first { |ev| ev.event == "referenced" }
      commit = event.commit

      refute commit
    end

    test "specify a timeout when fetching git commit messages" do
      @issue.reference_from_commit(@ari, @commit.oid)
      event = @issue.events.reload.first { |ev| ev.event == "referenced" }

      Platform::Loaders::GitObject
        .expects(:load)
        .with(@issue.repository, @commit.oid, expected_type: :commit, timeout: 5)
        .returns(Concurrent::Promise.fulfill(nil))
        .once

      event.commit
    end
  end

  context ".create" do
    test "saves a issue event" do
      event = IssueEvent.create(issue: @issue, actor: @user, event: "subscribed")

      assert_predicate event, :valid?
      assert_predicate event, :persisted?
    end

    test "saves event details alongside an event" do
      event = IssueEvent.create(issue: @issue, actor: @user, event: "subscribed", label_name: "some-label")

      assert_predicate event, :valid?
      assert_predicate event, :persisted?

      assert_equal "some-label", T.unsafe(event).label_name
    end

    test "saves label details alongside an event" do
      new_label = create :label, name: "my-label"

      event = IssueEvent.create(issue: @issue, actor: @user, event: "subscribed", label: new_label)

      assert_predicate event, :valid?
      assert_predicate event, :persisted?

      assert_equal "my-label", T.unsafe(event).label_name
    end

    test "self assigning issue keeps rollup summary open" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)
      NotificationSummary.fetch_and_update!(repo, issue, issue)
      IssueEvent.create(issue: issue, event: "assigned", actor_id: user.id)
      rollup_summary = GitHub.newsies.web.find_rollup_summary_by_thread(repo, issue)
      assert_equal "open", rollup_summary.issue_state
    end

    test "self requesting review keeps rollup summary open" do
      user = create(:user)
      repo = create(:repository, owner: user)
      issue = create(:issue, repository: repo, user: user)
      NotificationSummary.fetch_and_update!(repo, issue, issue)
      IssueEvent.create(issue: issue, event: "review_requested", actor_id: user.id)
      rollup_summary = GitHub.newsies.web.find_rollup_summary_by_thread(repo, issue)
      assert_equal "open", rollup_summary.issue_state
    end

    test "converted_to_discusssion updates rollup summary" do
      repo = create(:repository, has_discussions: true)
      issue = create(:issue, repository: repo)
      discussion = create(:discussion, repository: repo)
      NotificationSummary.fetch_and_update!(repo, issue, issue)
      GitHub.newsies.web.expects(:update_rollup_summary).once

      perform_enqueued_jobs(only: [UpdateRollupSummaryStateJob]) do
        IssueEvent.create(
          issue: issue,
          event: "converted_to_discussion",
          actor_id: repo.owner.id,
          subject: discussion,
        )
      end
    end
  end

  context "#subject_must_be_valid" do
    test "cannot have any arbitrary subject" do
      event = IssueEvent.new(subject: @org)
      refute event.valid?
      expected = ["must be one of #{IssueEvent::VALID_SUBJECTS.join(', ')}"]
      assert_equal expected, event.errors[:subject]
    end

    test "allows a Bot as a subject" do
      bot = create(:integration).bot
      event = IssueEvent.new(subject: bot)
      event.valid?
      assert event.errors[:subject].empty?
    end

    test "allows a Team as a subject" do
      event = IssueEvent.new(subject: @team)
      event.valid?
      assert event.errors[:subject].empty?
    end

    test "allows a User as a subject" do
      event = IssueEvent.new(subject: @user)
      event.valid?
      assert event.errors[:subject].empty?
    end

    test "allows a Mannequin as a subject" do
      event = IssueEvent.new(subject: @mannequin)
      event.valid?
      assert event.errors[:subject].empty?
    end

    test "allows a Discussion as a subject" do
      event = IssueEvent.new(subject: create(:discussion))
      event.valid?
      assert_empty event.errors[:subject]
    end
  end

  context "#abbreviated_oid" do
    test "is nil for non-commit references" do
      @issue.close(@ari)
      assert_equal 1, @issue.events.size
      assert_nil @issue.events.last.abbreviated_oid
    end

    test "is the expected 7 digit hash for commit references" do
      @issue.reference_from_commit(@ari, GitHub::NULL_OID)
      assert_equal 1, @issue.events.size
      assert_equal "0000000", @issue.events.last.abbreviated_oid
    end
  end

  test "recording closed events" do
    @issue.close(@ari)
    assert_equal 1, @issue.events.size
    assert_equal %w[closed], @issue.events.map(&:event)

    event = @issue.events[0]
    assert_equal @ari, event.actor
    assert_equal "closed", event.event
    assert_equal @issue.repository, event.repository
  end

  test "recording closed when state reason is specified" do
    issue = create(:issue, user: @ari)
    issue.close(@ari)
    assert_equal 1, issue.events.size
    assert_equal %w[closed], issue.events.map(&:event)

    assert issue.close(@ari, attributes: { state_reason: :not_planned })
    assert_equal 2, issue.events.size
    assert_equal %w[closed closed], issue.events.map(&:event)
  end

  test "determining the closer" do
    assert_nil @issue.closed_by
    @issue.close(@bwalsh)
    assert_equal @bwalsh, @issue.closed_by
  end

  test "determining reopenability" do
    @issue.close(@bwalsh)
    assert @issue.reopenable_by?(@ari),    "owner should be able to reopen"
    assert @issue.reopenable_by?(@bwalsh), "closer should be able to reopen"
    refute @issue.reopenable_by?(@user),   "other users should not be able to reopen"
  end

  test "recording reopened events" do
    Spokesd.enable_spokesd

    @issue.close(@ari)
    @issue.open(@ari)
    assert_equal 2, @issue.events.size
    assert_equal %w[closed reopened], @issue.events.map(&:event)

    event = @issue.events.last
    assert_equal @ari, event.actor
    assert_equal "reopened", event.event
    assert_equal @issue.repository, event.repository
  end

  test "recording subscription on first comment" do
    assert !@issue.subscribed?(@ari)
    comment = create(:issue_comment, issue: @issue, user: @ari, body: "ship it")
    assert @issue.subscribed?(@ari)
  end

  test "recording unsubscription" do
    @issue.subscribe(@bwalsh, "manual")
    @issue.unsubscribe(@bwalsh)
    assert_equal 2, @issue.events.size

    event = @issue.events.order(:id).last
    assert_equal @bwalsh, event.actor
    assert_equal "unsubscribed", event.event
    assert_equal @issue.repository, event.repository
  end

  test "recording unsubscribe" do
    @issue.subscribe(@bwalsh, "manual")
    assert_equal true, @issue.unsubscribe(@bwalsh)

    event = @issue.events.last
    assert_equal @bwalsh, event.actor
    assert_equal "unsubscribed", event.event
    assert_equal @issue.repository, event.repository
  end

  test "recording mentions via comment" do
    assert_performed_with job: SubscribeAndNotifyJob do
      comment = create(:issue_comment, issue: @issue, user: @ari, body: "@bwalsh what do you think?")
      assert_equal ["bwalsh"], comment.mentioned_users.map(&:login)
      assert_equal %w(mentioned subscribed), @issue.events.reload.map(&:event)
    end
  end

  test "records team-mentions via comment" do
    assert !@org_issue.subscribed?(@drama)
    @team.add_repository @org_repo, :pull
    assert_performed_with job: SubscribeAndNotifyJob do
      comment = create(:issue_comment, issue: @org_issue, user: @ari, body: "@myorg/myteam what do you think?")
      assert_equal ["myteam"], comment.mentioned_teams.map(&:name)
      assert @org_issue.subscribed?(@drama)
    end
  end

  test "mentioned users exclude spammy mentions", spammy_only: true do
    assert_performed_with job: SubscribeAndNotifyJob do
      comment = create(:issue_comment, issue: @issue, user: @ari, body: "@bwalsh what do you think?")
      second_comment = create(:issue_comment, issue: @issue, user: @ari, body: "@drama what do you think?")

      # This represents a mention in the db that was there before we added the authors table
      # so it would be returned by the query since there's no associated author
      @issue.events.find_by(event: "mentioned", actor_id: @drama.id).issue_event_author.destroy!
      @ari.mark_as_spammy({ hard_flag: true })

      assert_equal [@drama.id], IssueEvent.mentioned_users(@issue).pluck(:actor_id)
    end
  end

  test "recording assignees" do
    @issue.repository.add_member @bwalsh

    @issue.assignee = @bwalsh
    @issue.save
    assert_equal 1, @issue.events.assigns.size

    event = @issue.events.first
    assert_equal @bwalsh, event.actor
    assert_equal "assigned", event.event
  end

  test "recording reviewers" do
    @pull.request_review_from(reviewers: [@drama], actor: @pull.user)
    assert_equal 1, @pull.events.review_requests.size

    event = @pull.events.first
    assert_equal @drama, event.subject
    assert_equal "review_requested", event.event
  end

  test "autosubscribing new reviewers" do
    refute @pull.subscribed?(@drama)
    perform_enqueued_jobs only: SubscribeAndNotifyJob do
      @pull.request_review_from(reviewers: [@drama], actor: @pull.user)
    end
    assert_equal 1, @pull.events.review_requests.size

    assert @pull.subscribed?(@drama)
  end

  test "autosubscribing all members of a team review request" do
    refute @org_pull.subscribed?(@drama)
    refute @org_pull.subscribed?(@bwalsh)
    perform_enqueued_jobs(only: SubscribeAndNotifyJob) do
      @org_pull.request_review_from(reviewers: [@team], actor: @org_pull.user)
    end
    assert_equal 1, @org_pull.events.review_requests.size

    assert @org_pull.subscribed?(@drama)
    assert_equal "review_requested", @org_pull.issue.subscription_status(@drama).reason
    assert @org_pull.subscribed?(@bwalsh)
    assert_equal "review_requested", @org_pull.issue.subscription_status(@bwalsh).reason
  end

  test "autosubscribing all members of a team and sub teams from a review request" do
    child_team = create(:team, organization: @org, name: "child-team", privacy: :closed, parent_team_id: @team.id)
    child_team.add_member(@user)

    refute @org_pull.subscribed?(@drama)
    refute @org_pull.subscribed?(@bwalsh)
    refute @org_pull.subscribed?(@user)
    perform_enqueued_jobs(only: SubscribeAndNotifyJob) do
      @org_pull.request_review_from(reviewers: [@team], actor: @org_pull.user)
    end
    assert_equal 1, @org_pull.events.review_requests.size

    assert @org_pull.subscribed?(@drama)
    assert_equal "review_requested", @org_pull.issue.subscription_status(@drama).reason
    assert @org_pull.subscribed?(@bwalsh)
    assert_equal "review_requested", @org_pull.issue.subscription_status(@bwalsh).reason
    assert @org_pull.subscribed?(@user)
    assert_equal "review_requested", @org_pull.issue.subscription_status(@user).reason
  end

  test "autosubscribing new assignees" do
    assert !@issue.subscribed?(@ari)
    perform_enqueued_jobs only: SubscribeAndNotifyJob do
      @issue.assignee = @ari
    end
    @issue.save
    assert @issue.subscribed?(@ari)
  end

  test "its thread for notifications is the issue" do
    @issue_without_pull.close
    event = @issue_without_pull.events.last

    assert_equal @issue_without_pull, event.notifications_thread
  end

  test "its thread for notifications is the issue if it is associated with a PR" do
    @issue_with_pull.close
    event = @issue_with_pull.events.last

    assert_equal @pull.issue, event.notifications_thread
  end

  test "avoiding duplicate reference events" do
    @issue.reference_from_commit(@ari, GitHub::NULL_OID)
    @issue.reference_from_commit(@bwalsh, GitHub::NULL_OID)
    assert_equal 1, @issue.events.reload.to_a.count { |ev| ev.event == "referenced" }
  end

  test "ignore references for commits matching a merge group entry" do
    fake_oid = "fake_oid"
    @issue.repository.expects(:merge_queue_commits_include?).with(fake_oid).returns(true)

    assert_no_difference "IssueEvent.count" do
      @issue.reference_from_commit(@ari, fake_oid)
    end
  end

  test "disallowing closing issue twice with the same commit" do
    Spokesd.enable_spokesd

    commit_id = GitHub::NULL_OID

    assert !@issue.already_closed_by_commit?(commit_id)
    @issue.close(@ari, attributes: { commit: { id: commit_id } })
    @issue.open(@ari)
    assert @issue.open?

    @issue = Issue.find(@issue.id)

    assert @issue.already_closed_by_commit?(commit_id)
    @issue.close(@ari, attributes: { commit: { id: commit_id } })
    assert @issue.open?
  end

  test "returns nil for commit when doesn't exist" do
    commit_id = GitHub::NULL_OID

    @issue.reference_from_commit(@ari, commit_id)
    assert_equal "referenced", @issue.events.reload.last.event
    assert_nil @issue.events.reload.last.commit
  end

  test "recording multiple mention events" do
    assert_performed_with job: SubscribeAndNotifyJob do
      comment = create(:issue_comment, issue: @issue, user: @ari, body: "@bwalsh, @rtomayko: ping")
      assert_equal %w[bwalsh rtomayko], comment.mentioned_users.map(&:login).sort
      assert_equal 2, @issue.events.reload.to_a.count { |ev| ev.event == "mentioned" }
    end
  end

  test "does not notify for 'non notifiable' events" do
    comment = create(:issue_comment, issue: @issue, user: @ari, body: "@bwalsh what do you think?")
    @issue.events.reload.each { |e| assert !e.send(:notify_for_event?) }
  end

  test "does notify for close events" do
    @issue.close(@ari)
    event = @issue.events.first
    assert event.send(:notify_for_event?)
  end

  context "#label=" do
    test "it sets label attributes" do
      event = IssueEvent.new
      T.unsafe(event).label = @label

      assert_equal @label.name,       T.unsafe(event).label_name
      assert_equal @label.color,      T.unsafe(event).label_color
      assert_equal @label.text_color, T.unsafe(event).label_text_color
    end
  end

  context "stratocaster events" do
    test "triggers a closed IssuesEvent when closing" do
      assert_enqueued_with job: ProcessEventJob, args: ["IssuesEvent", [:closed, @issue_without_pull.id, @ari.id]] do
        @issue_without_pull.close(@ari)
      end

      assert_enqueued_with job: ProcessEventJob, args: ["PullRequestEvent", [:closed, @pull.id, @ari.id]] do
        @issue_with_pull.close(@ari)
      end
    end

    test "triggers a reopened IssuesEvent when reopening" do
      Spokesd.enable_spokesd

      @issue_without_pull.close(@ari)
      assert_enqueued_with job: ProcessEventJob, args: ["IssuesEvent", [:reopened, @issue_without_pull.id, @ari.id]] do
        @issue_without_pull.open(@ari)
      end

      @issue_with_pull.close(@ari)
      assert_enqueued_with job: ProcessEventJob, args: ["PullRequestEvent", [:reopened, @pull.id, @ari.id]] do
        @issue_with_pull.open(@ari)
      end
    end

    test "triggers a (un)assigned IssuesEvent when assigning/unassigning users" do
      assert_enqueued_with job: ProcessEventJob, args: ["IssuesEvent", [:assigned, @issue_without_pull.id, @bwalsh.id, { assignee_id: @ari.id }]] do
        @issue_without_pull.update! assignee: @ari
      end

      assert_enqueued_with job: ProcessEventJob, args: ["IssuesEvent", [:unassigned, @issue_without_pull.id, @bwalsh.id, { assignee_id: @ari.id }]] do
        @issue_without_pull.update! assignee: nil
      end

      assert_enqueued_with job: ProcessEventJob, args: ["PullRequestEvent", [:assigned, @pull.id, @bwalsh.id, { assignee_id: @ari.id }]] do
        @issue_with_pull.update! assignee: @ari
      end

      assert_enqueued_with job: ProcessEventJob, args: ["PullRequestEvent", [:unassigned, @pull.id, @bwalsh.id, { assignee_id: @ari.id }]] do
        @issue_with_pull.update! assignee: nil
      end
    end

    test "triggers a review_requested/review_request_removed IssuesEvent when (un)requesting users" do
      assert_enqueued_with job: ProcessEventJob, args: ["PullRequestEvent", [:review_requested, @pull.id, @pull.user.id, { subject_id: @ari.id, subject_type: "User" }]] do
        @pull.request_review_from(reviewers: [@ari], actor: @pull.user)
      end

      assert_enqueued_with job: ProcessEventJob, args: ["PullRequestEvent", [:review_request_removed, @pull.id, @pull.user.id, { subject_id: @ari.id, subject_type: "User" }]] do
        @pull.request_review_from(reviewers: [], actor: @pull.user)
      end
    end

    test "triggers a review_requested/review_request_removed IssuesEvent when (un)requesting teams" do
      assert_enqueued_with job: ProcessEventJob, args: ["PullRequestEvent", [:review_requested, @org_pull.id, @org_pull.user.id, { subject_id: @team.id, subject_type: "Team" }]] do
        @org_pull.request_review_from(reviewers: [@team], actor: @org_pull.user)
      end

      assert_enqueued_with job: ProcessEventJob, args: ["PullRequestEvent", [:review_request_removed, @org_pull.id, @org_pull.user.id, { subject_id: @team.id, subject_type: "Team" }]] do
        @org_pull.request_review_from(reviewers: [], actor: @org_pull.user)
      end
    end

    test "triggers a (un)labeled IssuesEvent when labeling/unlabeling" do
      assert_enqueued_with job: ProcessEventJob, args: ["IssuesEvent", [:labeled, @issue_without_pull.id, @bwalsh.id, { label_id: @label.id }]] do
        @issue_without_pull.add_labels @label
      end

      assert_enqueued_with job: ProcessEventJob, args: ["IssuesEvent", [:unlabeled, @issue_without_pull.id, @bwalsh.id, { label_id: @label.id }]] do
        @issue_without_pull.delete_labels @label
      end

      assert_enqueued_with job: ProcessEventJob, args: ["PullRequestEvent", [:labeled, @pull.id, @bwalsh.id, { label_id: @label.id }]] do
        @issue_with_pull.add_labels @label
      end

      assert_enqueued_with job: ProcessEventJob, args: ["PullRequestEvent", [:unlabeled, @pull.id, @bwalsh.id, { label_id: @label.id }]] do
        @issue_with_pull.delete_labels @label
      end
    end
  end

  context "event instrumentation" do
    general_events = IssueEvent::VALID_EVENTS - %w(labeled unlabeled milestoned demilestoned assigned unassigned review_requested review_request_removed)
    general_events.each do |event_name|
      test "instruments an 'issue.event.#{event_name}' event when a #{event_name} IssueEvent is created" do
        events = subscribe "issue.event.#{event_name}"
        issue_event = create :issue_event, issue: @issue, event: event_name
        expected_payload = {
          issue_id:        @issue.id,
          event:           event_name,
          actor:           issue_event.actor.login,
          actor_id:        issue_event.actor_id,
          spammy:          false,
          pull_request_id: @issue.pull_request.id,
          pull_request_url: @issue.pull_request.permalink,
          pull_request_title: @issue.pull_request.title,
          allowed:         true,
          repository_id:   @issue.repository_id,
          organization_id: @issue.repository.organization_id,
        }

        assert event = events.pop, "expected an instrumentation event for #{event_name}"
        assert_subset_hash expected_payload, event.payload
      end
    end

    test "sets the non-spammy check to false if a spammer acting on a non-owned repo" do
      events = subscribe "issue.event.labeled"
      expected_payload = {
        issue_id: @spammer_issue.id,
        label_id: @label.id,
        event:    "labeled",
        actor:    @spammer.login,
        actor_id: @spammer.id,
        spammy:   true,
        allowed:  false,
        repository_id: @spammer_issue.repository_id,
        organization_id: @spammer_issue.repository.organization_id,
      }

      @spammer_issue.add_labels @label

      assert event = events.pop, "expected an instrumentation event"
      assert_subset_hash expected_payload, event.payload
    end unless GitHub.enterprise?

    test "sets the non-spammy check to true if a spammer acting on an owned repo" do
      events = subscribe "issue.event.labeled"
      label = create :label, repository: @spammy_issue.repository
      expected_payload = {
        issue_id:        @spammy_issue.id,
        label_id:        label.id,
        event:           "labeled",
        actor:           @spammer.login,
        actor_id:        @spammer.id,
        spammy:          true,
        allowed:         true,
        repository_id:   @spammy_issue.repository_id,
        organization_id: @spammy_issue.repository.organization_id,
      }

      @spammy_issue.add_labels label

      assert event = events.pop, "expected an instrumentation event"
      assert_subset_hash expected_payload, event.payload
    end unless GitHub.enterprise?

    test "does not include pull_request_id in payload if issue is not for pull request" do
      refute @issue_without_pull.pull_request?

      events = subscribe "issue.event.labeled"
      expected_payload = {
        issue_id:        @issue_without_pull.id,
        label_id:        @label.id,
        event:           "labeled",
        actor:           @issue_without_pull.user.login,
        actor_id:        @issue_without_pull.user_id,
        spammy:          false,
        allowed:         true,
        repository_id:   @issue_without_pull.repository_id,
        organization_id: @issue_without_pull.repository.organization_id,
        business:        nil
      }

      @issue_without_pull.add_labels @label

      assert event = events.pop, "expected an instrumentation event"
      assert_equal expected_payload, event.payload
    end

    test "includes the label in instrumentation for labeled events" do
      events = subscribe "issue.event.labeled"
      expected_payload = {
        issue_id:        @issue.id,
        label_id:        @label.id,
        event:           "labeled",
        actor:           @issue.user.login,
        actor_id:        @issue.user_id,
        spammy:          false,
        pull_request_id: @issue.pull_request.id,
        pull_request_url: @issue.pull_request.permalink,
        pull_request_title: @issue.pull_request.title,
        allowed:         true,
        repository_id:   @issue.repository_id,
        organization_id: @issue.repository.organization_id,
      }

      @issue.add_labels @label

      assert event = events.pop, "expected an instrumentation event"
      assert_subset_hash expected_payload, event.payload
    end

    test "includes the label in instrumentation for unlabeled events" do
      @issue.add_labels @label

      events = subscribe "issue.event.unlabeled"
      expected_payload = {
        issue_id:        @issue.id,
        label_id:        @label.id,
        event:           "unlabeled",
        actor:           @issue.user.login,
        actor_id:        @issue.user_id,
        spammy:          false,
        pull_request_id: @issue.pull_request.id,
        pull_request_url: @issue.pull_request.permalink,
        pull_request_title: @issue.pull_request.title,
        allowed:         true,
        repository_id:   @issue.repository_id,
        organization_id: @issue.repository.organization_id,
      }

      @issue.delete_labels @label

      assert event = events.pop, "expected an instrumentation event"
      assert_subset_hash expected_payload, event.payload
    end

    test "includes the milestone in instrumentation for milestoned events" do
      events = subscribe "issue.event.milestoned"
      expected_payload = {
        issue_id:        @issue.id,
        milestone_id:    @milestone.id,
        event:           "milestoned",
        actor:           @issue.user.login,
        actor_id:        @issue.user_id,
        spammy:          false,
        pull_request_id: @issue.pull_request.id,
        pull_request_url: @issue.pull_request.permalink,
        pull_request_title: @issue.pull_request.title,
        allowed:         true,
        repository_id:   @issue.repository_id,
        organization_id: @issue.repository.organization_id,
      }

      @issue.milestone = @milestone
      @issue.save!

      assert event = events.pop, "expected an instrumentation event"
      assert_subset_hash expected_payload, event.payload
    end

    test "includes the milestone in instrumentation for demilestoned events" do
      @issue.milestone = @milestone
      @issue.save!

      events = subscribe "issue.event.demilestoned"
      expected_payload = {
        issue_id:        @issue.id,
        milestone_id:    @milestone.id,
        event:           "demilestoned",
        actor:           @issue.user.login,
        actor_id:        @issue.user_id,
        spammy:          false,
        pull_request_id: @issue.pull_request.id,
        pull_request_url: @issue.pull_request.permalink,
        pull_request_title: @issue.pull_request.title,
        allowed:         true,
        repository_id:   @issue.repository_id,
        organization_id: @issue.repository.organization_id,
      }

      @issue.milestone = nil
      @issue.save!

      assert event = events.pop, "expected an instrumentation event"
      assert_subset_hash expected_payload, event.payload
    end

    test "includes the assignee in instrumentation for assigned events" do
      events = subscribe "issue.event.assigned"
      expected_payload = {
        issue_id:        @issue.id,
        event:           "assigned",
        actor:           @ari.login,
        actor_id:        @ari.id,
        spammy:          false,
        assignee:        @ari.login,
        assignee_id:     @ari.id,
        subject:         @issue.user.login,
        subject_id:      @issue.user_id,
        subject_type:    "User",
        pull_request_id: @issue.pull_request.id,
        pull_request_url: @issue.pull_request.permalink,
        pull_request_title: @issue.pull_request.title,
        allowed:         true,
        repository_id:   @issue.repository_id,
        organization_id: @issue.repository.organization_id,
      }

      @issue.update! assignee: @ari

      assert event = events.pop, "expected an instrumentation event"
      assert_subset_hash expected_payload, event.payload
    end

    test "includes the assignee in instrumentation for unassigned events" do
      @issue.update! assignee: @ari

      events = subscribe "issue.event.unassigned"
      expected_payload = {
        issue_id:        @issue.id,
        event:           "unassigned",
        actor:           @ari.login,
        actor_id:        @ari.id,
        spammy:          false,
        assignee:        @ari.login,
        assignee_id:     @ari.id,
        subject:         @issue.user.login,
        subject_id:      @issue.user_id,
        subject_type:    "User",
        pull_request_id: @issue.pull_request.id,
        pull_request_url: @issue.pull_request.permalink,
        pull_request_title: @issue.pull_request.title,
        allowed:         true,
        repository_id:   @issue.repository_id,
        organization_id: @issue.repository.organization_id,
      }

      @issue.update! assignee: nil

      assert event = events.pop, "expected an instrumentation event"
      assert_subset_hash expected_payload, event.payload
    end

    test "labeled events preload repository association" do
      events = subscribe "issue.event.labeled"
      @labels = create_list(:label, 5, repository: @issue.repository)

      query_count = TestEnv.test_all_features? ? 15 : 41 # repos_domain_label
      assert_query_count_per_table({ repositories: query_count }) do
        @issue.add_labels @labels
      end

      assert event = events.pop, "expected an instrumentation event"
    end
  end

  test "scopes" do
    pr = make_pull_request
    issue = pr.issue
    remote_repo = create(:repository)
    ephemeral_repo = create(:repository)
    ephemeral_repo.remove(ephemeral_repo.owner, synchronous: true)

    closed = create(:issue_event, event: "closed", commit_id: "abcd")
    reopened = create(:issue_event, event: "reopened")
    merged = create(:issue_event, event: "merged")
    referenced = create(:issue_event, event: "referenced")
    valid_commit_ref = create(:issue_event, event: "referenced", commit_repository_id: remote_repo.id)
    orphaned_commit_ref = create(:issue_event, event: "referenced", commit_repository_id: ephemeral_repo.id)
    mentioned = create(:issue_event, event: "mentioned", issue: issue, actor: issue.user)
    subscribed = create(:issue_event, event: "subscribed", issue: issue, actor: issue.user)
    mentioned2 = create(:issue_event, event: "mentioned")
    assigned = create(:issue_event, event: "assigned")
    unassigned = create(:issue_event, event: "unassigned")
    review_requested = create(:issue_event, event: "review_requested")
    review_request_removed = create(:issue_event, event: "review_request_removed")
    labeled = create(:issue_event, event: "labeled")
    unlabeled = create(:issue_event, event: "unlabeled")
    milestoned = create(:issue_event, event: "milestoned")
    demilestoned = create(:issue_event, event: "demilestoned")
    renamed = create(:issue_event, event: "renamed")
    locked = create(:issue_event, event: "locked")
    unlocked = create(:issue_event, event: "unlocked")
    deployed = create(:issue_event, event: "deployed")
    deployment_environment_changed = create(:issue_event, event: "deployment_environment_changed")
    head_ref_deleted = create(:issue_event, event: "head_ref_deleted")
    head_ref_restored = create(:issue_event, event: "head_ref_restored")
    base_ref_force_pushed = create(:issue_event, event: "base_ref_force_pushed")
    head_ref_force_pushed = create(:issue_event, event: "head_ref_force_pushed")
    marked_as_duplicate = create(:issue_event, event: "marked_as_duplicate")
    unmarked_as_duplicate = create(:issue_event, event: "unmarked_as_duplicate")
    participatory = [closed, reopened, merged, referenced, assigned, unassigned, labeled, unlabeled, milestoned, demilestoned, deployed, deployment_environment_changed]

    assert_equal [closed], IssueEvent.closes
    assert_equal [reopened], IssueEvent.reopens
    assert_equal [merged], IssueEvent.merges
    assert_equal [assigned], IssueEvent.assigns
    assert_equal [unassigned], IssueEvent.unassigns
    assert_equal [review_requested], IssueEvent.review_requests
    assert_equal [review_request_removed], IssueEvent.review_request_removes
    assert_equal [mentioned, mentioned2], IssueEvent.mentions
    assert_equal [referenced, valid_commit_ref, orphaned_commit_ref], IssueEvent.referenced
    assert_equal [labeled], IssueEvent.labels
    assert_equal [unlabeled], IssueEvent.unlabels
    assert_equal [milestoned], IssueEvent.milestones
    assert_equal [demilestoned], IssueEvent.demilestones
    assert_equal [renamed], IssueEvent.renames
    assert_equal [locked], IssueEvent.locks
    assert_equal [unlocked], IssueEvent.unlocks
    assert_equal [deployed], IssueEvent.deployments
    assert_equal [deployment_environment_changed], IssueEvent.deployment_environment_changes
    assert_equal [marked_as_duplicate], IssueEvent.marked_as_duplicates
    assert_equal [unmarked_as_duplicate], IssueEvent.unmarked_as_duplicates
    assert_equal [closed, reopened], IssueEvent.closes_and_reopens
    assert_equal [head_ref_deleted, head_ref_restored], IssueEvent.head_ref
    assert_equal [base_ref_force_pushed, head_ref_force_pushed], IssueEvent.force_pushes
    assert_includes IssueEvent.issues, locked
    refute_includes IssueEvent.pull_requests, locked
    assert_equal [mentioned, subscribed], IssueEvent.pull_requests
    assert_equal [closed], IssueEvent.reference_types
    assert_equal 1, IssueEvent.mentioned_users(issue).size
    assert_equal issue.user.id, T.must(IssueEvent.mentioned_users(issue).first).actor_id
    assert_same_elements participatory, IssueEvent.participatory
  end

  test "high mentioned event returns none scope" do
    issue_with_two = create(:issue)
    create(:issue_event, event: "mentioned", issue: issue_with_two, actor: issue_with_two.user)
    create(:issue_event, event: "mentioned", issue: issue_with_two, actor: issue_with_two.user)

    issue_with_one = create(:issue)
    mentioned = create(:issue_event, event: "mentioned", issue: issue_with_one, actor: issue_with_one.user)

    IssueEvent.stub_const(:MAX_MENTIONED_EVENTS, 1) do
      assert_empty IssueEvent.mentioned_users(issue_with_two)
      assert_dogstats_increment(1, "issue_event.mentioned_users.skipped")

      refute_empty IssueEvent.mentioned_users(issue_with_one)
    end
  end

  test "#cross_reference" do
    other_repo = create(:repository)
    event = create(:issue_event, event: "referenced", commit_repository: other_repo, repository: @repo, issue: @issue)
    assert_predicate event, :cross_commit_repository?

    event = create(:issue_event, event: "referenced", commit_repository: @repo, repository: @repo, issue: @issue)
    refute_predicate event, :cross_commit_repository?
  end

  test "#permalink" do
    @issue.close

    ev = @issue.events.first
    assert_equal "https://github.com/ari/Kunze-Smith/pull/#{@issue.pull_request.number}#event-#{ev.id}", ev.permalink
    assert_equal "/ari/Kunze-Smith/pull/#{@issue.pull_request.number}#event-#{ev.id}", ev.permalink(include_host: false)

    @issue2.close

    ev = @issue2.events.first
    assert_equal "https://github.com/ari/Kunze-Smith/issues/#{@issue2.number}#event-#{ev.id}", ev.permalink
    assert_equal "/ari/Kunze-Smith/issues/#{@issue2.number}#event-#{ev.id}", ev.permalink(include_host: false)
  end

  test "#permalink for a ready_for_review event" do
    @org_pull.convert_to_draft(user: @org_pull.user)
    @org_pull.ready_for_review!(user: @org_pull.user)

    event = @org_issue.events.last

    assert event.ready_for_review?
    assert_equal "#{@org_pull.permalink}/changes_since_last_review", event.permalink
    assert_equal "#{@org_pull.permalink(include_host: false)}/changes_since_last_review", event.permalink(include_host: false)
  end

  test "#anchor" do
    @issue.close

    ev = @issue.events.first
    assert_equal "#event-#{ev.id}", ev.anchor
  end

  context "#async_unmark_as_duplicate_path_uri" do
    test "nil for non marked as duplicate events" do
      event = create(:issue_event, issue: @issue, actor: @user, event: "closed", subject: @org_issue)
      assert_nil event.async_unmark_as_duplicate_path_uri.sync
    end

    test "is the expected uri format" do
      event = create(:issue_event, issue: @issue, actor: @user, event: "marked_as_duplicate",
                              subject: @org_issue)
      expected = "/#{@issue.repository.owner.login}/#{@issue.repository.name}/issues/#{@issue.number}/duplicate"
      assert_equal expected, event.async_unmark_as_duplicate_path_uri.sync.to_s
    end
  end

  context "#async_subject_as_issue_or_pull_request" do

    test "subject is the issue belonging to a PR" do
      event = create(:issue_event, subject: @pull.issue)
      event = IssueEvent.find event.id

      assert_equal @pull, event.async_subject_as_issue_or_pull_request.sync
    end

    test "subject is an issue" do
      event = create(:issue_event, subject: @issue2)
      event = IssueEvent.find event.id

      assert_equal @issue2, event.async_subject_as_issue_or_pull_request.sync
    end

    test "subject is a user" do
      subject = create(:user)
      event = create(:issue_event, subject: subject)
      event = IssueEvent.find event.id

      assert_nil event.async_subject_as_issue_or_pull_request.sync
    end

    test "subject is nil" do
      event = create(:issue_event, subject: nil)
      event = IssueEvent.find event.id

      assert_nil event.async_subject_as_issue_or_pull_request.sync
    end
  end

  context "#async_visible_closer" do
    test "nil for non-closed events" do
      event = create(:issue_event, referencing_issue: @issue, event: "referenced")
      assert_nil event.async_visible_closer(Platform::Authorization::Permission.new({ viewer: @issue.user, origin: Platform::ORIGIN_MANUAL_EXECUTION })).sync
    end

    test "nil when abilities are nil" do
      event = create(:issue_event, referencing_issue: @issue, event: "closed")
      assert_nil event.async_visible_closer(nil).sync
    end

    test "nil for closed events with no commit or referencing issue" do
      event = create(:issue_event, event: "closed")
      assert_nil event.async_visible_closer(Platform::Authorization::Permission.new({ viewer: @issue.user, origin: Platform::ORIGIN_MANUAL_EXECUTION })).sync
    end

    context "with read access to referenced memex project" do
      test "returns the closer project for org owner and user is an org member" do
        issue = create(:issue, repository: @org_repo)
        memex_item = create(:memex_project_item, memex_project: @project, content: issue)
        event = create(:issue_event, issue: memex_item.content, actor: @collaborator, performed_by_project_workflow_action_id: @workflow_action.id, column_name: "Done", event: "closed")
        assert_equal @project, event.async_visible_closer(Platform::Authorization::Permission.new({ viewer: @collaborator, origin: Platform::ORIGIN_MANUAL_EXECUTION })).sync
      end
    end

    context "without read access to referenced memex project" do
      test "returns nil" do
        user = create(:collaborator, repository: @org_repo)
        issue = create(:issue, repository: @org_repo)
        memex_item = create(:memex_project_item, memex_project: @project, content: issue)

        event = create(:issue_event, issue: memex_item.content, performed_by_project_workflow_action_id: @workflow_action.id, column_name: "Done", event: "closed")
        assert_nil event.async_visible_closer(Platform::Authorization::Permission.new({ viewer: user, origin: Platform::ORIGIN_MANUAL_EXECUTION })).sync
      end
    end

    context "with read access to referencing repository" do
      test "returns the closer pull" do
        event = create(:issue_event, referencing_issue: @issue, event: "closed")
        assert_equal @pull, event.async_visible_closer(Platform::Authorization::Permission.new({ viewer: @issue.user, origin: Platform::ORIGIN_MANUAL_EXECUTION })).sync
      end

      test "returns the closer commit" do
        commit = @repo.heads.find("master").target
        event = create(:issue_event, commit_id: commit.oid, event: "closed", repository: @repo, issue: @issue)
        assert_equal commit, event.async_visible_closer(Platform::Authorization::Permission.new({ viewer: @issue.user, origin: Platform::ORIGIN_MANUAL_EXECUTION })).sync
      end
    end

    context "without read access to referencing repository" do
      test "returns nil for the closer pull" do
        event = create(:issue_event, referencing_issue: @issue, event: "closed")
        assert_nil event.async_visible_closer(Platform::Authorization::Permission.new({ viewer: event.actor, origin: Platform::ORIGIN_MANUAL_EXECUTION })).sync
      end

      test "returns nil for the closer commit" do
        commit = @repo.heads.find("master").target
        issue = create(:issue, repository: @repo)
        event = create(:issue_event, commit_id: commit.oid, event: "closed", repository: @repo, issue: issue)
        assert_nil event.async_visible_closer(Platform::Authorization::Permission.new({ viewer: event.actor, origin: Platform::ORIGIN_MANUAL_EXECUTION })).sync
      end
    end
  end

  context "#visible_closer_for" do
    test "nil for non-closed events" do
      Platform::Authorization::Permission.new({ viewer: @collaborator, origin: Platform::ORIGIN_MANUAL_EXECUTION })
      event = create(:issue_event, referencing_issue: @issue, event: "referenced")
      assert_nil event.visible_closer_for(@collaborator)
    end

    test "nil when abilities are nil" do
      rando = create(:user)
      event = create(:issue_event, referencing_issue: @issue, event: "closed")
      assert_nil event.visible_closer_for(rando)
    end

    test "nil for closed events with no commit or referencing issue" do
      Platform::Authorization::Permission.new({ viewer: @collaborator, origin: Platform::ORIGIN_MANUAL_EXECUTION })
      event = create(:issue_event, event: "closed")
      assert_nil event.visible_closer_for(@collaborator)
    end

    test "with read access to referenced memex project returns the closer project" do
      Platform::Authorization::Permission.new({ viewer: @collaborator, origin: Platform::ORIGIN_MANUAL_EXECUTION })
      issue = create(:issue, repository: @org_repo)
      memex_item = create(:memex_project_item, memex_project: @project, content: issue)
      event = create(:issue_event, issue: memex_item.content, performed_by_project_workflow_action_id: @workflow_action.id, column_name: "Done", event: "closed")
      assert_equal @project, event.visible_closer_for(@collaborator)
    end

    test "returns nil without read access to referenced memex project" do
      Platform::Authorization::Permission.new({ viewer: @collaborator, origin: Platform::ORIGIN_MANUAL_EXECUTION })
      user = create(:collaborator, repository: @org_repo)
      issue = create(:issue, repository: @org_repo)
      memex_item = create(:memex_project_item, memex_project: @project, content: issue)

      event = create(:issue_event, issue: memex_item.content, performed_by_project_workflow_action_id: @workflow_action.id, column_name: "Done", event: "closed")
      assert_nil event.visible_closer_for(user)
    end

    context "with read access to referencing repository" do
      test "returns the closer pull" do
        event = create(:issue_event, referencing_issue: @issue, event: "closed")
        assert_equal @pull, event.async_visible_closer(Platform::Authorization::Permission.new({ viewer: @issue.user, origin: Platform::ORIGIN_MANUAL_EXECUTION })).sync
      end

      test "returns the closer commit" do
        commit = @repo.heads.find("master").target
        event = create(:issue_event, commit_id: commit.oid, event: "closed", repository: @repo, issue: @issue)
        assert_equal commit, event.async_visible_closer(Platform::Authorization::Permission.new({ viewer: @issue.user, origin: Platform::ORIGIN_MANUAL_EXECUTION })).sync
      end
    end

    context "without read access to referencing repository" do
      test "returns nil for the closer pull" do
        event = create(:issue_event, referencing_issue: @issue, event: "closed")
        assert_nil event.async_visible_closer(Platform::Authorization::Permission.new({ viewer: event.actor, origin: Platform::ORIGIN_MANUAL_EXECUTION })).sync
      end

      test "returns nil for the closer commit" do
        commit = @repo.heads.find("master").target
        issue = create(:issue, repository: @repo)
        event = create(:issue_event, commit_id: commit.oid, event: "closed", repository: @repo, issue: issue)
        assert_nil event.async_visible_closer(Platform::Authorization::Permission.new({ viewer: event.actor, origin: Platform::ORIGIN_MANUAL_EXECUTION })).sync
      end
    end
  end

  test "dismissed_review returns the review that matches the id" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    review = @pull.reviews.create!(
      user: @bwalsh,
      head_sha: @pull.head_sha,
    )
    event = create(:issue_event, event: "review_dismissed", pull_request_review_id: review.id, actor_id: @bwalsh.id, issue: @issue)

    assert_equal 1, GitHub.dogstats.increments("pull_request.events.review_dismissed.count").length
    assert_equal event.dismissed_review, review
  end

  test "dismissal message autolinks urls" do
    review = @pull.reviews.create!(
      user: @bwalsh,
      head_sha: @pull.head_sha,
    )
    event = create(:issue_event, event: "review_dismissed",
      pull_request_review_id: review.id,
      actor_id: @bwalsh.id,
      issue: @issue,
      message: "I don't think so - see https://github.com/some/repo/issues/1")
    assert_match %r|<a href="https://github.com/some/repo/issues/1">https://github.com/some/repo/issues/1</a>|, event.dismissal_message
  end

  test "dismissal message hyperlinks issue mentions" do
    review = @pull.reviews.create!(
      user: @bwalsh,
      head_sha: @pull.head_sha,
    )
    event = create(:issue_event, event: "review_dismissed",
      pull_request_review_id: review.id,
      actor_id: @bwalsh.id,
      issue: @issue,
      message: "I don't think so - see ##{@pull.issue.number}")

    assert_match %r|<a .*href="#{@pull.permalink}".*>#1</a>|, event.dismissal_message
  end

  context "notify for event" do
    test "returns false if it is a closed event for a PullRequest that has been merged" do
      pull = make_pr_and_repos
      pull.merge
      event = create(:issue_event, event: "closed", issue: pull.issue)

      refute event.notify_for_event?
    end

    # IssueEvent closed and PullRequest not merged => true
    test "returns true if it is a closed event for a PullRequest that has not been merged" do
      pull = make_pr_and_repos
      event = create(:issue_event, event: "closed", issue: pull.issue)

      assert event.notify_for_event?
    end

    # IssueEvent merged and Issue is a PullRequest => true
    test "returns true if merged event" do
      event = create(:issue_event, event: "merged")

      assert event.notify_for_event?
    end

    # IssueEvent closed and Issue is not a PullRequest => true
    test "returns true if closed event for an Issue" do
      event = create(:issue_event, event: "closed")

      assert event.notify_for_event?
    end

    test "returns true if review request notifications are enabled and a team member is requested" do
      pull = make_pr_and_repos
      team = create(:team, review_request_delegation_notify_team: true)
      team = create(:team)
      reviewer = create(:user)
      team.add_member(reviewer)
      team.add_member(pull.user)
      team.add_repository(pull.repository, :push)
      pull.repository.add_member(reviewer, action: :write)
      ReviewRequest.create(pull_request_id: pull.id, reviewer_id: reviewer.id)
      ReviewRequest.create(pull_request_id: pull.id, reviewer_id: team.id)
      event = IssueEvent.new(issue: pull.issue, event: "review_requested", actor_id: @pull.user_id, subject: team)

      assert event.notify_for_event?
    end

    test "returns true if review request notifications are enabled and a team member is not requested" do
      pull = make_pr_and_repos
      reviewer = create(:user)
      team = create(:team, review_request_delegation_notify_team: true)
      team.add_member(reviewer)
      team.add_member(pull.user)
      team.add_repository(pull.repository, :push)
      pull.repository.add_member(reviewer, action: :write)
      ReviewRequest.create(pull_request_id: pull.id, reviewer_id: team.id)
      event = IssueEvent.new(issue: pull.issue, event: "review_requested", actor_id: @pull.user_id, subject: team)

      assert event.notify_for_event?
    end

    test "returns false if review request notifications are disabled and a team member is requested" do
      pull = make_pr_and_repos
      team = create(:team, organization: @org, review_request_delegation_notify_team: false)
      reviewer = create(:user)
      team.add_member(reviewer)
      team.add_member(pull.user)
      team.add_repository(pull.repository, :push)
      pull.repository.add_member(reviewer, action: :write)
      ReviewRequest.create(pull_request_id: pull.id, reviewer_id: reviewer.id)
      ReviewRequest.create(pull_request_id: pull.id, reviewer_id: team.id)
      event = IssueEvent.new(issue: pull.issue, event: "review_requested", actor_id: @pull.user_id, subject: team)

      refute event.notify_for_event?
    end

    test "returns true if review request notifications are disabled and a team member is not requested" do
      pull = make_pr_and_repos
      reviewer = create(:user)
      team = create(:team, review_request_delegation_notify_team: false)
      team.add_member(reviewer)
      team.add_member(pull.user)
      team.add_repository(pull.repository, :push)
      pull.repository.add_member(reviewer, action: :write)
      ReviewRequest.create(pull_request_id: pull.id, reviewer_id: team.id)
      event = IssueEvent.new(issue: pull.issue, event: "review_requested", actor_id: @pull.user_id, subject: team)

      assert event.notify_for_event?
    end
  end

  context "#subscribe_for_event?" do
    test "true when review request delegation should not notify team and no individual team members assigned" do
      pull = make_pr_and_repos
      reviewer = create(:user)
      team = create(:team, review_request_delegation_notify_team: false)
      team.add_member(reviewer)
      team.add_member(pull.user)
      team.add_repository(pull.repository, :push)
      pull.repository.add_member(reviewer, action: :write)
      ReviewRequest.create(pull_request_id: pull.id, reviewer_id: team.id)
      event = IssueEvent.new(issue: pull.issue, event: "review_requested", actor_id: @pull.user_id, subject: team)

      assert event.subscribe_for_event?
    end

    test "false when review request delegation should not notify team and an individual team member is assigned" do
      pull = make_pr_and_repos
      reviewer = create(:user)
      team = create(:team, organization: @org, review_request_delegation_notify_team: false)
      team.add_member(reviewer)
      team.add_member(pull.user)
      team.add_repository(pull.repository, :push)
      pull.repository.add_member(reviewer, action: :write)
      ReviewRequest.create(pull_request_id: pull.id, reviewer_id: team.id)
      ReviewRequest.create(pull_request_id: pull.id, reviewer_id: reviewer.id)
      event = IssueEvent.new(issue: pull.issue, event: "review_requested", actor_id: @pull.user_id, subject: team)

      refute event.subscribe_for_event?
    end
  end

  context "#subject_issue_readable_by?" do
    test "false when event has no issue subject" do
      some_team = create(:team)
      event = create(:issue_event, event: "closed", issue: @org_issue, subject: some_team)

      refute event.subject_issue_readable_by?(@user)
    end

    test "false when subject issue does not exist" do
      ephemeral_issue = create(:issue, user: @ari, repository: @org_repo)
      event = create(:issue_event,
        event: "marked_as_duplicate",
        issue: @org_issue,
        subject: ephemeral_issue,
      )
      ephemeral_issue.destroy
      event.reload

      refute event.subject_issue_readable_by?(@user)
    end

    test "false when viewer does not have access" do
      event = create(:issue_event, event: "marked_as_duplicate", issue: @issue)

      refute event.subject_issue_readable_by?(@user)
    end

    if GitHub.spamminess_check_enabled?
      test "false when the subject is hidden from the viewer (spammy)" do
        issue = create(:issue, user: @spammer)
        event = create(:issue_event, event: "marked_as_duplicate", subject: issue)

        refute event.subject_issue_readable_by?(@user)
      end
    end

    test "true when viewer has access to subject issue's repository" do
      dup_issue = create(:issue, user: @ari, repository: @org_repo)
      event = create(:issue_event,
        event: "marked_as_duplicate",
        issue: @org_issue,
        subject: dup_issue,
      )

      assert event.subject_issue_readable_by?(@user)
    end
  end

  context "triggering notifications" do
    test "assigned events trigger notifications with the assignee" do
      assigner = create(:user)
      assignee = create(:user)
      repo = create(:repository, owner: assigner)
      repo.add_member(assignee)
      issue = create(:issue, repository: repo, user: assigner)

      saved_at = Time.now.change(usec: 0).utc

      # Assigned events reverse the normal actor/subject relationship
      event = IssueEvent.new(issue: issue, event: "assigned", actor_id: assignee.id, subject_id: assigner.id)
      GitHub.newsies.expects(:trigger).with(
        instance_of(IssueEventNotification),
        recipient_ids: [assignee.id],
        reason: :assign,
        event_time: saved_at,
      )
      perform_enqueued_jobs only: SubscribeAndNotifyJob do
        Timecop.freeze(saved_at) { event.save! }
      end
    end

    test "activity events trigger notifications with a reason" do
      event = IssueEvent.new(issue: @issue, event: "closed", actor_id: @user.id)

      saved_at = Time.now.change(usec: 0).utc

      GitHub.newsies.expects(:trigger).with(
        instance_of(IssueEventNotification),
        recipient_ids: nil,
        reason: :state_change,
        event_time: saved_at,
      )
      perform_enqueued_jobs only: SubscribeAndNotifyJob do
        Timecop.freeze(saved_at) { event.save! }
      end

      saved_at = Time.now.change(usec: 0).utc

      event = IssueEvent.new(issue: @issue, event: "reopened", actor_id: @user.id)
      GitHub.newsies.expects(:trigger).with(
        instance_of(IssueEventNotification),
        recipient_ids: nil,
        reason: :state_change,
        event_time: saved_at,
      )
      perform_enqueued_jobs only: SubscribeAndNotifyJob do
        Timecop.freeze(saved_at) { event.save! }
      end

      event = IssueEvent.new(issue: @issue, event: "merged", actor_id: @user.id)
      GitHub.newsies.expects(:trigger).with(
        instance_of(IssueEventNotification),
        recipient_ids: nil,
        reason: :state_change,
        event_time: saved_at,
      )
      perform_enqueued_jobs only: SubscribeAndNotifyJob do
        Timecop.freeze(saved_at) { event.save! }
      end

      event = IssueEvent.new(issue: @issue, event: "review_requested", actor_id: @user.id, subject_id: @drama.id)
      GitHub.newsies.expects(:trigger).with(
        instance_of(IssueEventNotification),
        recipient_ids: [@drama.id],
        reason: :review_requested,
        event_time: saved_at,
      )
      perform_enqueued_jobs only: SubscribeAndNotifyJob do
        Timecop.freeze(saved_at) { event.save! }
      end

      bot = create(:integration).bot #todo add the new mq bot here
      event = IssueEvent.new(issue: @issue, event: "added_to_merge_queue", actor_id: bot, subject: @issue.user)
      GitHub.newsies.expects(:trigger).with(
        instance_of(IssueEventNotification),
        recipient_ids: nil,
        reason: :state_change,
        event_time: saved_at,
      )
      perform_enqueued_jobs only: SubscribeAndNotifyJob do
        Timecop.freeze(saved_at) { event.save! }
      end

      event = IssueEvent.new(issue: @issue, event: "removed_from_merge_queue", actor_id: bot, subject: @issue.user)
      GitHub.newsies.expects(:trigger).with(
        instance_of(IssueEventNotification),
        recipient_ids: nil,
        reason: :state_change,
        event_time: saved_at,
      )
      perform_enqueued_jobs only: SubscribeAndNotifyJob do
        Timecop.freeze(saved_at) { event.save! }
      end
    end

    test "ready_for_review events don't trigger notifications" do
      event = IssueEvent.new(issue: @org_issue, event: "ready_for_review", actor_id: @org_issue.user.id)
      GitHub.newsies.expects(:trigger).never
      perform_enqueued_jobs only: SubscribeAndNotifyJob do
        event.save!
      end
    end

    test "activity events don't trigger notifications when send_notifications? is disabled" do
      GitHub.stubs(:send_notifications?).returns(false)
      event = IssueEvent.new(issue: @issue, event: "closed", actor_id: @user.id)
      GitHub.newsies.expects(:trigger).never
      perform_enqueued_jobs only: SubscribeAndNotifyJob do
        event.save!
      end
    end

    test "converted_to_discussion triggers notifications" do
      repo = create(:repository, has_discussions: true)
      issue = create(:issue, repository: repo)
      discussion = create(:discussion, repository: repo)
      saved_at = Time.now.change(usec: 0).utc

      event = IssueEvent.new(
        issue: issue,
        event: "converted_to_discussion",
        actor_id: repo.owner.id,
        subject: discussion,
      )
      GitHub.newsies.expects(:trigger).with(
        instance_of(IssueEventNotification),
        recipient_ids: nil,
        reason: :state_change,
        event_time: saved_at,
      )
      perform_enqueued_jobs only: SubscribeAndNotifyJob do
        Timecop.freeze(saved_at) { event.save! }
      end
    end
  end

  context "#async_project" do
    test "returns project through project card when card exists" do
      card = create(:project_card)
      event = create(:issue_event,
        issue: @issue,
        event: "added_to_project",
        subject: card.project,
        card_id: card.id,
      )

      assert_equal card.project, event.async_project.sync
    end

    test "returns project through subject when card does not exist" do
      card = create(:project_card)
      project = card.project
      event = create(:issue_event,
        issue: @issue,
        event: "added_to_project",
        subject: project,
        card_id: card.id,
      )
      card.destroy

      assert_equal project, event.async_project.sync
    end
  end

  context "#async_project_card" do
    test "returns project card" do
      card = create :project_card
      event = create(:issue_event,
        issue: @issue,
        event: "added_to_project",
        subject: card.project,
        card_id: card.id,
      )

      assert_equal card, event.async_project_card.sync
    end
  end

  context "#async_project_column_name" do
    test "returns project column name" do
      event = create(:issue_event,
        issue: @issue,
        event: "added_to_project",
        column_name: "foobar",
      )

      assert_equal "foobar", event.async_project_column_name.sync
    end
  end

  context "automatically changing base succeeds" do
    test "creates the event" do
      event = create(:issue_event, issue: @pull.issue, event: "automatic_base_change_succeeded")
      assert_equal "automatic_base_change_succeeded", event.reload.event
    end
  end

  context "automatically changing base fails" do
    test "creates the event" do
      event = create(:issue_event, issue: @pull.issue, event: "automatic_base_change_failed")
      assert_equal "automatic_base_change_failed", event.reload.event
    end
  end

  context "automation checks via issue_event_detail" do
    test "automated? returns false with no workflow action ID" do
      event = IssueEvent.new(
        actor: create(:user),
      )
      refute event.automated?, "An event without a workflow action ID should not be marked as automated"
    end

    test "automated? returns true with workflow action ID" do
      event = IssueEvent.new(
        actor: create(:user),
        performed_by_project_workflow_action_id: 12345,
      )
      assert event.automated?, "An event with a workflow action ID should be marked as automated"
    end
  end

  context "#async_revertable_by?" do
    test "memoized value returns false when no user" do
      issue_event = IssueEvent.new
      refute issue_event.async_revertable_by?(nil).sync
      # check memoized value
      refute issue_event.async_revertable_by?(nil).sync
    end
  end

  context "#memex_project" do
    test "returns the memex project through performed_by_project_workflow_action_id" do
      issue = create(:issue, repository: @org_repo)
      memex_item = create(:memex_project_item, memex_project: @project, content: issue)
      assert memex_item.content.close(@collaborator, attributes: { performed_by_project_workflow_action_id: @workflow_action.id, closing_status_in_project: "Done" })
      assert_equal @project, issue.events.last.memex_project
    end

    test "returns nil if event is not triggered by auto_close workflow" do
      closed = create(:issue_event, event: "closed", commit_id: "abcd")
      assert_nil closed.memex_project
    end
  end

  context "#async_closer" do
    test "returns the memex project as closer if performed through memex project workflow" do
      issue = create(:issue, repository: @org_repo)
      memex_item = create(:memex_project_item, memex_project: @project, content: issue)
      assert memex_item.content.close(@collaborator, attributes: { performed_by_project_workflow_action_id: @workflow_action.id, closing_status_in_project: "Done" })
      assert_equal @project, issue.events.last.async_closer.sync
    end
  end

  context "#closer" do
    test "returns the memex project if performed through memex project workflow" do
      issue = create(:issue, repository: @org_repo)
      memex_item = create(:memex_project_item, memex_project: @project, content: issue)

      assert memex_item.content.close(@collaborator, attributes: { performed_by_project_workflow_action_id: @workflow_action.id, closing_status_in_project: "Done" })
      assert_equal @project, issue.events.last.closer
    end
  end
end
