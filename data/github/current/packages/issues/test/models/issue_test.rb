# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/query_identifier_helper"

class IssueTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers
  include QueryIdentifierHelper
  include DogstatsTestHelpers
  include BackgroundDeletesTestHelpers
  include ResiliencyHelpers

  mention_limit = GitHub::HTML::MentionFilter::MENTION_LIMIT

  fixtures do
    @owner        = create :user, plan: "large"
    @authed       = create :user
    @unauthed     = create :user
    @spammer      = create :user, spammy: true
    @member       = create :user

    @private_repo = create :private_repository, owner: @owner, admin: @owner, from_example: :pull_request_fork
    perform_enqueued_jobs(only: SubscribeAndNotifyJob) do
      @open_issue = create :issue, repository: @private_repo, user: @owner
    end
    @closed_issue = create :issue, repository: @private_repo, user: @owner, state: "closed"

    @open_issue_spam = create :issue, repository: @private_repo, user: @spammer

    @spammy_repo       = create :repository, owner: @spammer, admin: @spammer
    @spammy_open_issue = create :issue, repository: @spammy_repo, user: @spammer

    unless GitHub.enterprise?
      @staff = create(:staff_admin_user)
      @dmca_disabled_repo = create(:public_repository, owner: @owner, admin: @owner)
      @dmca_disabled_issue = create :issue, repository: @dmca_disabled_repo, user: @owner
      @dmca_disabled_repo.access.disable("dmca", @staff, dmca_takedown: "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown")
    end

    @repo = create(:public_repository, owner: @unauthed, admin: @unauthed)
    create(:collaborator, collaborator: @member, repository: @repo)

    @users        = (0..mention_limit).map { |i| create :user, login: "user#{i}" }
    @user         = @users.first
    @other_issue  = create :issue, repository: @repo, user: @user

    @milestone    = create :milestone, repository: @private_repo, title: "Zap Pow"

    create(:collaborator, collaborator: @authed, repository: @private_repo)
    create(:collaborator, collaborator: @user, repository: @private_repo)

    @help_wanted_label = create(:label, name: Labelable::HELP_WANTED_NAME, repository: @repo)
    @label   = create(:label, color: "ff0000", repository: @private_repo)
    @label_2 = create(:label, color: "000000", repository: @private_repo)
    @issue = create(:issue, repository: @repo, user: @unauthed)
    @private_issue = create(:issue, repository: @private_repo, user: @owner)
    @labeled = create(:issue, repository: @private_repo, user: @owner, labels: [@label])

    @issue_with_pull = Issue.create! \
        repository: @private_repo,
        title: @open_issue.title,
        body: @open_issue.body,
        user: @open_issue.user,
        pull_request: @private_repo.comparison("master", "topic").build_pull_request(user: @owner)

    @org = create :organization, admin: @owner
    @issue_type = create :issue_type, name: "Testing Type", owner: @org
    @private_repo_with_templates = create(:private_repository, owner: @org, admin: @owner, from_example: :dot_github)
    @memex_project = create(:memex_project, owner: @org)

    commit = @private_repo_with_templates.commits.create({ message: "Add files", author: @owner }) do |files|
      files.add ".github/ISSUE_TEMPLATE/cats.yml", <<~YAML
        name: All about cats
        about: Tell me about your favorite cats
        projects: ["#{@org}/#{@memex_project.number}"]
        type: "Testing Type"
        inputs:
          - type: input
            attributes:
              label: cats name
      YAML

      files.add ".github/ISSUE_TEMPLATE/bug.md", <<~MARKDOWN
        ---
        name: bug
        about: This is a bug
        title: Bug report
        type: "Testing Type"
        ---
        Use the format below to describe your bug.
      MARKDOWN
    end
    @private_repo_with_templates.refs["refs/heads/master"].update(commit, @owner)

  end

  context "#parent_repo_is_searchable?" do
    unless GitHub.enterprise?
      test "returns false if the repository is DMCA disabled" do
        refute_predicate @dmca_disabled_issue, :parent_repo_is_searchable?
      end
    end
  end

  context "number" do
    test "should start out as 1" do
      assert_equal 1, create(:issue).number
    end

    test "prevents save if set to 0" do
      issue = build(:issue)
      issue.expects(:set_number).once.returns(nil)
      refute issue.save
      assert issue.errors[:number].any?
    end
  end

  context "#for_repository" do
    test "returns issues if the repository has any" do
      owner = create(:user)
      repo = create(:repository, owner: owner, admin: owner)
      issue = create(:issue, repository: repo)
      assert_same_elements [issue], Issue.for_repository(repo)
    end

    test "returns empty if the repository has no issues" do
      assert_empty Issue.for_repository(create :repository)
    end
  end

  context "#for_organization" do
    test "returns issues if the organization has any" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo, user: org.admin)

      assert_equal [issue], Issue.for_organization(org)
    end

    test "returns empty if the organization has no issues" do
      assert_empty Issue.for_organization(create(:organization))
    end
  end

  context "destroy" do
    test "deletes issue reactions in background" do
      @issue.react(
        actor: @user,
        content: "tada"
      )
      assert_equal IssueReaction.count, 1

      only = [DestroyDependentRecordsJob]
      perform_enqueued_jobs(only: only) do
        @issue.destroy
      end

      assert_performed_jobs 1
      assert_equal IssueReaction.count, 0
    end

    test "deletes issue events in background using specific queue" do
      GitHub.flipper[:background_destroy_dedicated_queues].enable
      GitHub.flipper[:background_destroy_issues_pull_requests_queue].enable

      issue = create(:issue, repository: @private_repo, user: @owner, labels: [@label])
      assert issue.events.size == 1

      event = issue.events.first

      only = [DestroyDependentRecordsJob]
      perform_enqueued_jobs(only: only) do
        issue.destroy
      end

      assert_performed_jobs 1, queue: :background_destroy_issues_pull_requests
      assert_nil IssueEvent.find_by(id: event.id)
    end

    test "does not check for spam when issue is destroyed without a repo" do
      @repo.delete
      @issue.reload

      Issue.any_instance.expects(:enqueue_check_for_spam).never
      @issue.destroy
    end

    test "does not check for spam at all when destroyed" do
      Issue.any_instance.expects(:enqueue_check_for_spam).never
      @issue.destroy
    end

    test "works when destroying an issue with an orphaned list subscriber" do
      # Make newsies list subscribers appear orphaned.
      Newsies::Subscriber.any_instance.stubs(:user).returns(nil)

      subscriber = create(:user, login: "subscriber")
      GitHub.newsies.subscribe_to_list(subscriber, @issue.repository)

      @issue.destroy

      assert_nil Issue.find_by(id: @issue.id)
    end

    test "updates milestone count when destroying an issue" do
      @open_issue.update(milestone: @milestone)
      @private_issue.update(milestone: @milestone)

      assert_equal @milestone.open_issue_count, 2

      @open_issue.destroy

      assert_equal @milestone.open_issue_count, 1
    end

    test "doesn't throw an exception when updating milestone counts after repository has been deleted" do
      @open_issue.update(milestone: @milestone)
      @open_issue.repository.delete
      @open_issue.reload

      # Make sure we trigger the offending code path, despite how Rails would otherwise compute
      # this attribute.
      @open_issue.stubs(:milestone_id_before_last_save).returns(@milestone.id)

      assert_nothing_raised { @open_issue.destroy! }
    end

    test "destroy linked issue events" do
      issue_id = @issue.id
      create(:issue_event, issue: @issue)

      @issue.destroy
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob])

      assert_equal 0, IssueEvent.where(issue_id: issue_id).count
    end

    test "destroy child sub-issue relationships" do
      issue_id = @issue.id
      child = create(:issue, repository: @issue.repository)
      @issue.add_sub_issue!(child, @owner.id)

      assert_equal 1, SubIssue.where(source_issue_id: issue_id).count

      @issue.destroy
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob])

      assert_equal 0, SubIssue.where(source_issue_id: issue_id).count
    end

    test "destroy parent sub-issue relationships" do
      issue_id = @issue.id
      child = create(:issue, repository: @issue.repository)
      @issue.add_sub_issue!(child, @owner.id)

      assert_equal 1, SubIssue.where(source_issue_id: issue_id).count

      child.destroy
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob])

      assert_equal 0, SubIssue.where(source_issue_id: issue_id).count
    end

    test "instruments a destroy event" do
      events = subscribe "issue.destroy"

      issue = build(:issue, repository: @private_repo_with_templates, user: @owner)

      issue.destroy

      expected_payload = {
        title: issue.title,
        body: issue.body,
        org: issue.repository.owner.login,
        org_id: issue.repository.owner.id,
      }

      assert event = events.pop, "expected an instrumentation event"

      assert_equal expected_payload[:org], event.payload[:org]
      assert_equal expected_payload[:org_id], event.payload[:org_id]
    end
  end

  test "instruments hydro event when issue is created from a structured issue template" do
    data = {
      favorite_cat: "orange",
      least_favorite_cat: "dog",
    }

    issue = build(:issue, repository: @repo, user: @user)
    issue.issue_form_params = data
    issue.save

    expected_hydro_payload = {
      actor: Hydro::EntitySerializer.user(@user),
      data: JSON.dump(data),
      issue: Hydro::EntitySerializer.issue(issue),
      repository: Hydro::EntitySerializer.repository(@repo),
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
    }
    assert_hydro_published(
      expected_hydro_payload,
      schema: "github.issue_templates.v0.IssueCreateEvent",
    )
    assert_hydro_messages(count: 1, schema: "github.issue_templates.v0.IssueCreateEvent")
  end

  test "title should be less than 1024 bytes" do
    # this character is a 3 byte unicode sequence
    mb_str = "漢"
    ascii_str = "a"

    issue = create :issue, repository: @private_repo, user: @owner
    issue.title = mb_str * 1024
    refute issue.valid?
    refute issue.save
    assert issue.errors[:title].any?

    issue.title = mb_str * 1025
    refute issue.valid?
    refute issue.save
    assert issue.errors[:title].any?

    issue.title = mb_str * 342
    refute issue.valid?
    refute issue.save
    assert issue.errors[:title].any?

    issue.title = mb_str * 341
    assert issue.valid?
    assert issue.save
    refute issue.errors[:title].any?

    issue.title = ascii_str * 1025
    refute issue.valid?
    refute issue.save
    assert issue.errors[:title].any?

    issue.title = ascii_str * 1024
    assert issue.valid?
    assert issue.save
    refute issue.errors[:title].any?
  end

  test "titles should be UTF-8" do
    issue = create :issue, repository: @private_repo, user: @owner
    title = "Have a glass of \xF0\x9F\x8D\xB7"
    issue.title = title
    assert issue.save
    issue.reload
    assert_equal Encoding::UTF_8, issue.title.encoding
    assert_equal title, issue.title
    issue.reload
    issue.title = "Have a glass of \xF0\x9F\x8D\xB7"
    assert_empty issue.changes
    refute_predicate issue, :changed?
    refute_predicate issue, :title_changed?
    issue.reload
    issue.title = "Have a glass of \xF0\x9F\xA5\x83"
    refute_empty issue.changes
    assert_predicate issue, :changed?
    assert_predicate issue, :title_changed?
  end

  test "bodies should be UTF-8" do
    issue = create :issue, repository: @private_repo, user: @owner
    body = "Have a glass of \xF0\x9F\x8D\xB7"
    issue.body = body
    assert issue.save
    issue.reload
    assert_equal Encoding::UTF_8, issue.body.encoding
    assert_equal body, issue.body
    assert_equal Encoding::UTF_8, issue.compressed_body.encoding
    assert_equal body, issue.compressed_body
  end

  context "assigning body" do
    test "assigning a body also assigns a compressed_body" do
      issue = create :issue, repository: @private_repo, user: @owner
      body = "uncompressed issue body"
      issue.body = body
      assert issue.save
      issue.reload
      assert_equal body, issue.body
      assert_equal body, issue.compressed_body
      refute_equal body, issue.compressed_body_before_type_cast
    end

    test "reassigning a body should reassign the compressed_body" do
      issue = create :issue, repository: @private_repo, user: @owner
      body = "uncompressed issue body"
      issue.body = body
      assert issue.save
      new_body = "new uncompressed issue body"
      issue.body = new_body
      issue.save
      issue.reload
      assert_equal new_body, issue.body
      assert_equal new_body, issue.compressed_body
      refute_equal new_body, issue.compressed_body_before_type_cast
    end

    test "assigning the same body twice with multibyte characters" do
      body = "an issue body 😀"

      issue = create :issue, repository: @private_repo, user: @owner, body: body

      # As the issue body was assigned from a UTF8 encoded string,
      # that's what we see here.
      assert_equal issue.read_attribute(:body).encoding, Encoding::UTF_8

      # This causes `body` to be loaded from the `varbinary` column, tagged as binary encoded
      issue.reload

      # The body gets loaded from the database in proper UTF-8
      assert_equal issue.read_attribute(:body).encoding, Encoding::UTF_8

      # Assigning the same body (same bytes, different encoding) again
      # should not cause the body to be seen as changed.
      issue.body = body

      refute_predicate issue, :body_changed?
      refute_predicate issue, :compressed_body_changed?
    end

    test "assigning the same body via `update_body` with multibyte characters" do
      body = "an issue body 😀"

      issue = create :issue, repository: @private_repo, user: @owner, body: body

      # As the issue body was assigned from a UTF8 encoded string,
      # that's what we see here.
      assert_equal Encoding::UTF_8, issue.read_attribute(:body).encoding
      assert_equal Encoding::UTF_8, issue.read_attribute(:compressed_body).encoding

      # This causes `body` to be loaded from the `varbinary` column, tagged as binary encoded
      issue.reload

      # The body gets loaded from the database in proper UTF-8
      assert_equal Encoding::UTF_8, issue.read_attribute(:body).encoding
      assert_equal Encoding::UTF_8, issue.read_attribute(:compressed_body).encoding

      # Assigning the same body (same bytes, different encoding) again
      # should not cause the body to be seen as changed.
      issue.update_body(body, @owner)

      refute_predicate issue, :body_changed?
      refute_predicate issue, :compressed_body_changed?
    end

    test "assigning a nil body does not assign compressed_body" do
      issue = create :issue, repository: @private_repo, user: @owner, body: nil
      assert_nil issue.compressed_body_before_type_cast
    end
  end

  test "does not create issue when the body is too long" do
    issue = create :issue, repository: @private_repo, user: @owner
    body = "a" * (MYSQL_UNICODE_BLOB_LIMIT + 1)
    issue.body = body
    assert !issue.valid?, "#{issue.errors.full_messages}"
    assert_equal issue.errors.full_messages[0], "Body is too long"
  end

  test "does not accept a body with more than 65536 characters when record is new" do
    max_chars = MYSQL_UNICODE_BLOB_LIMIT / 4
    emoji = "😍"

    issue   = build :issue, repository: @private_repo, user: @owner
    assert issue.new_record?

    issue.body = emoji * max_chars
    assert_valid issue

    issue.body = "a" * max_chars
    assert_valid issue

    issue.body += "a"
    refute_valid issue
    assert_equal "Body is too long (maximum is 65536 characters)", issue.errors.full_messages.join

    # it should be valid on update for backward compatibility
    @private_issue.body = issue.body
    assert_valid @private_issue
  end

  test "does not create issue when the title is too long" do
    expected_characters = 256
    issue = create :issue, repository: @private_repo, user: @owner
    title = "a" * (Issue::TITLE_BYTESIZE_LIMIT + 1)
    issue.title = title
    assert !issue.valid?, "#{issue.errors.full_messages}"
    assert_equal issue.errors.full_messages[0], "Title is too long (maximum is #{expected_characters} characters)"
  end

  test "requires an owning repository" do
    issue = Issue.new user: @owner, title: "a title"
    assert !issue.valid?
    issue.repository = @private_repo
    assert issue.valid?
  end

  test "requires an owning user (created by)" do
    issue = Issue.new repository: @private_repo, title: "a title"
    assert !issue.valid?
    issue.user = @owner
    assert issue.valid?
  end

  test "accepts issues on locked repo not within migration" do
    Repository.any_instance.stubs(:locked_on_migration?).returns(true)
    assert @open_issue.valid?,
      "Issue should be valid but had the following errors: #{@open_issue.errors.full_messages}"
  end

  test "accepts issues on locked repo within migration" do
    Repository.any_instance.stubs(:locked_on_migration?).returns(true)
    GitHub.stubs(:importing?).returns(true)
    assert @open_issue.valid?
  end

  test "allows repo to be archived" do
    Repository.any_instance.stubs(:archived?).returns(true)
    assert @open_issue.valid?,
      "Issue should be valid but had the following errors: #{@open_issue.errors.full_messages}"
  end

  test "existing issue is editable with ghost (nil) user" do
    assert @open_issue.close(@authed, attributes: { user_id: nil })
    assert @open_issue.reload.closed?
    assert_nil @open_issue.user_id
  end

  context "#modifying_user" do
    test "returns the actor set in the context" do
      GitHub.context.push(actor_id: @user.id)
      assert_equal @user, @open_issue.modifying_user
    end

    test "returns the safe_user if actor_id is not set in the context" do
      result = @open_issue.modifying_user

      assert_equal @owner, result
      assert_equal @open_issue.safe_user, result, "expected the #modifying_user to be the #safe_user"
    end

    test "memoizes the result for repeated calls" do
      GitHub.context.push(actor_id: @user.id)

      assert_query_count(1) do
        assert_equal @user, @open_issue.modifying_user
      end

      assert_query_count(0) do
        assert_equal @user, @open_issue.modifying_user
      end
    end

    test "does not make any queries when modifying_user is set" do
      @open_issue.modifying_user = @user

      assert_query_count(0) do
        assert_equal @user, @open_issue.modifying_user
      end
    end

    test "makes only a single query when actor_id is not set in context" do
      GitHub.context.push(actor_id: nil)

      assert_query_count(1) do
        assert_equal @open_issue.safe_user, @open_issue.modifying_user
      end
    end
  end

  test "requires a title" do
    issue = Issue.new repository: @private_repo, user: @owner
    assert !issue.valid?
    issue.title = "a title"
    assert issue.valid?
  end

  test "state must be 'open' or 'closed'" do
    issue = Issue.new repository: @private_repo, user: @owner, title: "a title"
    assert issue.valid?
    issue.state = "closed"
    assert issue.valid?
    issue.state = "finna"
    assert issue.valid?
    assert_equal "open", issue.state
  end

  test "state defaults to 'open'" do
    issue = Issue.new repository: @private_repo, user: @owner, title: "a title"
    assert issue.valid?
    assert_equal "open", issue.state
  end

  test "a closed issue's state should == 'closed'" do
    assert_equal "closed", @closed_issue.state
  end

  test "a closed issue should have closed_at set" do
    refute_nil @closed_issue.closed_at
  end

  test "an open issue should not have closed_at set" do
    assert_nil @open_issue.closed_at
  end

  test "has a 'closed?' helper method" do
    assert_equal "closed", @closed_issue.state
    assert @closed_issue.respond_to? :closed?
    assert @closed_issue.closed?
  end

  test "has an 'open?' helper method" do
    assert_equal "open", @open_issue.state
    assert @open_issue.respond_to? :open?
    assert @open_issue.open?
  end

  test "does not update state reason by default" do
    assert @private_issue.close(@private_issue.user)
    assert  @private_issue.state_reason == Issue::StateReasonDependency::COMPLETED
  end

  test "does update state reason if the reason is specified" do
    # Close an issue as unresolved
    assert @private_issue.close(@private_issue.user, attributes: { state_reason: :not_planned })

    refute_nil @private_issue.state_reason
    assert @private_issue.state_reason_not_planned?
    assert_equal true, @private_issue.state_reason_not_planned?

    # Ensure that the value is persisted as tinyint in DB and not the actual string
    assert_equal 1, Issue.find_by(id: @private_issue.id)&.state_reason_before_type_cast

    # Ensure reopening updates the status
    assert @private_issue.open(@private_issue.user, { state_reason: :reopened })
    refute_nil @private_issue.state_reason
    assert_equal true, @private_issue.state_reason_reopened?

    # Closing as resolved afterwards also updates the status
    assert @private_issue.close(@private_issue.user, attributes: { state_reason: Issue::StateReasonDependency::COMPLETED })
    assert @private_issue.closed?
    assert  @private_issue.state_reason == Issue::StateReasonDependency::COMPLETED
  end

  test "updates state reason even when the issue is already closed" do
    assert @private_issue.close(@private_issue.user, attributes: { state_reason: :not_planned })
    assert_equal true, @private_issue.state_reason_not_planned?

    assert @private_issue.close(@private_issue.user, attributes: { state_reason: Issue::StateReasonDependency::COMPLETED })
    assert  @private_issue.state_reason == Issue::StateReasonDependency::COMPLETED
    assert @private_issue.close(@private_issue.user, attributes: { state_reason: :not_planned })
    assert_equal true, @private_issue.state_reason_not_planned?
  end

  test "does not update state reason for pulls" do
    Spokesd.enable_spokesd

    assert @issue_with_pull.close(@issue_with_pull.user, attributes: { state_reason: :not_planned })
    assert_nil @issue_with_pull.state_reason

    assert @issue_with_pull.open(@issue_with_pull.user, { state_reason: :reopened })
    assert_nil @issue_with_pull.state_reason
  end

  test "does not update with invalid state reason" do
    assert_raises ArgumentError do
      @private_issue.close(@private_issue.user, attributes: { state_reason: 23 })
    end
    assert_nil @private_issue.state_reason

    assert @private_issue.close(@private_issue.user, attributes: { state_reason: :not_planned })
    assert_raises ArgumentError do
      @private_issue.open(@private_issue.user, { state_reason: :reopened_again })
    end

    assert @private_issue.closed?
    assert @private_issue.state_reason_not_planned?
  end

  test "does fail if the state transition is not allowed" do
    assert @private_issue.close(@private_issue.user)
    refute @private_issue.close(@private_issue.user, attributes: { state_reason: :reopened })

    assert_includes @private_issue.errors[:state_reason], "Cannot transition to this state"
  end

  test "does not update if the state transition is the same" do
    assert @private_issue.close(@private_issue.user)
    assert_nil @private_issue.close(@private_issue.user, attributes: { state_reason: Issue::StateReasonDependency::COMPLETED })
  end

  test "does not update if the state transition is the same when FF enabled" do
    assert @private_issue.close(@private_issue.user)
    assert_nil @private_issue.close(@private_issue.user, attributes: { state_reason: Issue::StateReasonDependency::COMPLETED })
  end

  if GitHub.interaction_limits_enabled?
    context "interaction ban" do
      test "fails validation if user is interaction blocked" do
        User::InteractionAbility.stubs(:interaction_allowed?).returns(false)
        User::InteractionAbility.stubs(:ban_expiry).returns(DateTime.now + 1.day)
        interaction_ban_user = create(:user)
        begin
          create :issue, repository: @private_repo, user: interaction_ban_user
        rescue ActiveRecord::RecordInvalid => e
          assert_includes e.message, "suspended for"
        end
      end

      test "passes validation if user is interaction blocked but repo is org owned and user is an org member" do
        org = create(:organization)
        repo = create(:repository, owner: org, name: "org_owned_repo")
        User::InteractionAbility.stubs(:interaction_allowed?).returns(false)
        User::InteractionAbility.stubs(:ban_expiry).returns(DateTime.now + 1.day)
        interaction_ban_user = create(:user)
        org.add_member interaction_ban_user
        issue = build :issue, repository: repo, user: interaction_ban_user
        assert issue.valid?
      end

      test "pass on update when the editor is allowed" do
        interaction = RepositoryInteractionAbility.new(@repo)
        interaction.set_ability(:collaborators_only, @unauthed)

        assert @issue.update_body("hello!", @unauthed)
        assert_empty @issue.errors[:base]
      end

      test "fail on update when the editor is not allowed", skip_with_all_emus: true do
        interaction = RepositoryInteractionAbility.new(@repo)
        interaction.set_ability(:collaborators_only, @unauthed)

        refute @issue.update_body("hello!", @user)

        assert_includes @issue.errors[:base],
          "could not be created. Interactions on this repository have been restricted to collaborators only."
      end
    end
  end

  context "closing an open issue" do
    test "sets the closed_at to close the issue" do
      now = Time.now
      assert @open_issue.open?
      assert_nil @open_issue.closed_at
      assert @open_issue.close
      refute_nil @open_issue.closed_at
      assert_in_delta now, @open_issue.closed_at, 2
    end

    test "deprioritizes the issue in the milestone" do
      @open_issue.update(milestone: @milestone)
      refute_nil priority = @open_issue.issue_priorities.first
      assert @open_issue.close
      assert_raises(ActiveRecord::RecordNotFound) { priority.reload }
    end

    test "closes an issue with comment" do
      assert @open_issue.open?

      # Invoked twice, once on issue state change and once on issue comments count change
      GitHub::WebSocket.expects(:notify_issue_channel).with(@open_issue, GitHub::WebSocket::Channels.issue(@open_issue), anything).twice
      # Invoked once on state change
      GitHub::WebSocket.expects(:notify_issue_channel).with(@open_issue, GitHub::WebSocket::Channels.issue_state(@open_issue), anything).once

      @open_issue.comment_and_close(@user, "Closing comment")

      @open_issue.reload
      assert @open_issue.closed?
    end

    test "closes an issue without comment" do
      assert @open_issue.open?

      # Invoked once on state change
      GitHub::WebSocket.expects(:notify_issue_channel).with(@open_issue, GitHub::WebSocket::Channels.issue(@open_issue), anything).once
      GitHub::WebSocket.expects(:notify_issue_channel).with(@open_issue, GitHub::WebSocket::Channels.issue_state(@open_issue), anything).once

      @open_issue.comment_and_close(@user, "")

      @open_issue.reload
      assert @open_issue.closed?
    end
  end

  context "opening a closed issue" do
    test "unsets the closed_at to reopen the issue" do
      assert @closed_issue.closed?
      refute_nil @closed_issue.closed_at
      assert @closed_issue.reopen!
      assert_nil @open_issue.closed_at
    end

    test "opening-closing-reopening an issue in an org internal repo by external user" do
      org = create(:enterprise_linked_organization, admin: @owner)
      repo = create(:internal_repository, owner: org, name: "org_owned_repo")
      issue = create(:issue, repository: repo, user: @authed)
      issue.close(@authed)

      assert issue.closed?

      issue.open(@authed)

      assert issue.open?
    end

    test "re-prioritizes the issue in its milestone" do
      @closed_issue.update(milestone: @milestone)
      refute_predicate @closed_issue.issue_priorities, :exists?
      assert @closed_issue.reopen!
      assert new_priority = @closed_issue.issue_priorities.last,
        "reopened issue should have been reprioritized"
      assert_equal 1, new_priority.canonical_priority,
        "reopened issue should be prioritized at the top position"
    end

    test "reopens an issue with comment" do
      assert @closed_issue.closed?

      # Invoked twice, once on issue state change and once on issue comments count change
      GitHub::WebSocket.expects(:notify_issue_channel).with(@closed_issue, GitHub::WebSocket::Channels.issue(@closed_issue), anything).twice
      # Invoked once on state change
      GitHub::WebSocket.expects(:notify_issue_channel).with(@closed_issue, GitHub::WebSocket::Channels.issue_state(@closed_issue), anything).once

      @closed_issue.comment_and_open(@user, "Opening comment")

      @closed_issue.reload
      assert @closed_issue.open?
    end

    test "reopens an issue without comment" do
      assert @closed_issue.closed?

      # Invoked once on state change
      GitHub::WebSocket.expects(:notify_issue_channel).with(@closed_issue, GitHub::WebSocket::Channels.issue(@closed_issue), anything).once
      GitHub::WebSocket.expects(:notify_issue_channel).with(@closed_issue, GitHub::WebSocket::Channels.issue_state(@closed_issue), anything).once

      @closed_issue.comment_and_open(@user, "")

      @closed_issue.reload
      assert @closed_issue.open?
    end
  end

  test "cannot reopen an open issue" do
    assert @open_issue.open?
    assert !@open_issue.reopen!
    assert @open_issue.open?
    assert_includes @open_issue.errors[:state_reason], "Cannot transition to this state"
  end

  test "cant close a closed issue without specifying a reason" do
    assert @closed_issue.closed?
    refute @closed_issue.close
  end

  test "can reopen an issue closed by yourself" do
    @other_issue.close(@user)
    assert @other_issue.closed?
    assert_equal @user, @other_issue.closed_by
    @other_issue.reopen!(@user)
    assert @other_issue.open?
  end

  test "cannot reopen an issue closed by repo pusher" do
    @other_issue.close(@unauthed)
    assert @other_issue.closed?
    assert_equal @unauthed, @other_issue.closed_by
    @other_issue.reopen!(@user)
    assert @other_issue.closed?
  end

  test "assigning issue to owner" do
    assert_equal_owner @owner, @owner
    assert !@open_issue.assignee
    @open_issue.assignee = @owner
    @open_issue.save
    assert_equal @owner, @open_issue.assignee
  end

  test ".assigned_to scope finds issue by matching assignment" do
    user = create(:collaborator, repository: @private_repo)
    @open_issue.update(assignees: [user, @owner])

    assert_includes Issue.assigned_to(user), @open_issue
    assert_includes Issue.assigned_to(@owner), @open_issue
  end

  test ".assigned_to scope accepts user specified by login handle" do
    user = create(:collaborator, repository: @private_repo)
    @open_issue.update(assignees: [user, @owner])

    assert_includes Issue.assigned_to(user.display_login), @open_issue
    assert_includes Issue.assigned_to(user.display_login.to_sym), @open_issue
    assert_includes Issue.assigned_to(@owner.display_login), @open_issue
    assert_includes Issue.assigned_to(@owner.display_login.to_sym), @open_issue

    assert_raises Issue::AssigneeInvalid, "Assignee must be a User or login handle; got nil" do
      Issue.assigned_to(nil)
    end

    invalid_assignee = "idonotexist"
    assert_raises Issue::AssigneeInvalid, "Could not find assignee: %p" % invalid_assignee do
      Issue.assigned_to(invalid_assignee)
    end
  end

  test "#last_modified_at takes assignments into account" do
    user = create(:collaborator, repository: @private_repo)
    @open_issue.update(assignees: [@owner, user])

    Timecop.freeze(future = 10.minutes.from_now) do
      user.touch
      assert_in_delta future, @open_issue.last_modified_at, 1.second
    end
  end

  test "issue is touched when multiple assignments are added", feature_disabled: :disable_touch_issue_in_assignment do
    before, after = [Time.new(2017, 9, 1, 12, 34, 56), Time.new(2017, 9, 6, 12, 34, 56)]

    Timecop.freeze(before) do
      perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
        @open_issue.add_assignees(@owner)
        @open_issue.save
      end
      assert_in_delta before, @open_issue.reload.updated_at, 1.second
    end

    Timecop.freeze(after) do
      perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
        @open_issue.add_assignees(@user)
        @open_issue.save
      end

      assert_in_delta after, @open_issue.reload.updated_at, 1.second
    end
  end

  test "#unsubscribable_users excludes all assignees" do
    user = create(:collaborator, repository: @private_repo)
    @open_issue.update(assignees: [@owner, user])

    unsubscribable_users = @open_issue.unsubscribable_users([@owner, user])
    refute_includes unsubscribable_users, @owner
    refute_includes unsubscribable_users, user
  end

  test "can be locked and unlocked by the owner" do
    owner = create(:user)
    repo = create(:repository, owner: owner, admin: owner)
    issue = create(:issue, repository: repo)

    assert !issue.locked?

    collab = create(:collaborator, repository: repo)
    user   = create(:user)
    staff  = create(:staff_admin_user)

    assert issue.lock(owner)
    assert issue.locked?
    refute issue.locked_for?(owner)
    refute issue.locked_for?(collab)
    assert issue.locked_for?(staff)
    assert issue.locked_for?(user)
    assert issue.locked_for?(nil)
    assert issue.locked_for?(GitHub::NullUser.new)

    assert issue.unlock(owner)
    refute issue.locked?
    refute issue.locked_for?(owner)
    refute issue.locked_for?(collab)
    refute issue.locked_for?(staff)
    refute issue.locked_for?(user)
    refute issue.locked_for?(nil)
    refute issue.locked_for?(GitHub::NullUser.new)

    assert issue.lock(collab)
    assert issue.locked?
    refute issue.locked_for?(owner)
    refute issue.locked_for?(collab)
    assert issue.locked_for?(staff)
    assert issue.locked_for?(user)
    assert issue.locked_for?(nil)
    assert issue.locked_for?(GitHub::NullUser.new)

    assert issue.unlock(collab)
    refute issue.locked?

    refute issue.lock(user)
    refute issue.locked?
    issue.lock(owner)         # back to default
    refute issue.unlock(user)
    assert issue.locked?
    issue.unlock(owner)       # back to default

    assert issue.lock(staff)
    assert issue.locked?
    assert issue.unlock(staff)
    refute issue.locked?
  end

  test "locking an issue updates the issue updated_at" do
    old_updated_at = @issue.updated_at

    Timecop.travel(1.day.from_now) do
      assert @issue.lock(@unauthed)
    end

    assert_operator @issue.updated_at, :>, old_updated_at
  end

  test "locking an issue that is already locked does not fire another event" do
    @issue.lock(@unauthed)

    assert_difference "@issue.events.count", 0 do
      @issue.lock(@unauthed)
    end
  end

  test "unlocking an issue that was converted to a discusssion does nothing" do
    owner = create(:user)
    repo = create(:repository, owner: owner, admin: owner, has_discussions: true)
    issue = create(:issue, repository: repo)

    issue.lock(owner)
    assert issue.locked?

    discussion = create(:discussion, issue: issue, repository: repo)

    issue.unlock(owner)

    assert issue.locked?
  end

  test "unlocking an issue updates the issue updated_at" do
    @issue.lock(@unauthed)
    old_updated_at = @issue.updated_at

    Timecop.travel(1.day.from_now) do
      assert @issue.unlock(@unauthed)
    end

    assert_operator @issue.updated_at, :>, old_updated_at
  end

  test "unlocking an issue that is not locked does not fire an event" do
    assert_difference "@issue.events.count", 0 do
      @issue.unlock(@unauthed)
    end
  end

  test "can't lock issue when repo is being migrated" do
    @issue.repository.lock_for_migration

    refute @issue.lock(@unauthed)
    refute @issue.locked?
  end

  test "can't lock issue when repo has issues disabled" do
    @issue.repository.update_attribute(:has_issues, false)

    refute @issue.lock(@unauthed)
    refute @issue.locked?
  end

  test "spammy user creating an issue on a repo they do not own does not fire an event", spammy_only: true do
    assert_difference -> { GitHub.stratocaster.events("repo:#{@private_repo.id}").count }, 0 do
      @issue_with_pull = Issue.create! \
        repository: @private_repo,
        title: @open_issue.title,
        body: @open_issue.body,
        user: @open_issue.user,
        pull_request: @private_repo.comparison("master", "topic").build_pull_request(user: @spammer)
    end
  end

  test "allows commenting when unlocked" do
    owner = create(:user)
    repo = create(:repository, owner: owner, admin: owner)
    issue = create(:issue, repository: repo)
    user = issue.user

    issue.unlock(owner)
    assert !issue.locked?
    assert issue.can_comment?(user)

    comment = issue.comments.create(user: owner, body: "hey")
    comment.reload

    comment = issue.comments.create(user: user, body: "hey")
    comment.reload
  end

  test "participating in issue when creating it" do
    issue = create(:issue)

    assert_equal [issue.id], Issue.participating(issue.user).pluck(:id)
  end

  test "participating in issue when commenting" do
    issue = create(:issue)
    commenting_user = create(:user)
    issue.comments.create(user: commenting_user, body: "hey")

    assert_equal [issue.id], Issue.participating(commenting_user).pluck(:id)
  end

  test "only allows writers to comment when locked" do
    owner = create(:user)
    repo = create(:repository, owner: owner, admin: owner)
    issue = create(:issue, repository: repo)

    collab = create(:collaborator, repository: repo)
    user = create(:user)

    issue.lock(owner)
    assert issue.locked?

    assert issue.can_comment?(owner)
    assert issue.can_comment?(collab)
    refute issue.can_comment?(user)

    comment = issue.comments.create(user: owner, body: "hey")
    comment.reload

    comment = issue.comments.create(user: collab, body: "hey")
    comment.reload

    comment = issue.comments.create(user: user, body: "hey")
    assert_raises(ActiveRecord::RecordNotFound) { comment.reload }
  end

  test "only allows writer-comments to be updated when locked" do
    owner = create(:user)
    repo = create(:repository, owner: owner, admin: owner)
    issue = create(:issue, repository: repo)

    collab = create(:collaborator, repository: repo)
    user = create(:user)

    owner_comment = issue.comments.create(user: owner, body: "hey")
    owner_comment.reload

    collab_comment = issue.comments.create(user: collab, body: "hey")
    collab_comment.reload

    user_comment = issue.comments.create(user: user, body: "hey")
    user_comment.reload

    issue.lock(owner)
    assert issue.locked?

    owner_comment.update(body: "hey new")
    owner_comment.reload
    assert_equal "hey new", owner_comment.body

    collab_comment.update(body: "hey new")
    collab_comment.reload
    assert_equal "hey new", collab_comment.body

    user_comment.update(body: "hey new")
    user_comment.reload
    assert_equal "hey", user_comment.body
  end

  test "records events when locked and unlocked" do
    user = create(:user)
    repo = create(:repository, owner: user, admin: user)
    issue = create(:issue, repository: repo)
    assert !issue.locked?


    assert issue.lock(user)
    issue.reload
    event = issue.events.last
    assert_equal "locked", event.event
    assert_equal user, event.actor

    assert issue.unlock(user)
    issue.reload
    event = issue.events.last
    assert_equal "unlocked", event.event
    assert_equal user, event.actor
  end

  test "knows when it was locked" do
    owner = create(:user)
    repo = create(:repository, owner: owner, admin: owner)
    issue = create(:issue, repository: repo)

    issue.stubs(:lockable_by?).returns(true)

    assert_nil issue.locked_at

    Timecop.freeze(8.days.ago) do
      issue.lock(owner)
    end

    assert issue.locked_at < 7.days.ago

    Timecop.freeze(4.days.ago) do
      issue.unlock(owner)
      issue.lock(owner)
    end

    assert issue.locked_at < 3.days.ago
  end

  test "sets a lock reason when a valid reason is provided" do
    owner = create(:user)
    repo = create(:repository, owner: owner, admin: owner)
    issue = create(:issue, repository: repo)

    issue.lock(owner, "not a valid lock reason")
    assert !issue.locked?

    valid_reason = Issue::LOCK_REASONS.first
    issue.lock(owner, valid_reason)
    assert issue.locked?
    assert_equal valid_reason, issue.active_lock_reason
  end

  test "returns nil for active_lock_reason when the repository is archived" do
    issue = create(:issue)
    Repository.any_instance.stubs(:archived?).returns(true)

    assert issue.repository.archived?
    assert_nil issue.active_lock_reason
    assert_equal "This repository has been archived.", issue.locked_reason
  end

  test "returns nil for active_lock_reason when the repository is locked for migration" do
    issue = create(:issue)
    Repository.any_instance.stubs(:locked_on_migration?).returns(true)

    assert issue.repository.locked_on_migration?
    assert_nil issue.active_lock_reason
    assert_equal "This repository is being migrated.", issue.locked_reason
  end

  context "locked_at column" do
    test "lock update the locked_at column" do
      owner = create(:user)
      repo = create(:repository, owner: owner, admin: owner)
      issue = create(:issue, repository: repo)

      issue.lock(owner)

      assert issue.read_attribute(:locked_at)
    end

    test "unlock update the locked_at column" do
      owner = create(:user)
      repo = create(:repository, owner: owner, admin: owner)
      issue = create(:issue, repository: repo)

      issue.lock(owner)
      issue.unlock(owner)

      refute issue.read_attribute(:locked_at)
    end
  end

  test "generates events on create" do
    GitHub.context.push(actor_id: @user.id)
    issue = Issue.new(title: "wat", user: @owner, repository: @private_repo)
    issue.milestone = create(:milestone, repository: @private_repo)
    issue.labels   << create(:label, repository: issue.repository)
    issue.assignee  = @owner
    issue.save

    events = issue.events.map(&:event)
    assert_same_elements %w(milestoned labeled assigned), events
  end

  test "generates contribution timestamp based on Time.zone on create" do
    Time.use_zone "Australia/Melbourne" do
      issue = Issue.new(title: "wat", user: @owner, repository: @private_repo)
      issue.save
      assert_equal Time.zone.now.utc_offset, T.unsafe(issue).contributed_at.utc_offset
    end
  end

  test "returns local times for old issues" do
    # Goes through 48 hours so we hit at least some edge
    # case independent of the local timezone of the machine running the test
    48.times do |i|
      time = Time.utc(2014, 1, 1) + i * 3600
      issue = Issue.new(title: "wat", user: @owner, repository: @private_repo, created_at: time, contributed_at: time)
      issue.save
      issue = Issue.find(T.must(issue.id))
      assert_equal time.localtime.to_date, issue.contributed_on
      assert_equal time, issue.contribution_time
    end
  end

  test "triggers milestone event" do
    GitHub.context.push(actor_id: @owner.id)
    @open_issue.milestone = @milestone

    assert_difference "@open_issue.events.count", 1 do
      @open_issue.trigger_milestone_event
    end
  end

  context "#has_timeline_items?" do
    test "checks for timeline activity" do
      issue = create(:issue, repository: @private_repo, user: @owner)
      refute_predicate issue, :has_timeline_items?
    end

    test "returns true if event is present" do
      issue = create(:issue, repository: @private_repo, user: @owner)
      issue.assignee = @owner
      issue.save
      issue.reload
      assert_predicate issue, :has_timeline_items?
    end

    test "returns true if comment is present" do
      issue = create(:issue, repository: @private_repo, user: @owner)
      create(:issue_comment, issue: issue)
      issue.reload
      assert_predicate issue, :has_timeline_items?
    end

    test "returns true if reference exists" do
      issue = create(:issue, repository: @private_repo, user: @owner)
      issue.comments.destroy_all
      issue.record_reference_from(@open_issue, @owner, Time.now)
      issue.reload
      assert_predicate issue, :has_timeline_items?
    end

    test "returns false if issue has no timeline events" do
      issue = create(:issue, repository: @private_repo, user: @owner)
      issue.subscribe(@authed, "manual")

      assert_predicate issue, :events?
      refute_predicate issue, :has_timeline_items?
    end
  end

  context "#async_commented_on_by?" do
    test "returns true when user has commented on issue" do
      issue = create(:issue)
      user = create(:user)
      create(:issue_comment, user: user, issue: issue)

      assert issue.async_commented_on_by?(user).sync
    end

    test "returns false when user has not commented on issue" do
      issue = create(:issue)
      user = create(:user)

      refute issue.async_commented_on_by?(user).sync
    end
  end

  test "triggers label event" do
    GitHub.context.push(actor_id: @owner.id)

    assert_difference "@open_issue.events.count", 1 do
      @open_issue.trigger_label_event(create(:label, repository: @open_issue.repository))
    end
  end

  context "Avoiding duplicate label events" do
    test "doesn't trigger duplicate labeled event" do
      GitHub.context.push(actor_id: @owner.id)
      label = create(:label, name: "label1", repository: @open_issue.repository)

      assert_difference "@open_issue.events.count", 1 do
        @open_issue.trigger_label_event(label)
        @open_issue.trigger_label_event(label)
      end
    end

    test "does trigger all label events for sequential add/remove/add" do
      GitHub.context.push(actor_id: @owner.id)
      label = create(:label, name: "label1", repository: @open_issue.repository)

      assert_difference "@open_issue.events.count", 3 do
        @open_issue.trigger_label_event(label)
        @open_issue.trigger_unlabel_event(label)
        @open_issue.trigger_label_event(label)
      end
    end
  end

  test "triggers unlabeled event" do
    GitHub.context.push(actor_id: @owner.id)

    assert_difference "@labeled.events.count", 1 do
      @labeled.trigger_unlabel_event(@label)
    end
  end

  test "triggers renamed event" do
    GitHub.context.push(actor_id: @owner.id)
    title_was = @open_issue.title
    @open_issue.title = "New title"

    assert_difference "@open_issue.events.count", 1 do
      @open_issue.save
    end

    event = @open_issue.events.last
    assert_equal "renamed", event.event
    assert_equal title_was, event.title_was
    assert_equal @open_issue.title, event.title_is
  end

  test "generates an event for assignment" do
    @open_issue.assignee = @owner
    @open_issue.save

    @open_issue.assignee = @user
    @open_issue.save

    assert_equal "assigned", @open_issue.events.first.event
  end

  test "generates an event for unassignment with assignees=" do
    @open_issue.repository.add_member(@user)

    user = create(:user)
    GitHub.context.push(actor_id: user.id)
    @open_issue.assignees = [@owner]
    @open_issue.save

    @open_issue.assignees = [@user]
    @open_issue.save

    event = @open_issue.events.find { |e| e.event == "unassigned" }
    assert_equal "unassigned", event.event
    assert_equal user,         event.subject
  end

  test "can only add associated repo milestones" do
    milestone = create(:milestone, repository: create(:repository))
    issue = Issue.new(repository: create(:repository), milestone: milestone)
    issue.save
    assert issue.errors[:milestone].any?
  end

  test "assigning milestones updates the milestone counts" do
    assert_equal 0, @milestone.open_issue_count
    assert_equal 0, @milestone.closed_issue_count
    @open_issue.milestone = @milestone
    @open_issue.save!
    assert_equal 1, @milestone.open_issue_count
    @closed_issue.milestone = @milestone
    assert_equal 1, @milestone.open_issue_count
  end

  context "visible_cards_for" do
    test "finds the correct project cards associated with an issue" do
      project = create(:project, owner: @open_issue.repository)
      column = create(:project_column, project: project)
      card = create(:project_card, content: @open_issue, column: column)

      another_project = create(:project, owner: @open_issue.repository)
      another_card = create(:project_card, content: @open_issue, project: another_project)

      create(:project_card, content: @closed_issue, column: column)

      assert_same_elements [card, another_card], @open_issue.visible_cards_for(@owner)
    end

    test "excludes cards in repositories that the viewer can't see" do
      project = create(:project, owner: @open_issue.repository)
      column = create(:project_column, project: project)
      create(:project_card, content: @open_issue, column: column)

      assert_empty @open_issue.visible_cards_for(create(:user))
    end

    test "excludes cards in org projects that the user does not have read access to" do
      org = create(:organization)
      org_member = create(:user, login: "org-member")
      org.add_member(org_member)

      org_repo = create(:repository, owner: org)
      issue = create(:issue, repository: org_repo)

      read_access_project = create(:project, owner: org)
      read_access_column = create(:project_column, project: read_access_project)
      read_access_card = create(:project_card, content: issue, column: read_access_column)
      read_access_project.update_org_permission(:read)

      no_access_project = create(:project, owner: org)
      no_access_column = create(:project_column, project: no_access_project)
      create(:project_card, content: issue, column: no_access_column)
      no_access_project.update_org_permission(nil)

      assert_same_elements [read_access_card], issue.visible_cards_for(org_member)
    end

    test "includes cards in public org projects for logged out users", skip_with_all_emus: true do
      org = create(:organization)
      org_repo = create(:repository, owner: org)
      issue = create(:issue, repository: org_repo)

      public_project = create(:project, owner: org, public: true)
      public_column = create(:project_column, project: public_project)
      public_card = create(:project_card, content: issue, column: public_column)

      private_project = create(:project, owner: org, public: false)
      private_column = create(:project_column, project: private_project)
      create(:project_card, content: issue, column: private_column)

      assert_same_elements [public_card], issue.visible_cards_for(nil)
    end

    test "includes cards in user projects for a viewer" do
      repo = create(:repository, owner: @owner, force_user_owned: true)
      issue = create(:issue, repository: repo, user: @owner)
      user_project = create(:project, owner: @owner)
      user_project_column = create(:project_column, project: user_project)
      user_project_card = create(:project_card, content: issue, column: user_project_column)

      assert_includes issue.visible_cards_for(@owner), user_project_card
    end

    test "we get expected queries if cards are present in issue" do
      project = create(:project, owner: @open_issue.repository)
      column = create(:project_column, project: project)
      card = create(:project_card, content: @open_issue, column: column)

      _, queries = log_cleaned_queries do
        assert_same_elements [card], @open_issue.visible_cards_for(@owner)
      end

      assert_equal 2, identify_queries(queries).count { |q| q == "configuration_entries" }
      assert_equal 3, identify_queries(queries).count { |q| q == "project_cards" }
      assert_equal 1, identify_queries(queries).count { |q| q == "repositories" }
      assert_equal 5, identify_queries(queries).count { |q| q == "projects" }
    end

    test "we skip unrequired queries if cards are not present in issue" do
      _, queries = log_cleaned_queries do
        assert_equal [], @open_issue.visible_cards_for(@owner)
      end

      assert_equal 0, identify_queries(queries).count { |q| q == "configuration_entries" }
      assert_equal 0, identify_queries(queries).count { |q| q == "project_cards" }
      assert_equal 0, identify_queries(queries).count { |q| q == "repositories" }
      assert_equal 1, identify_queries(queries).count { |q| q == "projects" }
    end
  end

  # This can happen when you assign someone to an issue then revoke their
  # collaborator grant for the repo.
  test "removes assignee if they become a non-collaborator" do
    owner = create(:user)
    repo = create(:private_repository, owner: owner, admin: owner, force_user_owned: true)
    user = create(:collaborator, repository: repo)
    issue = create(:issue, repository: repo, user: owner)
    assert !issue.assignee
    issue.update_attribute("assignee", user)
    assert_equal user, issue.assignee

    only = [RemoveUserFromRepoCleanupJob]
    perform_enqueued_jobs(only: only) do
      repo.remove_member(user)
    end

    issue.reload
    refute repo.members.include?(user)
    issue.close!
    assert issue.closed?
    assert_nil issue.assignee
  end

  test "issue creator is automatically subscribed", feature_disabled: :notifyd_issue_watch_activity_notify do
    assert @open_issue.subscribed?(@open_issue.user)
  end

  test "automatically subscribes assignees", feature_disabled: :notifyd_issue_watch_activity_notify do
    assert !@open_issue.subscribed?(@authed)
    perform_enqueued_jobs only: SubscribeAndNotifyJob do
      @open_issue.update_attribute :assignee, @authed
    end
    assert @open_issue.subscribed?(@authed)
  end

  test "does not subscribe assigner", feature_disabled: :notifyd_issue_watch_activity_notify do
    @open_issue.unsubscribe(@owner)
    assert !@open_issue.subscribed?(@owner)

    GitHub.context.push(actor_id: @owner.id)
    perform_enqueued_jobs only: SubscribeAndNotifyJob do
      @open_issue.update_attribute :assignee, @authed
    end
    assert !@open_issue.subscribed?(@owner)
  end

  test "subscribes an authed user to the issue", feature_disabled: :notifyd_issue_watch_activity_notify do
    assert !@open_issue.subscribed?(@authed)
    assert @open_issue.subscribe(@authed, "manual")
    assert @open_issue.subscribed?(@authed)
    status = @open_issue.subscription_status(@authed).value
    assert status.valid?
    assert_equal "manual", status.reason
  end

  test "unsubscribes author from the issue", feature_disabled: :notifyd_issue_watch_activity_notify do
    assert @open_issue.subscribed?(@owner)
    @open_issue.unsubscribe(@owner)
    assert !@open_issue.subscribed?(@owner)
  end

  test "does not subscribe unauthed user to the issue", feature_disabled: :notifyd_issue_watch_activity_notify do
    assert !@open_issue.subscribed?(@unauthed)
    assert !@open_issue.subscribe(@unauthed)
    assert !@open_issue.subscribed?(@unauthed)
  end

  unless GitHub.enterprise?
    test "does not subscribe mentioned users to an issue opened by a spammy user", skip_with_all_emus: true, feature_disabled: :notifyd_issue_watch_activity_notify do
      assert_performed_with job: SubscribeAndNotifyJob do
        issue = Issue.create!(
          repository: @private_repo,
          title: @open_issue_spam.title,
          body: "Hey @authed! Lookit this!",
          user: @spammer,
        )
        refute issue.subscribed?(@authed)
      end
    end

    test "subscribes mentioned users to an issue opened by a ghost user", skip_with_all_emus: true, feature_disabled: :notifyd_issue_watch_activity_notify do
      assert_performed_with job: SubscribeAndNotifyJob do
        ghost = User.create_ghost
        issue = Issue.create!(
          repository: @private_repo,
          title: @open_issue_spam.title,
          body: "Hey @#{@authed.display_login}! Look at this!",
          user: ghost,
        )
        assert issue.subscribed?(@authed)
      end
    end

    test "does not subscribe when the author is a blocked user", feature_disabled: :notifyd_issue_watch_activity_notify do
      assert_performed_with job: SubscribeAndNotifyJob do
        blocking_user = create(:user)
        blocked_user = create(:user)
        issue = create(:issue,
          repository: @private_repo,
          title: "Blocked user test",
          body: "Hey @#{blocking_user.display_login}, you smell!",
          user: blocked_user,
        )
        refute issue.subscribed?(blocking_user)
      end
    end

    test "subscribes when the author is nil", feature_disabled: :notifyd_issue_watch_activity_notify do
      issue = create(:issue)
      mentionee = create(:user)
      issue.user = nil
      issue.subscribe_mentioned([mentionee], nil)
      assert issue.subscribed?(mentionee)
    end
  end

  test "finds mentioned users" do
    @open_issue.body = "what do you think? /cc @#{@owner.display_login} @#{@authed.display_login}"
    assert_equal [@owner, @authed], @open_issue.mentioned_users
  end

  test "includes unauthorized mentions but doesn't subscribe them", feature_disabled: :notifyd_issue_watch_activity_notify do
    assert !@open_issue.subscribed?(@unauthed)

    @open_issue.body = "what do you think? /cc @#{@unauthed.display_login}"
    assert_equal [@unauthed], @open_issue.mentioned_users
    @open_issue.subscribe_mentioned
    assert !@open_issue.subscribed?(@unauthed)
  end

  test "excludes enterprise managed users mentions", skip_enterprise: true, feature_disabled: :notifyd_issue_watch_activity_notify do
    emu_user = create :emu
    enterprise = emu_user.enterprise_managed_business

    if TestEnv.test_in_multitenancy_mode?
      GitHub::CurrentTenant.set(@authed.enterprise_managed_business)
    end

    @open_issue.body = "what do you think? /cc @#{@authed.display_login} @#{emu_user.display_login}"
    assert_equal [@authed], @open_issue.mentioned_users
    @open_issue.subscribe_mentioned
    assert @open_issue.subscribed?(@authed)
    refute @open_issue.subscribed?(emu_user)
  end

  test "includes enterprise managed users mentions and excludes non-EMU users", skip_enterprise: true, feature_disabled: :notifyd_issue_watch_activity_notify do
    emu_user = create :emu
    enterprise = emu_user.enterprise_managed_business

    owner = enterprise.owners.first
    other_emu_user = create(:emu, business: enterprise)

    org = create(:organization, business: enterprise, admin: owner)
    org.add_member(emu_user)
    org.add_member(other_emu_user)

    repo = create(:internal_repository, owner: org)

    issue = create(:issue,
      repository: repo,
      user: other_emu_user,
      body: "what do you think? /cc @#{@authed.display_login} @#{emu_user.display_login}"
    )

    assert_equal [emu_user], issue.mentioned_users
    issue.subscribe_mentioned
    assert issue.subscribed?(emu_user)
    refute issue.subscribed?(@authed)
  end

  test "excludes enterprise managed users mentions for different enterprises", skip_enterprise: true, feature_disabled: :notifyd_issue_watch_activity_notify do
    emu_user = create :emu
    enterprise = emu_user.enterprise_managed_business
    owner = enterprise.owners.first
    other_emu_user = create(:emu, business: enterprise)

    org = create(:organization, business: enterprise, admin: owner)
    org.add_member(emu_user)
    org.add_member(other_emu_user)

    repo = create(:internal_repository, owner: org)

    # different EMU enterprise
    other_enterprise_emu_user = create :emu
    other_enterprise = other_enterprise_emu_user.enterprise_managed_business
    refute_equal enterprise, other_enterprise

    if TestEnv.test_in_multitenancy_mode?
      GitHub::CurrentTenant.set(emu_user.enterprise_managed_business)
    end

    issue = create(:issue,
      repository: repo,
      user: other_emu_user,
      body: "what do you think? /cc @#{@authed.display_login} @#{emu_user.display_login} @#{other_enterprise_emu_user.display_login}"
    )

    assert_equal [emu_user], issue.mentioned_users
    issue.subscribe_mentioned
    assert issue.subscribed?(emu_user)
    refute issue.subscribed?(other_enterprise_emu_user)
    refute issue.subscribed?(@authed)
  end

  test "includes authorized mentions and subscribes them", feature_disabled: :notifyd_issue_watch_activity_notify do
    create(:collaborator, repository: @private_repo)
    assert !@open_issue.subscribed?(@authed)

    @open_issue.body = "what do you think? /cc @#{@authed.display_login}"
    assert_equal [@authed], @open_issue.mentioned_users
    @open_issue.subscribe_mentioned

    assert @open_issue.subscribed?(@authed)

    status = @open_issue.subscription_status(@authed).value
    assert status.valid?
    assert_equal "mention", status.reason
  end

  if GitHub.prevent_mention_spam?
    # EMUs repos are only private, mention spam filtering is only applied to public repos see mention_filter.rb
    test "limits mentioned users to #{mention_limit}", skip_with_all_emus: true do
      @issue.body = @users[0, mention_limit + 1].map { |u| "@#{u.display_login}" }.join(", ")
      assert @issue.valid?
      assert_equal mention_limit, @issue.mentioned_users.length
    end
  else
    test "does not limit mentioned users" do
      @issue.body = @users[0, mention_limit + 1].map { |u| "@#{u.display_login}" }.join(", ")
      assert @issue.valid?
      assert_equal mention_limit + 1, @issue.mentioned_users.length
    end
  end

  test "creates an issue event with author" do
    issue = create(:issue, repository: @repo)
    mentionee = create(:user)
    issue.subscribe_mentioned([mentionee], @user)
    assert issue.events.where(event: "mentioned").last.author, @user
  end

  unless GitHub.enterprise?
    context "Hydro Instrumentation" do
      include HydroTestHelpers

      # github.v1.IssueCreate is only published for public repos which do not exist in EMU mode
      test "issue create event is published to hydro", skip_with_all_emus: true do
        now = Time.now.beginning_of_day

        Timecop.freeze(now) do
          GitHub.context.push(actor_ip: "3ffe:505:2::1")
          GitHub.context.push(user_agent: "test agent")

          actor = create(:user)
          repo = create(:public_repository, owner: actor)
          issue = create :issue, :with_instrumentation, :wait_for_orchestration, user: actor, title: "Hello", body: "World", repository: repo

          message = {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            actor: Hydro::EntitySerializer.user(actor),
            repository: Hydro::EntitySerializer.repository(repo),
            repository_owner: Hydro::EntitySerializer.user(repo.owner),
            issue: Hydro::EntitySerializer.issue(issue),
            issue_creator: Hydro::EntitySerializer.user(actor),
            specimen_body: Hydro::EntitySerializer.specimen_data(issue.body),
            specimen_title: Hydro::EntitySerializer.specimen_data(issue.title),
            title: issue.title,
            body: issue.body,
          }

          with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
            assert_hydro_published(message, schema: "github.v1.IssueCreate")
          end
        end
      end

      test "instruments hydro.schemas.events_platform.v0.Tier1Event hydro event when issue is created and feature flag is enabled", skip_with_all_emus: true do
        now = Time.now.beginning_of_day

        Timecop.freeze(now) do
          with_hydro_publisher(GitHub.sync_hydro_publisher) do
            GitHub.context.push(actor_ip: "3ffe:505:2::1")
            GitHub.context.push(user_agent: "test agent")

            mock_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
            Events::Tier1EventPublisher.expects(:new_guid).returns(mock_guid).at_least_once

            last_writes = {
              mysql1: { gtid: "000-000", time: Time.now.to_i * 1000 },
              repositories: { gtid: "000-000", time: Time.now.to_i * 1000 }
            }
            DatabaseSelector::ReplicationState.expects(:current).at_least_once.returns(DatabaseSelector::ReplicationState.new)
            DatabaseSelector::ReplicationState.any_instance.expects(:to_hash).at_least_once.returns(last_writes)

            actor = create(:user)
            repository = create(:public_repository, owner: actor)

            GitHub.flipper[:events_v2_publish_tier1_event].enable(Events::ParentAsActor.repo_actor(repository.id))
            issue = create :issue, :with_instrumentation, :wait_for_orchestration, user: actor, title: "Hello", body: "World", repository: repository

            message = {
              guid: mock_guid,
              type: :EVENT_TYPE_ISSUES,
              action: :EVENT_ACTION_OPENED,
              target: {
                primary_entity: {
                  type: :ENTITY_TYPE_ISSUE,
                  id: issue.id.to_s,
                  graphql_global_relay_id: issue.global_relay_id,
                  graphql_next_global_id: issue.next_global_id,
                },
                related_entities: [{
                  type: :ENTITY_TYPE_REPOSITORY,
                  id: repository.id.to_s,
                  graphql_global_relay_id: repository.global_relay_id,
                  graphql_next_global_id: repository.next_global_id,
                }],
              },
              triggered_at: now,
              actor: {
                type: :ENTITY_TYPE_USER,
                id: actor.id.to_s,
                graphql_global_relay_id: actor.global_relay_id,
                graphql_next_global_id: actor.next_global_id,
              },
              attachment: nil,
              target_repository_id: repository.id,
              target_organization_id: repository&.organization_id,
              target_business_id: repository&.organization&.business&.id,
            }
            # ignoring the metadata compare with ignore_extra_keys:true while asserting the hydro message
            assert_hydro_published(message, schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: "events_platform.v0.Issues", ignore_extra_keys: true)

            # Testing metadata separately
            hydro_message_metadata = hydro_messages(schema: "hydro.schemas.events_platform.v0.Tier1Event").first[:metadata]
            assert_equal(false, hydro_message_metadata[:spammy_user_acting_outside_own_repos])
            assert_equal(false, hydro_message_metadata[:disabled_for_import])
            assert_equal(false, hydro_message_metadata[:otel_trace_id].blank?)

            assert_equal(2, hydro_message_metadata[:tracked_writes].length)
            mysql1_tracked_write = hydro_message_metadata[:tracked_writes].find { |write| write[:cluster_name] == "mysql1" }
            assert_not nil, mysql1_tracked_write
            assert_equal(last_writes[:mysql1][:gtid], mysql1_tracked_write[:gtid])
            assert_equal(last_writes[:mysql1][:time] / 1000, mysql1_tracked_write[:time][:seconds])
            assert_equal("mysql1", mysql1_tracked_write[:cluster_name])

            repositories_tracked_write = hydro_message_metadata[:tracked_writes].find { |write| write[:cluster_name] == "repositories" }
            assert_not nil, repositories_tracked_write
            assert_equal(last_writes[:repositories][:gtid], repositories_tracked_write[:gtid])
            assert_equal(last_writes[:repositories][:time] / 1000, repositories_tracked_write[:time][:seconds])
            assert_equal("repositories", repositories_tracked_write[:cluster_name])
          end
        end
      end

      test "instruments hydro.schemas.events_platform.v0.Tier1Event hydro event when issue is created and feature flag is disabled", skip_with_all_emus: true do
        now = Time.now.beginning_of_day

        Timecop.freeze(now) do
          with_hydro_publisher(GitHub.sync_hydro_publisher) do
            GitHub.context.push(actor_ip: "3ffe:505:2::1")
            GitHub.context.push(user_agent: "test agent")

            actor = create(:user)
            repository = create(:public_repository, owner: actor)

            GitHub.flipper[:events_v2_publish_tier1_event].disable
            _ = create :issue, :with_instrumentation, :wait_for_orchestration, user: actor, title: "Hello", body: "World", repository: repository

            assert_hydro_messages(count: 0, schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: "events_platform.v0.Issues")
          end
        end
      end

      test "instruments hydro.schemas.events_platform.v0.Tier1Event and enqueues IssueCreateEvent with common guid", skip_with_all_emus: true do
        now = Time.now.beginning_of_day

        Timecop.freeze(now) do
          with_hydro_publisher(GitHub.sync_hydro_publisher) do
            GitHub.context.push(actor_ip: "3ffe:505:2::1")
            GitHub.context.push(user_agent: "test agent")

            mock_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
            Events::Tier1EventPublisher.expects(:new_guid).returns(mock_guid).at_least_once

            last_writes = {
              mysql1: { gtid: "000-000", time: Time.now.to_i * 1000 },
              repositories: { gtid: "000-000", time: Time.now.to_i * 1000 }
            }
            DatabaseSelector::ReplicationState.expects(:current).at_least_once.returns(DatabaseSelector::ReplicationState.new)
            DatabaseSelector::ReplicationState.any_instance.expects(:to_hash).at_least_once.returns(last_writes)

            actor = create(:user)
            repository = create(:public_repository, owner: actor)

            GitHub.flipper[:events_v2_publish_tier1_event].enable(Events::ParentAsActor.repo_actor(repository.id))

            mock_issue_id = 6
            Issue.any_instance.expects(:id).returns(mock_issue_id).at_least_once
            Hook::Event::IssuesEvent.expects(:queue).with(
              action: :opened,
              issue_id: mock_issue_id,
              actor_id: actor.id,
              triggered_at: now,
              event_guid: mock_guid,
            )

            issue = create :issue, :with_instrumentation, :wait_for_orchestration, user: actor, title: "Hello", body: "World", repository: repository

            message = {
              guid: mock_guid,
              type: :EVENT_TYPE_ISSUES,
              action: :EVENT_ACTION_OPENED,
            }

            # ignoring the metadata compare with ignore_extra_keys:true while asserting the hydro message
            assert_hydro_published(message, schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: "events_platform.v0.Issues", ignore_extra_keys: true)
          end
        end
      end

      test "Issue create publishes github.platform_health.v1.UserGeneratedContent" do
        now = Time.now.beginning_of_day

        Timecop.freeze(now) do
          GitHub.context.push(actor_ip: "3ffe:505:2::1")
          GitHub.context.push(user_agent: "test agent")

          actor = create(:user)
          repo = create :repository, owner: actor
          issue = create :issue, :with_instrumentation, :wait_for_orchestration, user: actor, title: "Hello", body: "World", repository: repo

          message = {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            spamurai_form_signals: nil,
            action_type: :CREATE,
            content_type: :ISSUE,
            actor: Hydro::EntitySerializer.user(actor),
            original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.IssueCreate"),
            content_database_id: issue.id,
            content_global_relay_id: issue.global_relay_id,
            content_created_at: issue.created_at,
            content_updated_at: issue.updated_at,
            title: Hydro::EntitySerializer.specimen_data(issue.title),
            content: Hydro::EntitySerializer.specimen_data(issue.body),
            parent_content_author: nil,
            parent_content_database_id: nil,
            parent_content_global_relay_id: nil,
            parent_content_created_at: nil,
            parent_content_updated_at: nil,
            owner: Hydro::EntitySerializer.user(repo.owner),
            repository: Hydro::EntitySerializer.repository(repo),
            content_visibility: TestEnv.test_with_all_emus? ? :INTERNAL : :PUBLIC,
          }

          with_hydro_publisher(GitHub.user_generated_content_hydro_publisher) do
            assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
          end
        end
      end

      # github.v1.IssueCreate is only published for public repos which do not exist in EMU mode
      test "issue created event is published to hydro", skip_with_all_emus: true do
        now = Time.now.beginning_of_day

        Timecop.freeze(now) do
          GitHub.context.push(actor_ip: "3ffe:505:2::1")
          GitHub.context.push(user_agent: "test agent")

          actor = create(:user)
          repo = create(:public_repository, owner: actor)
          issue = create :issue, :with_instrumentation, :wait_for_orchestration, user: actor, title: "Hello", body: "World", repository: repo

          message = {
            repository: Hydro::EntitySerializer.repository_domain(repo),
            actor: Hydro::EntitySerializer.user_domain(actor),
            issue: Hydro::EntitySerializer.issue_domain(issue),
            repository_owner: Hydro::EntitySerializer.user_domain(repo.owner),
          }

          with_hydro_publisher(GitHub.low_latency_hydro_publisher) do
            assert_hydro_published(message, schema: "github.domain_events.v0.IssueCreated")
          end
        end
      end

      test "issue close event is published to hydro" do
        actor = create(:user)
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create(:public_repository, owner: org)
        issue = create :issue, :with_instrumentation, :wait_for_orchestration, user: actor, title: "Hello", body: "World", repository: repo
        issue.close(actor)
        expected_hydro_payload = {
          actor: Hydro::EntitySerializer.user(actor),
          issue: Hydro::EntitySerializer.issue(issue),
          repository: Hydro::EntitySerializer.repository(repo),
          repository_owner: Hydro::EntitySerializer.user(repo.owner),
          issue_creator: Hydro::EntitySerializer.user(issue.user),
        }
        assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueClose")
      end

      test "issue converted to discussion event is published to hydro" do
        owner = create(:user)
        repo = create(:repository, owner: owner, admin: owner, has_discussions: true)
        issue = create(:issue, :with_instrumentation, :wait_for_orchestration, repository: repo, user: owner)
        discussion = create(:discussion, repository: repo)

        IssueEvent.create(
          issue: issue,
          event: "converted_to_discussion",
          actor_id: owner.id,
          subject: discussion,
        )
        expected_hydro_payload = {
          actor: Hydro::EntitySerializer.user(owner),
          issue: Hydro::EntitySerializer.issue(issue),
          repository: Hydro::EntitySerializer.repository(repo),
        }
        assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueConvertedToDiscussion")
      end

      test "issue reopen event is published to hydro" do
        actor = create(:user)
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create(:public_repository, owner: org)
        issue = create :issue, :with_instrumentation, :wait_for_orchestration, user: actor, title: "Hello", body: "World", repository: repo
        issue.close(actor)
        issue.reopen!(actor)
        expected_hydro_payload = {
          actor: Hydro::EntitySerializer.user(actor),
          issue: Hydro::EntitySerializer.issue(issue),
          repository: Hydro::EntitySerializer.repository(repo),
          repository_owner: Hydro::EntitySerializer.user(repo.owner),
        }
        assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueReopen")
      end

      test "issue reopen event is not published to hydro if it's a pull request" do
        actor = create(:user)
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create(:public_repository, owner: org)
        pr = create :pull_request, :disable_disk_access, repository: repo
        pr.close(actor)
        pr.open(actor)
        refute_hydro_messages(schema: "github.v1.IssueReopen")
      end

      test "publishes an issue update milestone event to hydro when setting a milestone for the first time" do
        GitHub.context.push(actor_id: @user.id)
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create(:public_repository, owner: org)
        milestone = create :milestone, repository: repo, title: "Beta Release 0.5"
        issue = create :issue, :with_instrumentation, :wait_for_orchestration, title: "Hello", body: "World", repository: repo

        Timecop.freeze(Time.now) do
          issue.update!(milestone: milestone)

          expected_hydro_payload = {
            actor: Hydro::EntitySerializer.user(@user),
            repository: Hydro::EntitySerializer.repository(repo),
            milestone: Hydro::EntitySerializer.milestone(milestone),
            issue: Hydro::EntitySerializer.issue(issue),
            pull_request: nil,
            action: "issue.events.milestoned"
          }
          assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueUpdateMilestone", count: 1)
        end
      end

      test "publishes exactly one issue update milestone event to hydro when switching to a different milestone" do
        GitHub.context.push(actor_id: @user.id)
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create(:public_repository, owner: org)
        milestone = create :milestone, repository: repo, title: "Beta Release 0.5"
        milestone2 = create :milestone, repository: repo, title: "Beta Release 0.6"
        issue = create :issue, :with_instrumentation, :wait_for_orchestration, title: "Hello", body: "World", repository: repo, milestone: milestone
        reset_hydro

        Timecop.freeze(Time.now) do
          issue.update!(milestone: milestone2)

          expected_hydro_payload = {
            actor: Hydro::EntitySerializer.user(@user),
            repository: Hydro::EntitySerializer.repository(repo),
            milestone: Hydro::EntitySerializer.milestone(milestone2),
            issue: Hydro::EntitySerializer.issue(issue),
            pull_request: nil,
            action: "issue.events.milestoned"
          }
          assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueUpdateMilestone", count: 1)

          # Assert that exactly one IssueUpdateMilestone event is published, regardless of payload.
          # This tests against publishing a superfluous milestone:nil event when changing from one milestone to another.
          assert_hydro_messages(schema: "github.v1.IssueUpdateMilestone", count: 1)
        end
      end

      test "publishes an issue update milestone event to hydro when clearing the milestone (demilestoned)" do
        GitHub.context.push(actor_id: @user.id)
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create(:public_repository, owner: org)
        milestone = create :milestone, repository: repo, title: "Beta Release 0.5"
        issue = create :issue, :with_instrumentation, :wait_for_orchestration, title: "Hello", body: "World", repository: repo, milestone: milestone

        Timecop.freeze(Time.now) do
          issue.update!(milestone: nil)

          expected_hydro_payload = {
            actor: Hydro::EntitySerializer.user(@user),
            repository: Hydro::EntitySerializer.repository(repo),
            milestone: nil,
            issue: Hydro::EntitySerializer.issue(issue),
            pull_request: nil,
            action: "issue.events.demilestoned"
          }
          assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueUpdateMilestone", count: 1)
        end
      end

      test "publishes an issue update milestone event to hydro when setting a milestone for pull requests" do
        GitHub.context.push(actor_id: @user.id)
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create(:public_repository, owner: org)
        milestone = create :milestone, repository: repo, title: "Beta Release 0.5"
        pr = create :pull_request, :disable_disk_access, repository: repo

        Timecop.freeze(Time.now) do
          pr.issue.update!(milestone: milestone)

          expected_hydro_payload = {
            actor: Hydro::EntitySerializer.user(@user),
            repository: Hydro::EntitySerializer.repository(repo),
            milestone: Hydro::EntitySerializer.milestone(milestone),
            issue: Hydro::EntitySerializer.issue(pr.issue),
            pull_request: Hydro::EntitySerializer.pull_request(pr),
            action: "issue.events.milestoned"
          }
          assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueUpdateMilestone", count: 1)
        end
      end
    end

    ## Issue Type
    test "publishes an issue update issue type event to hydro when setting a issue type for the first time" do
      GitHub.flipper[:issue_types].enable
      GitHub.context.push(actor_id: @user.id)
      org = create(:organization, plan: GitHub::Plan.business_plus)
      repo = create(:repository, owner: org)
      issue_type = org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])
      issue = create(:issue, :with_instrumentation, :wait_for_orchestration, title: "Hello", body: "World", repository: repo)

      Timecop.freeze(Time.now) do
        issue.update!(issue_type: issue_type)

        expected_hydro_payload = {
          actor: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(repo),
          issue_type: Hydro::EntitySerializer.issue_type(issue_type),
          issue: Hydro::EntitySerializer.issue(issue),
          action: "issue.typed"
        }
        assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueUpdateIssueType", count: 1)
      end
    end

    test "publishes exactly one issue update issue type event to hydro when switching to a different issue type" do
      GitHub.flipper[:issue_types].enable
      GitHub.context.push(actor_id: @user.id)
      org = create(:organization, plan: GitHub::Plan.business_plus)
      repo = create(:repository, owner: org)

      issue_type = org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])
      issue_type2 = org.issue_types.find_by(name: IssueType::DEFAULTS.second[:name])
      issue = create(:issue, :with_instrumentation, :wait_for_orchestration, title: "Hello", body: "World", repository: repo, issue_type: issue_type)
      reset_hydro

      Timecop.freeze(Time.now) do
        issue.update!(issue_type: issue_type2)

        expected_hydro_payload = {
          actor: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(repo),
          issue_type: Hydro::EntitySerializer.issue_type(issue_type2),
          issue: Hydro::EntitySerializer.issue(issue),
          action: "issue.typed"
        }
        assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueUpdateIssueType", count: 1)

        # Assert that exactly one IssueUpdateIssueType event is published, regardless of payload.
        # This tests against publishing a superfluous issue_type:nil event when changing from one issue_type to another.
        assert_hydro_messages(schema: "github.v1.IssueUpdateIssueType", count: 1)
      end
    end

    test "publishes an issue update issue type event to hydro when clearing the type (untyped)" do
      GitHub.flipper[:issue_types].enable
      GitHub.context.push(actor_id: @user.id)
      org = create(:organization, plan: GitHub::Plan.business_plus)
      repo = create(:repository, owner: org)
      issue_type = org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])

      issue = create(:issue, :with_instrumentation, :wait_for_orchestration, title: "Hello", body: "World", repository: repo, issue_type: issue_type)

      Timecop.freeze(Time.now) do
        issue.update!(issue_type: nil)

        expected_hydro_payload = {
          actor: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(repo),
          issue_type: Hydro::EntitySerializer.issue_type(issue_type),
          issue: Hydro::EntitySerializer.issue(issue),
          action: "issue.untyped"
        }
        assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueUpdateIssueType", count: 1)
      end
    end

    ## Assignee
    test "publishes an issue update assignee event to hydro when setting assignees for the first time" do
      GitHub.context.push(actor_id: @user.id)

      Timecop.freeze(Time.now) do
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create :repository, owner: org
        create(:collaborator, collaborator: @user, repository: repo)
        issue = create :issue, :with_instrumentation, :wait_for_orchestration, title: "Hello", body: "World", repository: repo
        issue.update!(assignees: [@user])

        expected_hydro_payload = {
          actor: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(repo),
          assignees: Hydro::EntitySerializer.users([@user]),
          issue: Hydro::EntitySerializer.issue(issue),
          pull_request: nil,
          action: "issue.events.assigned"
        }
        assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueUpdateAssignee", count: 1)
      end
    end

    test "publishes update assignee event to hydro when changing assignees" do
      Timecop.freeze(Time.now) do
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create(:public_repository, owner: org)
        create(:collaborator, collaborator: @user, repository: repo)
        new_user = create(:collaborator, repository: repo)

        issue = create :issue, :with_instrumentation, :wait_for_orchestration, title: "Hello", body: "World", repository: repo, assignees: [@user]

        reset_hydro

        issue.update(assignees: [new_user])

        expected_hydro_payload = {
          actor: Hydro::EntitySerializer.user(new_user),
          repository: Hydro::EntitySerializer.repository(repo),
          assignees: Hydro::EntitySerializer.users([new_user]),
          issue: Hydro::EntitySerializer.issue(issue),
          pull_request: nil,
          action: "issue.events.assigned"
        }
        assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueUpdateAssignee", count: 1)
      end
    end

    test "publishes an issue update assignees event to hydro when unassigning" do
      GitHub.context.push(actor_id: @user.id)

      Timecop.freeze(Time.now) do
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create :repository, owner: org
        create(:collaborator, collaborator: @user, repository: repo)
        issue = create :issue, :with_instrumentation, :wait_for_orchestration, title: "Hello", body: "World", repository: repo, assignees: [@user]
        issue.update!(assignees: [])

        expected_hydro_payload = {
          actor: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(repo),
          assignees: [],
          issue: Hydro::EntitySerializer.issue(issue),
          pull_request: nil,
          action: "issue.events.unassigned"
        }
        assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueUpdateAssignee", count: 1)
      end
    end

    test "publishes an issue update assignee event to hydro when setting assignees for pull requests" do
      GitHub.context.push(actor_id: @user.id)

      Timecop.freeze(Time.now) do
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create :repository, owner: org
        create(:collaborator, collaborator: @user, repository: repo)
        pr = create :pull_request, :disable_disk_access, repository: repo
        pr.issue.update!(assignees: [@user])

        expected_hydro_payload = {
          actor: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(repo),
          assignees: Hydro::EntitySerializer.users([@user]),
          issue: Hydro::EntitySerializer.issue(pr.issue),
          pull_request: Hydro::EntitySerializer.pull_request(pr),
          action: "issue.events.assigned"
        }
        assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueUpdateAssignee", count: 1)
      end
    end

    test "publishes an issue update label event to hydro when setting a label for the first time" do
      GitHub.context.push(actor_id: @user.id)

      Timecop.freeze(Time.now) do
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create :repository, owner: org
        issue = create :issue, :with_instrumentation, :wait_for_orchestration, title: "Hello", body: "World", repository: repo
        help_wanted_label = create(:label, name: Labelable::HELP_WANTED_NAME, repository: issue.repository)
        issue.add_labels([help_wanted_label])

        expected_hydro_payload = {
          actor: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(repo),
          repository_owner: Hydro::EntitySerializer.user(repo.owner),
          labels: Hydro::EntitySerializer.labels([help_wanted_label]),
          issue: Hydro::EntitySerializer.issue(issue),
          pull_request: nil,
          action: "issue.events.labeled"
        }

        assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueUpdateLabel", count: 1)
      end
    end

    test "publishes an issue update label event to hydro when clearing the label (unlabeled)" do
      GitHub.context.push(actor_id: @user.id)

      Timecop.freeze(Time.now) do
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create(:public_repository, owner: org)
        some_label = create(:label, name: "some label", repository: repo)
        issue = create :issue, :with_instrumentation, :wait_for_orchestration, title: "Hello", body: "World", repository: repo, labels: [some_label]
        reset_hydro
        issue.delete_labels([some_label])

        expected_hydro_payload = {
          actor: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(repo),
          repository_owner: Hydro::EntitySerializer.user(repo.owner),
          labels: [],
          issue: Hydro::EntitySerializer.issue(issue),
          pull_request: nil,
          action: "issue.events.unlabeled"
        }
        assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueUpdateLabel", count: 1)
      end
    end

    test "publishes an issue update label event to hydro when setting a label for pull requests" do
      GitHub.context.push(actor_id: @user.id)

      Timecop.freeze(Time.now) do
        org = create(:organization, plan: GitHub::Plan.business_plus)
        repo = create(:public_repository, owner: org)
        pr = create :pull_request, :disable_disk_access, repository: repo
        some_label = create(:label, name: "some label", repository: repo)
        reset_hydro
        pr.issue.add_labels([some_label])

        expected_hydro_payload = {
          actor: Hydro::EntitySerializer.user(@user),
          repository: Hydro::EntitySerializer.repository(repo),
          repository_owner: Hydro::EntitySerializer.user(repo.owner),
          labels: Hydro::EntitySerializer.labels([some_label]),
          issue: Hydro::EntitySerializer.issue(pr.issue),
          pull_request: Hydro::EntitySerializer.pull_request(pr),
          action: "issue.events.labeled"
        }
        assert_hydro_published(expected_hydro_payload, schema: "github.v1.IssueUpdateLabel", count: 1)
      end
    end
  end

  test "instruments issue.create when opening an issue" do
    event_guid = "9e83ccb0-54bb-11ef-8355-d2519c14d59c"
    SimpleUUID::UUID.any_instance.expects(:to_guid).once.returns(event_guid)
    events = subscribe "issue.create"
    issue = perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      Issue.create! \
      repository: @private_repo,
      title: @open_issue.title,
      body: @open_issue.body,
      user: @open_issue.user
    end
    expected_payload = {
      repo: @private_repo.name_with_display_owner,
      repo_id: @private_repo.id,
      public_repo: @private_repo.public?,
      issue_id: issue.id,
      user: @open_issue.user.display_login,
      user_id: @open_issue.user_id,
      task_list: false,
      spammy: false,
      allowed: true,
      org: nil,
      business: nil,
      event_guid: event_guid,
    }.merge(issue.event_analytics_payload)

    assert event = events.pop, "expected an instrumentation event"
    assert_equal expected_payload, event.payload
  end

  test "instruments issue.create when opening an issue by a spammy user on non-owned repo", spammy_only: true do
    event_guid = "9e83ccb0-54bb-11ef-8355-d2519c14d59c"
    SimpleUUID::UUID.any_instance.expects(:to_guid).once.returns(event_guid)
    events = subscribe "issue.create"
    issue = perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      Issue.create! \
        repository: @private_repo,
        title: @open_issue_spam.title,
        body: @open_issue_spam.body,
        user: @spammer
    end
    expected_payload = {
      repo: @private_repo.name_with_display_owner,
      repo_id: @private_repo.id,
      public_repo: @private_repo.public?,
      issue_id: issue.id,
      user: @spammer.display_login,
      user_id: @spammer.id,
      task_list: false,
      spammy: true,
      allowed: false,
      org: nil,
      business: nil,
      event_guid: event_guid,
    }.merge(issue.event_analytics_payload)

    assert event = events.pop, "expected an instrumentation event"
    assert_equal expected_payload, event.payload
  end unless GitHub.enterprise?

  test "instruments issue.create when opening an issue by a spammy user on their own repo", spammy_only: true do
    events = subscribe "issue.create"
    event_guid = "9e83ccb0-54bb-11ef-8355-d2519c14d59c"
    SimpleUUID::UUID.any_instance.expects(:to_guid).once.returns(event_guid)
    issue = perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      Issue.create! \
        repository: @spammy_repo,
        title: @spammy_open_issue.title,
        body: @spammy_open_issue.body,
        user: @spammer
    end
    expected_payload = {
      repo: @spammy_repo.name_with_display_owner,
      repo_id: @spammy_repo.id,
      public_repo: @spammy_repo.public?,
      issue_id: issue.id,
      user: @spammer.display_login,
      user_id: @spammer.id,
      task_list: false,
      spammy: true,
      allowed: true,
      org: nil,
      business: nil,
      event_guid: event_guid,
    }.merge(issue.event_analytics_payload)

    assert event = events.pop, "expected an instrumentation event"
    assert_equal expected_payload, event.payload
  end unless GitHub.enterprise?

  test "instruments issue.create with issue_template data for yaml issue form" do
    issue = build :issue, repository: @private_repo_with_templates, user: @owner
    issue.body_template_name = "cats.yml"

    perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      issue.save!
    end

    expected_hydro_payload = {
      actor: Hydro::EntitySerializer.user(issue.user),
      issue: Hydro::EntitySerializer.issue(issue),
      issue_creator: Hydro::EntitySerializer.user(issue.user),
      repository: Hydro::EntitySerializer.repository(issue.repository),
      repository_owner: Hydro::EntitySerializer.user(issue.repository.owner),
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      issue_template: Hydro::EntitySerializer.issue_template(issue.template),
    }

    assert_hydro_published(
      expected_hydro_payload,
      schema: "github.v1.IssueCreateTemplate",
    )

    assert_hydro_messages(count: 1, schema: "github.v1.IssueCreateTemplate")
    hydro_payload = hydro_messages(schema: "github.v1.IssueCreateTemplate").first
    assert_equal(true, hydro_payload[:issue_template][:project])
    assert_equal(true, hydro_payload[:issue_template][:is_issue_form])
    assert_equal(1, hydro_payload[:issue_template][:project_count])
    assert_equal(true, hydro_payload[:issue_template][:issue_type])
  end

  test "instruments issue.create with issue_template data for markdown issue template" do
    issue = build :issue, repository: @private_repo_with_templates, user: @owner
    issue.body_template_name = "bug.md"

    perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      issue.save!
    end

    expected_hydro_payload = {
      actor: Hydro::EntitySerializer.user(issue.user),
      issue: Hydro::EntitySerializer.issue(issue),
      issue_creator: Hydro::EntitySerializer.user(issue.user),
      repository: Hydro::EntitySerializer.repository(issue.repository),
      repository_owner: Hydro::EntitySerializer.user(issue.repository.owner),
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      issue_template: Hydro::EntitySerializer.issue_template(issue.template),
    }

    assert_hydro_published(
      expected_hydro_payload,
      schema: "github.v1.IssueCreateTemplate",
    )

    assert_hydro_messages(count: 1, schema: "github.v1.IssueCreateTemplate")
    hydro_payload = hydro_messages(schema: "github.v1.IssueCreateTemplate").first
    assert_equal(false, hydro_payload[:issue_template][:project])
    assert_equal(false, hydro_payload[:issue_template][:is_issue_form])
    assert_equal(0, hydro_payload[:issue_template][:project_count])
    assert_equal(true, hydro_payload[:issue_template][:issue_type])
  end

  test "instruments issue.create when opening an issue with issue type" do
    GitHub.flipper[:issue_types].enable
    issue = build :issue, repository: @private_repo_with_templates, user: @owner
    issue.issue_type = @issue_type

    perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      issue.save!
    end

    expected_hydro_payload = {
      actor: Hydro::EntitySerializer.user(issue.user),
      issue: Hydro::EntitySerializer.issue(issue),
      issue_creator: Hydro::EntitySerializer.user(issue.user),
      repository: Hydro::EntitySerializer.repository(issue.repository),
      repository_owner: Hydro::EntitySerializer.user(issue.repository.owner),
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      issue_type: Hydro::EntitySerializer.issue_type(@issue_type),
    }

    assert_hydro_published(
      expected_hydro_payload,
      schema: "github.v1.IssueCreateTemplate",
    )

    assert_hydro_messages(count: 1, schema: "github.v1.IssueCreateTemplate")
  end

  test "triggering an issue opened event" do
    issue = perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      Issue.create! repository: @private_repo,
        title: @open_issue.title,
        body: @open_issue.body,
        user: @open_issue.user
    end

    assert_enqueued_with job: ProcessEventJob, args: ["IssuesEvent", [:opened, issue.id, @open_issue.user.id]]
  end

  test "triggers a PullRequestEvent instead of IssuesEvent on open if pull_request?" do
    pr = perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      Issue.create!(repository: @private_repo,
                       title: @open_issue.title,
                       body: @open_issue.body,
                       user: @open_issue.user,
                       pull_request: @private_repo.comparison("master", "topic-rebased-on-master").build_pull_request(user: @open_issue.user),
                      ).pull_request
    end

    refute pr.new_record?, pr.errors.full_messages.to_sentence
    assert_enqueued_with job: ProcessEventJob, args: ["PullRequestEvent", [:opened, pr.id, @open_issue.user.id]]
  end

  test "trigger add issue card to project event" do
    project = create(:project, owner: @open_issue.repository)
    column = create(:project_column, project: project)

    card = create(:project_card, content: @open_issue, column: column)
    events = @open_issue.events.where(event: "added_to_project")
    event = events.first
    assert_equal 1, events.count
    assert_equal project, event.subject
    assert_equal @owner, event.actor
    assert_equal card.id, event.card_id
  end

  test "doesn't trigger add event when card is pending" do
    assert_no_difference -> { IssueEvent.count } do
      create(:pending_project_card)
    end
  end

  test "trigger remove from project event" do
    User.create_ghost # TODO: Remove when https://github.com/github/github/pull/65949 ships
    project = create(:project, owner: @open_issue.repository)
    column = create(:project_column, project: project)

    card = create(:project_card, content: @open_issue, column: column)
    card.destroy
    assert event = @open_issue.events.where(event: "removed_from_project").first,
      "IssueEvent wasn't created when removed from a project"
    assert_equal project, event.subject
    assert_equal @owner, event.actor
    assert_equal card.id, event.card_id
  end

  test "doesn't trigger remove event when card is pending" do
    card = create(:pending_project_card)
    assert_no_difference -> { IssueEvent.count } do
      card.destroy
    end
  end

  test "trigger moved within project event without automation" do
    project = create(:project, owner: @open_issue.repository)
    column1 = create(:project_column, project: project, name: "column1")
    column2 = create(:project_column, project: project, name: "column2")

    card1 = create(:project_card, content: @open_issue, column: column1)
    column1.prioritize_card!(card1)
    card1.reload
    column2.prioritize_card!(card1)

    event = @open_issue.events.where(event: "moved_columns_in_project").first
    assert_equal project, event.subject
    assert_equal @owner, event.actor
    assert_equal "column1", event.previous_column_name
    assert_equal "column2", event.column_name
    assert_nil event.issue_event_detail.performed_by_project_workflow_action_id, "Event detail should have no action ID"
    refute_predicate event, :automated?, "Event should be shown as not automated"

  end

  test "trigger moved within project event with automation" do
    GitHub.context.push(project_workflow_action_id: 1234)
    project = create(:project, owner: @open_issue.repository)
    column1 = create(:project_column, project: project, name: "column1")
    column2 = create(:project_column, project: project, name: "column2")

    card1 = create(:project_card, content: @open_issue, column: column1)
    column1.prioritize_card!(card1)
    card1.reload
    column2.prioritize_card!(card1)

    event = @open_issue.events.where(event: "moved_columns_in_project").first
    assert_equal 1234, event.issue_event_detail.performed_by_project_workflow_action_id, "Event detail should have correct action ID"
    assert_predicate event, :automated?, "Event should be shown as automated"
  end

  test "trigger create upon moving out of pending card state without automation" do
    project = create(:project, owner: @open_issue.repository)
    column = create(:project_column, project: project, name: "column")
    card = create(:pending_project_card, project: project, content: @open_issue, creator: @owner)

    column.prioritize_card!(card)

    events = @open_issue.events.where(event: "added_to_project")
    event = events.first
    assert_equal 1, events.count
    assert_equal project, event.subject
    assert_equal @owner, event.actor
    assert_equal card.id, event.card_id
    assert_nil event.issue_event_detail.performed_by_project_workflow_action_id, "Event detail should have no action ID"
    refute_predicate event, :automated?, "Event should be shown as not automated"
  end

  test "trigger create upon moving out of pending card state with automation" do
    GitHub.context.push(project_workflow_action_id: 1234)
    project = create(:project, owner: @open_issue.repository)
    column = create(:project_column, project: project, name: "column")
    card = create(:pending_project_card, project: project, content: @open_issue, creator: @owner)

    column.prioritize_card!(card)

    event = @open_issue.events.where(event: "added_to_project").first
    assert_equal 1234, event.issue_event_detail.performed_by_project_workflow_action_id, "Event should have correct action ID"
    assert_predicate event, :automated?, "Event should be shown as automated"
  end

  test "#title_or_body_changed? is true if title changes" do
    refute @open_issue.title_or_body_changed?
    @open_issue.title = "new"
    assert @open_issue.title_or_body_changed?
  end

  test "#title_changed? is false if UTF-8 title doesn't change" do
    @sc_issue = create(:issue,
      repository: @private_repo,
      user: @owner,
      title: "caractères spéciaux",
    )

    refute @sc_issue.title_changed?
    @sc_issue.title = "caractères spéciaux"
    refute @sc_issue.title_changed?
  end

  test "#title_changed? is true if UTF-8 title changes" do
    @sc_issue = create(:issue,
      repository: @private_repo,
      user: @owner,
      title: "caractères spéciaux",
    )

    refute @sc_issue.title_changed?
    @sc_issue.title = "caractères spéciaux foo"
    assert @sc_issue.title_changed?
  end

  test "#title_or_body_changed? is true if body changes" do
    issue = create :issue, body: nil
    issue.reload
    refute issue.title_or_body_changed?
    issue.body = "new"
    assert issue.title_or_body_changed?
  end

  test "#title_or_body_changed? is false if body changes from empty string to nil" do
    repo = create :private_repository, owner: @owner

    sql = <<-SQL
      INSERT INTO `issues` (`title`, `repository_id`, `compressed_body`, `state`)
      VALUES ("Some title", #{repo.id}, "", "open")
    SQL

    ApplicationRecord::Domain::IssuesPullRequests.connection.insert(Arel.sql(sql))

    issue = repo.issues.first
    assert_equal "", issue.body
    refute issue.title_or_body_changed?
    issue.assignee = @owner
    issue.save
    assert_nil issue.body
    refute issue.title_or_body_changed?
  end

  context "#instrument_update_event" do
    test "instruments when an issue's title is updated" do
      events = subscribe "issue.update"
      GitHub.context.push(actor_id: @authed.id)

      # Change to known values
      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        @open_issue.update! title: "Title", assignees: [@owner]
      end
      assert events.pop, "event expected but not instrumented"

      # No change
      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        @open_issue.update! title: "Title"
      end
      assert_nil events.pop, "an event was not expected"

      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        @open_issue.update! title: "Changed Title"
      end

      expected_payload = {
        issue_id: @open_issue.id,
        repo: @open_issue.repository.name_with_display_owner,
        repo_id: @open_issue.repository_id,
        public_repo: @open_issue.repository.public?,
        user: @open_issue.user.display_login,
        user_id: @open_issue.user_id,
        actor: @authed.display_login,
        actor_id: @authed.id,
        old_title: "Title",
        title: "Changed Title",
        assignee_ids: [@owner.id],
        spammy: false,
        allowed: true,
        org: nil,
        business: nil,
      }.merge(@open_issue.event_analytics_payload).sort

      assert event = events.pop, "not instrumented"
      assert_equal expected_payload.sort, event.payload.sort
    end

    test "instruments when an issue's body is updated" do
      events = subscribe "issue.update"
      GitHub.context.push(actor_id: @authed.id)

      # Change to known values
      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        @open_issue.update_body "Body", @owner
      end
      assert events.pop, "event expected but not instrumented"

      # No change
      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        @open_issue.update_body "Body", @owner
      end
      assert_nil events.pop, "an event was not expected"

      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        @open_issue.update_body "Changed Body", @owner
      end

      expected_payload = {
        issue_id: @open_issue.id,
        repo: @open_issue.repository.name_with_display_owner,
        repo_id: @open_issue.repository_id,
        public_repo: @open_issue.repository.public?,
        user: @open_issue.user.display_login,
        user_id: @open_issue.user_id,
        actor: @authed.display_login,
        actor_id: @authed.id,
        old_body: "Body",
        body: "Changed Body",
        assignee_ids: [@owner.id],
        spammy: false,
        allowed: true,
        org: nil,
        business: nil,
      }.merge(@open_issue.event_analytics_payload).sort

      assert event = events.pop, "not instrumented"
      assert_equal expected_payload.sort, event.payload.sort
    end

    test "does not instrument an update when neither title or body has changed" do
      events = subscribe "issue.update"
      GitHub.context.push(actor_id: @authed.id)

      assert @open_issue.open?
      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        @open_issue.close!
      end

      assert events.empty?
    end
  end

  if Interaction.enabled?
    context "interaction tracking" do
      test "tracks issue for user when issue is created" do
        interactor = create(:user)
        interaction = Interaction.for_user(interactor)
        assert_nil interaction.last_issue_at
        assert_difference "interaction.issues" do
          perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
            Issue.create! \
              repository: @private_repo,
              title: @open_issue.title,
              body: @open_issue.body,
              user: interactor
          end

          interaction.reload
        end
        assert interaction.last_issue_at?
      end

      test "does not track issue for user when issue creation fails" do
        interactor = create(:user)
        interaction = Interaction.for_user(interactor)
        assert_nil interaction.last_issue_at
        assert_no_difference "interaction.issues" do
          begin
            Issue.create! \
              repository: @private_repo,
              body: @open_issue.body,
              user: interactor
          rescue ActiveRecord::RecordInvalid => e
            assert true, "issue should not have been created"
          end

          interaction.reload
        end
        assert_nil interaction.last_issue_at
      end
    end
  end

  test "issue formatter" do
    assert_equal :markdown, Issue.new.formatter
  end

  context "ISSUE_TEMPLATE.md" do
    test "body_template returns ISSUE_TEMPLATE content when one is found" do
      example_repo :magic_config_files, @repo

      assert_equal "Please describe your issue.\n", @issue.body_template
    end

    test "body_template finds ISSUE_TEMPLATE content in .github/" do
      example_repo :dot_github, @repo

      assert_equal "Please describe your bug:\n", @issue.body_template
    end

    test "body_template follows symlinks .github/" do
      example_repo :dotgithub_w_symlink, @repo

      assert_equal "On a scale of 1 to 10, how badly does it hurt?\n", @issue.body_template
    end

    test "body_template only finds files name ISSUE_TEMPLATE or a variant with an extension" do
      example_repo :dirty_dotgithub, @repo

      assert_nil @issue.body_template
    end

    test "body_template returns org level legacy template if exists", skip_with_all_emus: true do
      org = create(:organization)
      org_repo = create(:repository, owner: org)
      dot_github_repo = create(:repository, owner: org, name: ".github", from_example: :magic_config_files)

      issue = create(:issue, repository: org_repo)
      assert_equal "Please describe your issue.\n", issue.body_template
    end
  end

  context "ISSUE_TEMPLATE/nested.md" do
    test "body_template returns ISSUE_TEMPLATE/ content when one is found" do
      example_repo :magic_config_files_w_nesting, @repo
      @issue.body_template_name = "feature.md"
      assert_equal "Please describe your feature:\n", @issue.body_template
    end

    test "body_template finds ISSUE_TEMPLATE content in .github/ISSUE_TEMPLATE/" do
      example_repo :dot_github_w_nesting, @repo
      @issue.body_template_name = "feature.md"
      assert_equal "Please describe your feature:\n", @issue.body_template
    end

    test "body_template follows symlinks .github/ISSUE_TEMPLATE/" do
      example_repo :dotgithub_w_symlink_w_nesting, @repo
      @issue.body_template_name = "feature.md"
      assert_equal "On a scale of 1 to 10, how awesome is it?\n", @issue.body_template
    end

    test "body_template returns ISSUE_TEMPLATE/ template from org's .github repo if exists", skip_with_all_emus: true do
      org = create(:organization)
      org_repo = create(:repository, owner: org)
      dot_github_repo = create(:repository, owner: org, name: ".github", from_example: :magic_config_files_w_nesting)
      assert_equal dot_github_repo, org_repo.reload.global_health_files_repo,
        "need org's .github repo to be global health files repo for this test"

      issue = build(:issue, repository: org_repo)
      issue.body_template_name = "feature.md"
      assert_equal "Please describe your feature:\n", issue.body_template
    end

    test "body_template returns ISSUE_TEMPLATE/ template from user's .github repo if exists", skip_with_all_emus: true do
      user_repo = create(:repository, owner: @owner)
      dot_github_repo = create(:repository, owner: @owner, name: ".github", from_example: :magic_config_files_w_nesting)
      assert_equal dot_github_repo, user_repo.reload.global_health_files_repo,
        "need user's .github repo to be global health files repo for this test"

      issue = build(:issue, repository: user_repo)
      issue.body_template_name = "feature.md"
      assert_equal "Please describe your feature:\n", issue.body_template
    end
  end

  test "body_template returns nothing when there's no ISSUE_TEMPLATE file" do
    assert_nil @open_issue.body_template
  end

  test "body_template only finds files name ISSUE_TEMPLATE or a variant with an extension" do
    example_repo :dirty_dotgithub, @repo

    assert_nil @issue.body_template
  end

  test "body_template is empty for new issues" do
    repo = create :repository
    assert_nil repo.issues.new.body_template
  end

  test "subscribes for comments", feature_disabled: :notifyd_issue_watch_activity_notify do
    assert !@open_issue.subscribed?(@authed)

    create :issue_comment, :wait_for_orchestration, issue: @open_issue, body: "hello!", user: @authed

    status = @open_issue.subscription_status(@authed).value
    assert status.subscribed?
    assert_equal "comment", status.reason
  end

  context "notifications" do
    test "its author is the user" do
      assert_equal @private_issue.user, @private_issue.notifications_author
    end

    test "its thread for notifications is itself" do
      assert_equal @private_issue, @private_issue.notifications_thread
    end

    test "its thread for notifications is the issue if it has a PR" do
      assert_equal @issue_with_pull, @issue_with_pull.notifications_thread
    end

    test "its subscription type for notifications is `PullRequest` if it has a PR" do
      assert_equal PullRequest, @issue_with_pull.notifications_subscription_type
    end

    test "its list is the repo" do
      assert_equal @private_issue.repository, @private_issue.notifications_list
    end

    test "cleans up newsies data for thread when issue is destroyed" do
      GitHub.newsies.expects(:async_delete_all_for_thread).with(@private_issue.repository, @private_issue)
      only = [RemoveFromSearchIndexJob]
      perform_enqueued_jobs(only: only) do
        @private_issue.destroy
      end
    end
  end

  test "list of participants for issue includes issue creator" do
    assert_equal [@unauthed],
                 @issue.participants_for(@unauthed)
  end

  test "list of participants for issues includes issue event actors" do
    repo = create :repository, owner: @owner, force_user_owned: true
    create(:collaborator, repository: repo, collaborator: @user)
    issue = create(:issue, repository: repo, user: @owner)
    create :issue_event, issue: issue, event: "closed", actor_id: @user.id
    assert_equal [@owner, @user], issue.participants_for(@owner)
  end

  test "list of participants for issues does not include apps or bots" do
    integration = create(:integration)
    create :issue_event, issue: @issue, event: "closed", actor_id: integration.bot
    refute_includes @issue.participants_for(@unauthed), integration.bot
  end

  test "list of participants for issues with a bot as the author does not include the bot" do
    bot = create(:bot)
    issue = create(:issue, user: bot)
    refute_includes issue.participants, bot
    assert_equal issue.participant_count, 0
  end

  test "participants for issue includes issue commenters" do
    repo = create :repository, owner: @owner, force_user_owned: true
    create(:collaborator, repository: repo, collaborator: @user)
    issue = create(:issue, repository: repo, user: @owner)

    # participate via commenting on the issue
    issue.comments.create!({
      repository: repo,
      user: @user,
      body: "blah",
    })

    assert_same_elements [@user, @owner],
      Issue.find(issue.id).participants_for(@owner)
  end

  test "list of participants for issue does not include those who mentioned the issue from another issue" do
    repo = create :repository, owner: @owner, force_user_owned: true
    create(:collaborator, repository: repo, collaborator: @user)
    issue = create(:issue, repository: repo, user: @owner)
    other_issue = create(:issue, repository: repo, user: @owner)

    # mentioning the issue from another issue
    # does not qualify as participating
    other_issue.comments.create!({
      repository: repo,
      user: @user,
      body: "this must have to do with ##{issue.number}",
    })

    assert_same_elements [@owner],
      Issue.find(issue.id).participants_for(@owner)
  end

  test "list of participants for issue does not include those who mentioned the issue from a commit" do
    repo = create :repository, owner: @owner, force_user_owned: true, from_example: :simple
    user = create(:collaborator, repository: repo)
    issue = create(:issue, repository: repo, user: @owner)

    # mentioning the issue from another issue
    # does not qualify as participating
    metadata = { message: "see ##{issue.number}", committer: user }
    ref = repo.heads.find(repo.default_branch)
    before = ref.target.oid
    ref.append_commit(metadata, user)

    message = {
      repository_id: repo.id,
      ref_updates: [{ ref: "refs/heads/master", before: before, after: ref.target.oid }],
      pushed_at: Time.now,
      pusher: @owner.login,
    }

    assert_difference "issue.events.reload.size" do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_issues_on_push")
    end

    assert_same_elements [@owner],
      Issue.find(issue.id).participants_for(@owner)
  end

  test "list of participants for issue does not include organizations", skip_with_all_emus: true do
    user_to_org = create(:user)
    issue = create(:issue, repository: @repo, user: user_to_org)
    org = Organization.transform!(user_to_org, @unauthed)
    participants = issue.reload.participants_for(@unauthed)
    refute_includes participants, user_to_org
    refute_includes participants, org
  end

  test "list of participants for issue can be limited" do
    @open_issue.comments.create!(user: @users[0], body: "Comment body")
    @open_issue.comments.create!(user: @users[1], body: "Comment body")
    limit = 1

    participants = @open_issue.participants_for(@unauthed, user_limit: limit)
    assert_equal participants.size, limit
  end

  test "list of participants for issue ignores non-Integer limit" do
    @open_issue.comments.create!(user: @users[0], body: "Comment body")
    @open_issue.comments.create!(user: @users[1], body: "Comment body")
    limit = "one"

    participants = @open_issue.reload.participants_for(@unauthed, user_limit: limit)
    refute_equal participants.size, limit
  end

  test "loading participants sets the participant count on the issue" do
    @open_issue.events.create!(actor: @users[1], event: "closed")

    participants = @open_issue.participants_for(@unauthed)
    assert_equal @open_issue.participant_count, participants.size
  end

  test "comments loaded is limited to the COMMENT_LIMIT" do
    @open_issue.comments.create!(user: @users[0], body: "Comment body")
    @open_issue.comments.create!(user: @users[1], body: "Comment body")

    Issue.stub_const(:COMMENT_LIMIT, 1) do
      @open_issue.reload
      assert_equal @open_issue.comments.size, 1
    end
  end

  test "loading participants filters out duplicate users" do
    repo = create(:repository, owner: @owner, force_user_owned: true)
    user = create(:collaborator, repository: repo)
    issue = create(:issue, user: @owner, repository: repo)

    issue.comments.create!(user: user, body: "Comment body")
    issue.comments.create!(user: @owner, body: "Comment body")
    issue.events.create!(actor: user, event: "closed")

    participants = issue.participants_for(@owner)
    assert_same_elements participants, [@owner, user]
  end

  if GitHub.spamminess_check_enabled? && !TestEnv.test_with_all_emus?
    test "list of participants for issue does not include spammer" do
      # participate via commenting on the issue
      @issue.comments.create!({
        repository: @repo,
        user: @spammer,
        body: "blah",
      })

      create :issue_event, issue: @issue, event: "closed", actor_id: @spammer.id

      issue = Issue.find(@issue.id)
      assert_same_elements [@unauthed], issue.participants_for(@unauthed)
      assert_same_elements [@spammer, @unauthed], issue.participants_for(@spammer)
    end

    test ".not_spammy does not return issues from spammy users" do
      spammy_issue = create :issue, repository: @private_repo, user: @spammer

      issues = Issue.not_spammy
      refute issues.include?(spammy_issue)
    end

    test ".suggestions is chainable with .not_spammy" do
      spammy_issue = create :issue, repository: @private_repo, user: @spammer

      issues = Issue.suggestions.not_spammy
      refute issues.include?(spammy_issue)
    end
  end

  test ".suggestions returns issues in updated_at order" do
    @issue.update!(updated_at: 1.minute.ago)
    @other_issue.update!(updated_at: 3.weeks.ago)

    issues = Issue.suggestions
    public_issue_index = T.must(issues.find_index(@issue))
    other_issue_index = T.must(issues.find_index(@other_issue))
    assert public_issue_index < other_issue_index
  end

  test "enqueues community profile job after create", skip_enterprise: true do
    CommunityProfileUpdateHelpWantedCountersJob.expects(:enqueue_once_per_interval).
      with(args: [@repo.id], interval: CommunityProfile::UPDATE_INTERVAL)

    issue = create(:issue, repository: @repo, user: @user, labels: [@help_wanted_label])
  end

  test "does not enqueue help wanted job unless relevant labels have been added or removed", skip_enterprise: true do
    CommunityProfileUpdateHelpWantedCountersJob.expects(:enqueue_once_per_interval).never
    label = create(:label, repository: @repo, name: "123")
    issue = create(:issue, repository: @repo, user: @user, labels: [label])
  end

  context "#set_first_contribution_flag", skip_with_all_emus: true do
    test "sets the flag for the first pull request by a non-maintainer", skip_enterprise: true do
      example_repo :pull_request_source, @repo
      new_user = create(:user)
      fork = create(:fork_repository, forker: new_user, fork_repo: @repo, from_example: :pull_request_fork)
      issue = Issue.create!(
        repository: @repo,
        title: @open_issue.title,
        body: @open_issue.body,
        user: new_user,
        pull_request: @repo.comparison("master", "#{new_user.display_login}:topic").build_pull_request(user: new_user),
      )
      assert issue.pull_request?
      assert issue.first_contribution_prompt_active?
    end

    test "does not set the flag for the first issue by a non-maintainer", skip_enterprise: true do
      new_user = create(:user)
      issue = Issue.create!(
        repository: @repo,
        title: @open_issue.title,
        body: @open_issue.body,
        user: new_user,
      )
      refute issue.pull_request?
      refute issue.first_contribution_prompt_active?
    end

    test "does not set the flag for the first pull request by a maintainer", skip_enterprise: true do
      example_repo :pull_request_fork, @repo
      issue = Issue.create!(
        repository: @repo,
        title: @open_issue.title,
        body: @open_issue.body,
        user: @member,
        pull_request: @repo.comparison("master", "topic").build_pull_request(user: @member),
      )
      assert issue.pull_request?
      refute issue.first_contribution_prompt_active?
    end

    test "does not set the flag if the user has seen it on another repository", skip_enterprise: true do
      example_repo :pull_request_source, @repo
      new_user = create(:user)
      fork = create(:fork_repository, forker: new_user, fork_repo: @repo, from_example: :pull_request_fork)
      issue = Issue.create!(
        repository: @repo,
        title: @open_issue.title,
        body: @open_issue.body,
        user: new_user,
        pull_request: @repo.comparison("master", "#{new_user.display_login}:topic").build_pull_request(user: new_user),
      )
      assert issue.first_contribution_prompt_active?

      another_public_repo = create(:public_repository, owner: @repo.owner, from_example: :pull_request_source)
      another_fork = create(:fork_repository, forker: new_user, fork_repo: @repo, from_example: :pull_request_fork)
      another_issue = Issue.create!(
        repository: another_public_repo,
        title: @open_issue.title,
        body: @open_issue.body,
        user: new_user,
        pull_request: another_public_repo.comparison("master", "#{new_user.display_login}:topic", head_repo: another_fork).build_pull_request(user: new_user),
      )
      refute another_issue.first_contribution_prompt_active?
    end

    test "returns nil if kv is unavailable", skip_enterprise: true do
      GitHub::KV.any_instance.stubs(:get).returns(GitHub::Result.new { raise GitHub::KV::UnavailableError })

      example_repo :pull_request_source, @repo
      new_user = create(:user)
      fork = create(:fork_repository, forker: new_user, fork_repo: @repo, from_example: :pull_request_fork)
      issue = Issue.create!(
        repository: @repo,
        title: @open_issue.title,
        body: @open_issue.body,
        user: new_user,
        pull_request: @repo.comparison("master", "#{new_user.display_login}:topic").build_pull_request(user: new_user),
      )
      assert issue.pull_request?
      refute issue.first_contribution_prompt_active?
    end
  end

  context ".labled_by_any" do
    test "returns issues that belong to a provided label id" do
      label = create(:label, name: "label", repository: @private_issue.repository)
      @private_issue.add_labels label

      assert_equal [@private_issue], Issue.labeled_by_any(label.id).to_a
    end

    test "finds issues by label name irrespective of its casing" do
      label = create(:label, name: "label", repository: @private_repo)
      other_label = create(:label, name: "other_label", repository: @private_repo)

      @private_issue.add_labels [label, other_label]

      assert_equal [@private_issue], Issue.labeled_by_any(["LABEL"])
    end

    test "returns issues that belong to one label in the provided list of label names" do
      label = create(:label, name: "label", repository: @private_repo)
      other_label = create(:label, name: "other_label", repository: @private_repo)
      unrelated_label = create(:label, name: "unrelated_label", repository: @private_repo)

      @private_issue.add_labels [label, other_label]

      assert_equal [@private_issue], Issue.labeled_by_any(%w[label unrelated_label]).to_a
      assert_equal [@private_issue], Issue.labeled_by_any(%w[label other_label]).to_a.uniq
    end
  end

  context ".labeled" do
    test "finds issues with many labels by a single passed label name" do
      label = create(:label, name: "label", repository: @private_repo)
      other_label = create(:label, name: "other_label", repository: @private_repo)

      @private_issue.add_labels [label, other_label]

      assert_equal [@private_issue], Issue.labeled(["label"])
    end

    test "finds issues by label name irrespective of its casing" do
      label = create(:label, name: "label", repository: @private_repo)
      other_label = create(:label, name: "other_label", repository: @private_repo)

      @private_issue.add_labels [label, other_label]

      assert_equal [@private_issue], Issue.labeled(["LABEL"])
    end

    test "only finds issues that match all passed label names" do
      label = create(:label, name: "label", repository: @private_repo)
      other_label = create(:label, name: "other_label", repository: @private_repo)
      unrelated_label = create(:label, name: "unrelated_label", repository: @private_repo)
      @private_issue.add_labels [label, other_label]

      assert_equal [], Issue.labeled(%w[label unrelated_label]).to_a
      assert_equal [@private_issue], Issue.labeled(%w[label other_label]).to_a
    end

    test "fails to add when label is in a different repository" do
      other_repo = create(:repository, owner: @owner)
      label = create(:label, name: "label", repository: other_repo)
      assert_raises Issue::InvalidLabelAddedError do
        @private_issue.add_labels [label]
      end

      assert_raises Issue::InvalidLabelAddedError do
        @private_issue.labels << label
      end
    end
  end

  context ".add_labels" do
    test "it add labels to an issue" do
      Search.expects(:add_to_search_index).with("issue", @private_issue.id).at_most(2)

      assert_equal [],         @private_issue.labels
      assert_equal [@labeled], @label.issues

      perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
        @private_issue.add_labels [@label]
      end

      assert_same_elements [@label], @private_issue.labels.reload
      assert_same_elements [@private_issue, @labeled], @label.issues.reload
    end

    test "it does not add labels to an issue that already has 100 labels" do
      labels = create_list(:label, 100, repository: @private_issue.repository)
      assert_equal [], @private_issue.labels
      @private_issue.add_labels labels
      assert_equal 100, @private_issue.labels.count
      assert_raises(ActiveRecord::RecordInvalid) { @private_issue.add_labels [@label] }
      refute @private_issue.valid?
      assert_equal 100, @private_issue.labels.count
    end

    test "it add labels to a pull request" do
      Search.expects(:add_to_search_index).with("pull_request", @issue_with_pull.pull_request.id).at_most(2)

      assert_equal [],         @issue_with_pull.labels

      perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
        @issue_with_pull.add_labels [@label]
      end

      assert_same_elements [@label], @issue_with_pull.labels.reload
    end

    test "it touches the issue" do
      timestamp = @private_issue.updated_at

      Timecop.freeze(3.hours.from_now) do
        @private_issue.add_labels [@label]
        refute_equal @private_issue.updated_at, timestamp
      end
    end

    test "generates an event" do
      GitHub.context.push(actor_id: @owner.id)

      assert_difference "@private_issue.events.count", 1 do
        @private_issue.add_labels [@label]
      end

      event = @private_issue.events.last
      assert_equal "labeled", event.event
    end

    test "enqueues community profile update job", skip_enterprise: true do
      CommunityProfileUpdateHelpWantedCountersJob.expects(:enqueue_once_per_interval).
        with(args: [@repo.id], interval: CommunityProfile::UPDATE_INTERVAL)

      @issue.add_labels [@help_wanted_label]
    end
  end

  context ".delete_labels" do
    test "deletes labels from an issue" do
      Search.expects(:add_to_search_index).with("issue", @labeled.id).at_most(2)

      assert_equal [@label], @labeled.labels

      perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
        @labeled.delete_labels [@label]
      end

      assert_equal [], @labeled.labels.reload
    end

    test "does not delete label or generate event if label not assigned to issue" do
      GitHub.context.push(actor_id: @owner.id)

      assert_equal [], @private_issue.labels

      assert_no_difference "@private_issue.events.count" do
        @private_issue.delete_labels [@label]
      end

      assert_equal [], @private_issue.reload.labels
      assert_empty @private_issue.events.unlabels
    end

    test "it touches the issue" do
      timestamp = @labeled.updated_at

      Timecop.freeze(3.hours.from_now) do
        @labeled.delete_labels [@label]
        refute_equal @labeled.updated_at, timestamp
      end
    end

    test "generates an event" do
      GitHub.context.push(actor_id: @owner.id)

      assert_difference "@labeled.events.count", 1 do
        @labeled.delete_labels [@label]
      end

      event = @labeled.events.last
      assert_equal "unlabeled", event.event
    end

    test "enqueues community profile update job", skip_enterprise: true do
      CommunityProfileUpdateHelpWantedCountersJob.expects(:enqueue_once_per_interval).
        with(args: [@repo.id], interval: CommunityProfile::UPDATE_INTERVAL)

      @issue.labels << @help_wanted_label
      @issue.delete_labels [@help_wanted_label]
    end
  end

  context ".clear_labels" do
    test "it clears labels for an issue" do
      Search.expects(:add_to_search_index).with("issue", @labeled.id).at_most(2)

      assert_equal [@label], @labeled.labels

      perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
        @labeled.clear_labels
      end

      assert_equal [], @labeled.labels.reload
    end

    test "it touches the issue" do
      timestamp = @labeled.updated_at

      Timecop.freeze(3.hours.from_now) do
        @labeled.clear_labels
        refute_equal @labeled.updated_at, timestamp
      end
    end

    test "generates an event" do
      GitHub.context.push(actor_id: @owner.id)

      assert_difference "@labeled.events.count", 1 do
        @labeled.clear_labels
      end

      event = @labeled.reload.events.last
      assert_equal "unlabeled", event.event
    end
  end

  context ".replace_labels" do
    test "it replaces labels for an issue" do
      Search.expects(:add_to_search_index).with("issue", @private_issue.id).at_most(2)

      assert_equal [],         @private_issue.labels
      assert_equal [@labeled], @label.issues

      perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
        @private_issue.replace_labels [@label]
      end

      assert_same_elements [@label], @private_issue.labels.reload
      assert_same_elements [@private_issue, @labeled], @label.issues.reload
    end

    test "respects the label limit validation on an issue" do
      labels = create_list(:label, 100, repository: @private_issue.repository)

      assert_equal [], @private_issue.labels
      @private_issue.replace_labels(labels)
      assert_equal labels.count, @private_issue.labels.count

      refute @private_issue.replace_labels(labels + [@label])
      refute @private_issue.valid?
      assert_equal labels.count, @private_issue.labels.count
    end

    test "replace multiple labels" do
      assert_equal [], @private_issue.labels

      @private_issue.replace_labels [@label, @label_2]

      assert_same_elements [@label, @label_2], @private_issue.labels.reload
      assert_includes @label.issues.reload, @private_issue
      assert_includes @label_2.issues.reload, @private_issue
    end

    test "it removes labels with an empty list" do
      assert_equal [@label], @labeled.labels
      @labeled.replace_labels []
      assert_equal [], @labeled.labels.reload
    end

    test "it touches the issue" do
      timestamp = @private_issue.updated_at

      Timecop.freeze(3.hours.from_now) do
        @private_issue.replace_labels [@label]
        refute_equal @private_issue.updated_at, timestamp
      end
      timestamp = @labeled.updated_at
    end

    test "it generates label events" do
      new_label = create :label, name: "wontfix", repository: @labeled.repository
      first_label_events = @labeled.events.to_a.dup # events from test setup
      assert first_label_events.size == 1
      assert first_label_events.first.event == "labeled" && first_label_events.first.label_id == @label.id

      @labeled.replace_labels [new_label]
      events = @labeled.reload.events.to_a.dup - first_label_events

      event = events.shift
      assert_equal "unlabeled", event.event
      assert_equal @label.name, event.label_name

      event = events.shift
      assert_equal "labeled", event.event
      assert_equal "wontfix", event.label_name
    end

    test "returns true" do
      new_label = create :label, name: "wontfix", repository: @labeled.repository
      issue = create :issue, repository: @labeled.repository
      assert issue.events.empty?
      result = issue.replace_labels [new_label]
      assert_equal true, result
      refute issue.events.empty?
    end

    test "handles duplicate issue labels" do
      @labeled.stubs(:destroy_replaced_labels).returns(true)
      assert_nothing_raised  do
        @labeled.replace_labels(@labeled.labels)
      end
    end

    test "enqueues community profile update job", skip_enterprise: true do
      CommunityProfileUpdateHelpWantedCountersJob.expects(:enqueue_once_per_interval).
        with(args: [@repo.id], interval: CommunityProfile::UPDATE_INTERVAL)

      @issue.add_labels [@help_wanted_label]
    end
  end

  context "editable_by?" do
    test "with anonymous user and ghost author" do
      issue = create(:issue)
      issue.user.destroy
      issue.reload

      assert_nil issue.user

      refute issue.editable_by?(nil)
    end

    test "with locked thread" do
      owner = create(:user)
      repo = create(:repository, owner: owner, admin: owner)
      author = create(:user)
      issue = create(:issue, repository: repo, user: author)

      assert !issue.locked?

      collab = create(:collaborator, repository: repo)
      user   = create(:user)
      staff  = create(:staff_admin_user)

      # author is not a repo collab
      refute_includes repo.members, author

      assert issue.lock(owner)
      assert issue.locked?

      assert issue.editable_by?(owner)
      assert issue.editable_by?(collab)
      refute issue.editable_by?(author)
      refute issue.editable_by?(user)
      refute issue.editable_by?(nil)
    end
  end

  context "#og_image_url" do
    test "it returns enhanced opengraph image url with correct cache key" do
      issue = create(:issue)
      repo = issue.repository

      # calculate expected cache key from specific resource attributes
      cache_key = Digest::SHA256.hexdigest(
        [
          issue.updated_at,
          repo.name,
          repo.owner_id,
        ].join(":")
      )

      # enhanced opengraph url with expected cache slug
      image_url = "#{GitHub.og_image_generator_base_url}/#{cache_key}#{issue.permalink(include_host: false)}"

      assert_equal image_url, issue.og_image_url
    end
  end

  context "#async_viewer_can_update?" do
    test "returns whether the given user can edit the issue" do
      owner = create(:user)
      repo = create(:repository, owner: owner, admin: owner)
      issue = create(:issue, repository: repo)

      refute_predicate issue, :locked?

      collab = create(:collaborator, repository: repo)
      author = issue.user
      user   = create(:user)
      staff  = create(:staff_admin_user)

      # author is not a repo collab
      refute_includes repo.members, author

      assert issue.async_viewer_can_update?(owner).sync
      assert issue.async_viewer_can_update?(collab).sync
      assert issue.async_viewer_can_update?(author).sync
      refute issue.async_viewer_can_update?(staff).sync
      refute issue.async_viewer_can_update?(user).sync
      refute issue.async_viewer_can_update?(nil).sync

      assert issue.lock(owner)
      assert_predicate issue, :locked?

      # # Find a new object so that we don't keep any cached ivars around
      issue = Issue.find(issue.id)

      assert issue.async_viewer_can_update?(owner).sync
      assert issue.async_viewer_can_update?(collab).sync
      refute issue.async_viewer_can_update?(author).sync
      refute issue.async_viewer_can_update?(staff).sync
      refute issue.async_viewer_can_update?(user).sync
      refute issue.async_viewer_can_update?(nil).sync
    end

    test "returns whether the given user can edit the issue (org)" do
      org = create(:organization, plan: "business_plus")
      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo)

      read = create(:collaborator,  repository: repo, action: :read)
      triage = create(:collaborator, repository: repo, action: :triage)
      maintain = create(:collaborator, repository: repo, action: :maintain)
      write = create(:collaborator, repository: repo, action: :write)
      admin = create(:collaborator, repository: repo, action: :admin)

      refute issue.async_viewer_can_update?(read).sync
      refute issue.async_viewer_can_update?(triage).sync
      assert issue.async_viewer_can_update?(maintain).sync
      assert issue.async_viewer_can_update?(write).sync
      assert issue.async_viewer_can_update?(admin).sync
    end

    test "that multiple issue promises have their discussion queries batched together" do
      owner = create(:user)
      repo = create(:repository, owner: owner, admin: owner, has_discussions: true)
      issues = Array.new(3) { create(:issue, repository: repo) }

      _, queries = log_cleaned_queries do
        Promise.all(issues.map { |i| i.async_viewer_can_update?(owner) }).sync
      end

      actual_queries         = identify_queries(queries)
      discussion_query_count = actual_queries.count { |q| q == "discussions" }

      assert_equal 1, discussion_query_count, message: "Expected only 1 discussion query when executing promise"
    end
  end

  context "#async_viewer_cannot_update_reasons" do
    test "returns a list of reason codes that describe why the the given user can not edit" do
      owner = create(:user)
      repo = create(:repository, owner: owner, admin: owner)
      issue = create(:issue, repository: repo)

      refute_predicate issue, :locked?

      collab = create(:collaborator, repository: repo)
      author = issue.user
      user   = create(:user)
      staff  = create(:staff_admin_user)

      # author is not a repo collab
      refute_includes repo.members, author

      assert_equal [], issue.async_viewer_cannot_update_reasons(owner).sync
      assert_equal [], issue.async_viewer_cannot_update_reasons(collab).sync
      assert_equal [], issue.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:insufficient_access], issue.async_viewer_cannot_update_reasons(staff).sync
      assert_equal [:insufficient_access], issue.async_viewer_cannot_update_reasons(user).sync
      assert_equal [:login_required], issue.async_viewer_cannot_update_reasons(nil).sync

      assert issue.lock(owner)
      assert_predicate issue, :locked?

      # Find a new object so that we don't keep any cached ivars around
      issue = Issue.find(issue.id)

      assert_empty issue.async_viewer_cannot_update_reasons(owner).sync
      assert_empty issue.async_viewer_cannot_update_reasons(collab).sync
      assert_equal [:locked], issue.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:locked, :insufficient_access], issue.async_viewer_cannot_update_reasons(staff).sync
      assert_equal [:locked, :insufficient_access], issue.async_viewer_cannot_update_reasons(user).sync
      assert_equal [:login_required], issue.async_viewer_cannot_update_reasons(nil).sync
    end

    context "when interaction limits are enabled" do
      test "returns insufficient_access for non-collaborator author" do
        assert_empty @other_issue.async_viewer_cannot_update_reasons(@user).sync

        interaction = RepositoryInteractionAbility.new(@repo)
        interaction.set_ability(:collaborators_only, @unauthed)

        assert_equal [:insufficient_access], @other_issue.async_viewer_cannot_update_reasons(@user).sync
      end

      test "returns empty list for owner author" do
        interaction = RepositoryInteractionAbility.new(@repo)
        interaction.set_ability(:collaborators_only, @unauthed)
        assert_empty @issue.async_viewer_cannot_update_reasons(@unauthed).sync
      end
    end
  end

  context "#async_possible_transfer_repositories" do
    test "includes all repos ordered by update time if issue belongs to public repo", skip_with_all_emus: true do
      user = create(:user)
      public_repo = create :repository, owner: user
      other_public_repo = create :repository, owner: user
      private_repo = create :private_repository,  owner: user
      issue = create :issue, repository: public_repo

      Timecop.freeze(10.minutes.ago) { other_public_repo.touch }
      Timecop.freeze(5.minutes.ago) { private_repo.touch }

      results = issue.async_possible_transfer_repositories(viewer: user).sync

      assert_equal [private_repo, other_public_repo], results
    end

    test "includes repos that match in name regardless of its updated_at time" do
      GitHub.flipper[:limit_transfer_repo_suggestions].disable

      user = create(:user)
      original_repo = create :repository, owner: user, force_user_owned: true, name: "github-sdk"

      repos = []
      (1..6).each do |i|
        repos[i] = create :repository, owner: user, force_user_owned: true, name: "#{i}-github-sdk"
      end
      (7..12).each do |i|
        repos[i] = create :repository, owner: user, force_user_owned: true, name: "github-sdk-#{i}"
      end

      issue = create :issue, repository: repos[2]

      Timecop.freeze(13.minutes.ago) { original_repo.touch }
      (1..12).each do |i|
        Timecop.freeze((13 - i).minutes.ago) { repos[i].touch }
      end

      results = issue.async_possible_transfer_repositories(viewer: user, query: "github-sdk").sync

      assert_equal [*repos[7..12]&.reverse, original_repo, *repos[4..6]&.reverse], results
    end

    test "excludes repos that don't have issues enabled" do
      user = create(:user)
      repo = create :repository, owner: user, force_user_owned: true
      other_repo = create :repository, owner: user, force_user_owned: true, has_issues: false
      issue = create :issue, repository: repo

      results = issue.async_possible_transfer_repositories(viewer: user).sync

      refute_includes results, other_repo
    end

    test "excludes repos that are deleted" do
      user = create :user
      repo = create :repository, owner: user, force_user_owned: true
      remove_repo = create :repository, owner: user, force_user_owned: true
      issue = create :issue, repository: repo

      remove_repo.remove(user, synchronous: true)
      results = issue.async_possible_transfer_repositories(viewer: user).sync

      refute_includes results, remove_repo
    end

    test "only includes private repos if issue belongs to private repo" do
      user = create(:user)
      private_repo = create :private_repository,  owner: user, force_user_owned: true
      other_private_repo = create :private_repository, owner: user, force_user_owned: true
      repo = create :repository, owner: user, admin: user
      issue = create :issue, repository: private_repo

      results = issue.async_possible_transfer_repositories(viewer: user).sync

      assert_equal [other_private_repo], results
    end

    test "includes repos where the user has write access and above" do
      user = create(:user)
      owner = create(:user)
      repo = create :repository, owner: owner, admin: owner, force_user_owned: true
      admin_repo = create :repository, owner: owner, force_user_owned: true
      create(:collaborator, collaborator: user, repository: admin_repo, action: :admin)
      write_repo = create :repository, owner: owner, force_user_owned: true
      create(:collaborator, collaborator: user, repository: write_repo, action: :write)
      read_repo = create :repository, owner: owner, force_user_owned: true
      create(:collaborator, collaborator: user, repository: read_repo, action: :read)
      issue = create :issue, repository: repo

      Timecop.freeze(10.minutes.ago) { admin_repo.touch }
      Timecop.freeze(5.minutes.ago) { write_repo.touch }

      results = issue.async_possible_transfer_repositories(viewer: user).sync

      assert_equal [write_repo, admin_repo], results
    end
  end

  context "issue deleted tier1 event" do
    mock_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"

    test "not instrument hydro.schemas.events_platform.v0.Tier1Event hydro event when issue is deleted and tier1 event feature flag is disabled", skip_with_all_emus: true do
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do

          GitHub.context.push(actor_ip: "3ffe:505:2::1")
          GitHub.context.push(user_agent: "test agent")

          actor = create(:user)
          repository = create(:public_repository, owner: actor)
          GitHub.flipper[:events_v2_publish_tier1_event].disable
          issue = create :issue, :with_instrumentation, :wait_for_orchestration, user: actor, title: "Hello", body: "World", repository: repository
          issue.destroy
          assert_hydro_messages(count: 0, schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: "events_platform.v0.Issues")
        end
      end
    end

    test "not instrument hydro.schemas.events_platform.v0.Tier1Event hydro event when issue is deleted and delete action specific feature flag is disabled", skip_with_all_emus: true do
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          GitHub.context.push(actor_ip: "3ffe:505:2::1")
          GitHub.context.push(user_agent: "test agent")

          actor = create(:user)
          repository = create(:public_repository, owner: actor)
          GitHub.flipper[:events_v2_publish_tier1_event].enable(Events::ParentAsActor.repo_actor(repository.id))
          GitHub.flipper[:events_v2_publish_issues_deleted_tier1_event].disable

          issue = create :issue, :with_instrumentation, :wait_for_orchestration, user: actor, title: "Hello", body: "World", repository: repository

          issue.destroy
          assert_hydro_messages(count: 1, schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: "events_platform.v0.Issues")

          # Ensure only the issue created event was published.
          message = {
            type: :EVENT_TYPE_ISSUES,
            action: :EVENT_ACTION_OPENED,
          }
          assert_hydro_published(message, schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: "events_platform.v0.Issues", ignore_extra_keys: true)
        end
      end
    end

    test "increments metrics if generating a tier 1 event for issue deletion events fails" do
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          GitHub.context.push(actor_ip: "3ffe:505:2::1")
          GitHub.context.push(user_agent: "test agent")

          mock_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
          Events::Tier1EventPublisher.expects(:new_guid).returns(mock_guid).at_least_once

          last_writes = {
            mysql1: { gtid: "000-000", time: Time.now.to_i * 1000 },
            repositories: { gtid: "000-000", time: Time.now.to_i * 1000 }
          }
          DatabaseSelector::ReplicationState.expects(:current).at_least_once.returns(DatabaseSelector::ReplicationState.new)
          DatabaseSelector::ReplicationState.any_instance.expects(:to_hash).at_least_once.returns(last_writes)

          actor = create(:user)
          repository = create(:public_repository, owner: actor)

          GitHub.flipper[:events_v2_publish_tier1_event].enable(Events::ParentAsActor.repo_actor(repository.id))
          GitHub.flipper[:events_v2_publish_issues_deleted_tier1_event].enable
          issue = create :issue, :with_instrumentation, :wait_for_orchestration, user: actor, title: "Hello", body: "World", repository: repository
          Events::IssuesPublisher.expects(:generate_deleted_tier1_event).raises(StandardError.new("boom"))
          Failbot.expects(:report).with(instance_of(StandardError)).once
          issue.destroy
          expected_tags = [
            "operation:generate_deleted_tier1_event",
            "event:issue_deleted",
            "error:StandardError"
          ]
          stats = GitHub.dogstats.increments("events_v2.tier1_event_publish.errors", tags: expected_tags)
          assert_equal 1, stats.size
        end
      end
    end


    test "increments metrics if generating a tier 1 event for issue deletion events fails when publishing" do
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          GitHub.context.push(actor_ip: "3ffe:505:2::1")
          GitHub.context.push(user_agent: "test agent")

          mock_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
          Events::Tier1EventPublisher.expects(:new_guid).returns(mock_guid).at_least_once

          last_writes = {
            mysql1: { gtid: "000-000", time: Time.now.to_i * 1000 },
            repositories: { gtid: "000-000", time: Time.now.to_i * 1000 }
          }
          DatabaseSelector::ReplicationState.expects(:current).at_least_once.returns(DatabaseSelector::ReplicationState.new)
          DatabaseSelector::ReplicationState.any_instance.expects(:to_hash).at_least_once.returns(last_writes)

          actor = create(:user)
          repository = create(:public_repository, owner: actor)

          GitHub.flipper[:events_v2_publish_tier1_event].enable(Events::ParentAsActor.repo_actor(repository.id))
          GitHub.flipper[:events_v2_publish_issues_deleted_tier1_event].enable
          issue = create :issue, :with_instrumentation, :wait_for_orchestration, user: actor, title: "Hello", body: "World", repository: repository
          Events::IssuesPublisher.expects(:publish_tier1_event).raises(StandardError.new("boom"))
          Failbot.expects(:report).with(instance_of(StandardError)).once
          issue.destroy
          expected_tags = [
            "operation:publish",
            "event:issue_deleted",
            "error:StandardError"
          ]
          stats = GitHub.dogstats.increments("events_v2.tier1_event_publish.errors", tags: expected_tags)
          assert_equal 1, stats.size
        end
      end
    end


    test "instruments hydro.schemas.events_platform.v0.Tier1Event hydro event when issue is deleted and feature flag is enabled", skip_with_all_emus: true do
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          GitHub.context.push(actor_ip: "3ffe:505:2::1")
          GitHub.context.push(user_agent: "test agent")

          mock_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
          Events::Tier1EventPublisher.expects(:new_guid).returns(mock_guid).at_least_once

          last_writes = {
            mysql1: { gtid: "000-000", time: Time.now.to_i * 1000 },
            repositories: { gtid: "000-000", time: Time.now.to_i * 1000 }
          }
          DatabaseSelector::ReplicationState.expects(:current).at_least_once.returns(DatabaseSelector::ReplicationState.new)
          DatabaseSelector::ReplicationState.any_instance.expects(:to_hash).at_least_once.returns(last_writes)

          actor = create(:user)
          repository = create(:public_repository, owner: actor)

          GitHub.flipper[:events_v2_publish_tier1_event].enable(Events::ParentAsActor.repo_actor(repository.id))
          GitHub.flipper[:events_v2_publish_issues_deleted_tier1_event].enable
          issue = create :issue, :with_instrumentation, :wait_for_orchestration, user: actor, title: "Hello", body: "World", repository: repository

          issue_attachment = Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueAttachment.new(
            issue: Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::Issue.new(
              id: issue.id,
              repository_id: repository.id,
              user_id: Google::Protobuf::Int64Value.new(value: actor.id),
              issue_comments_count: issue.issue_comments_count,
              number: issue.number,
              position: issue.position,
              title: Google::Protobuf::BytesValue.new(value: issue.read_attribute_before_type_cast(:title)&.to_s),
              state: :OPEN,
              created_at: Google::Protobuf::Timestamp.new(seconds: issue.created_at.to_i),
              updated_at: Google::Protobuf::Timestamp.new(seconds: issue.updated_at.to_i),
              closed_at: nil,
              pull_request_id: nil,
              milestone_id: nil,
              assignee_id: nil,
              contributed_at_timestamp: Google::Protobuf::Int64Value.new(value: issue.contributed_at_timestamp),
              contributed_at_offset: Google::Protobuf::Int32Value.new(value: issue.contributed_at_offset),
              user_hidden: issue.user_hidden,
              performed_by_integration_id: nil,
              has_pull_request: issue&.has_pull_request,
              locked_at: nil,
              compressed_body: Google::Protobuf::BytesValue.new(value: issue.read_attribute_before_type_cast(:compressed_body)&.to_s),
              issue_type_id: nil,
              issue_state_reason: nil,
            )
          )

          message = {
            guid: mock_guid,
            type: :EVENT_TYPE_ISSUES,
            action: :EVENT_ACTION_DELETED,
            target: {
              primary_entity: {
                type: :ENTITY_TYPE_ISSUE,
                id: issue.id.to_s,
                graphql_global_relay_id: issue.global_relay_id,
                graphql_next_global_id: issue.global_relay_id,
              },
              related_entities: [{
                type: :ENTITY_TYPE_REPOSITORY,
                id: repository.id.to_s,
                graphql_global_relay_id: repository.global_relay_id,
                graphql_next_global_id: repository.global_relay_id,
              }],
            },
            triggered_at: now,
            actor: {
              type: :ENTITY_TYPE_USER,
              id: actor.id.to_s,
              graphql_global_relay_id: actor.global_relay_id,
              graphql_next_global_id: actor.global_relay_id,
            },
            target_repository_id: repository.id,
            target_organization_id: repository&.organization_id,
            target_business_id: repository&.organization&.business&.id,
            event_attachment:  {
              type_url: "type.googleapis.com/hydro.schemas.github.event_payload_attachment.v0.IssueAttachment",
              message: T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueAttachment).encode(issue_attachment)
            },
          }

          delivery_system = mock("delivery_system")
          delivery_system.expects(:generate_hookshot_payloads).once
          delivery_system.expects(:deliver_later).once

          Hook::DeliverySystem.expects(:new).with do |params|
            assert_equal mock_guid, params.event_guid
          end.once.returns(delivery_system)

          issue.destroy

          # We expect both the issue created and issue deleted event.
          assert_hydro_messages(count: 2, schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: "events_platform.v0.Issues")

          # ignoring the metadata compare with ignore_extra_keys:true while asserting the hydro message
          assert_hydro_published(message, schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: "events_platform.v0.Issues", ignore_extra_keys: true)
        end
      end
    end
  end

  context "#generate_webhook_payload" do
    event_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
    test "generates :deleted event payload by default" do
      SimpleUUID::UUID.any_instance.expects(:to_guid).once.returns(event_guid)
      GitHub.context.push(actor_id: @owner.id)
      Hook::Event::IssuesEvent.expects(:new).with(issue_id: @private_issue.id, actor_id: @owner.id, action: :deleted, event_guid: event_guid)
      Hook::DeliverySystem.any_instance.expects(:generate_hookshot_payloads)

      @private_issue.generate_webhook_payload

      assert @private_issue.instance_variable_defined?(:@delivery_system)
    end

    test "transferred payload when the issue is deleted due to an issue transfer" do
      SimpleUUID::UUID.any_instance.expects(:to_guid).once.returns(event_guid)
      GitHub.context.push(actor_id: @owner.id)
      Hook::Event::IssuesEvent.expects(:new).with(issue_id: @private_issue.id, actor_id: @owner.id, action: :transferred, event_guid: event_guid)
      Hook::DeliverySystem.any_instance.expects(:generate_hookshot_payloads)

      @private_issue.deletion_hook_action = :transferred
      @private_issue.generate_webhook_payload

      assert @private_issue.instance_variable_defined?(:@delivery_system)
    end

    test "generates a sub-issue event when the issue is deleted and has a parent issue" do
      GitHub.context.push(actor_id: @owner.id)
      parent = create(:issue, repository: @private_issue.repository)
      parent.add_sub_issue!(@private_issue, @owner.id)

      now = Time.now.beginning_of_day
      Timecop.freeze(now) do
        Hook::Event::SubIssuesEvent.expects(:new).with(
          parent_issue_id: parent.id,
          child_issue_id: @private_issue.id,
          actor_id: @owner.id,
          action: :sub_issue_removed,
          triggered_at: now
        )
        Hook::Event::SubIssuesEvent.expects(:new).with(
          parent_issue_id: parent.id,
          child_issue_id: @private_issue.id,
          actor_id: @owner.id,
          action: :parent_issue_removed,
          triggered_at: now
        )
        Hook::DeliverySystem.any_instance.expects(:generate_hookshot_payloads).times(3)

        @private_issue.generate_webhook_payload

        assert @private_issue.instance_variable_defined?(:@parent_issue_delivery_system)
      end
    end

    test "generates sub-issue event(s) when the issue is deleted and has sub-issues" do
      GitHub.context.push(actor_id: @owner.id)
      sub_issue1 = create(:issue, repository: @private_issue.repository)
      sub_issue2 = create(:issue, repository: @private_issue.repository)
      @private_issue.add_sub_issue!(sub_issue1, @owner.id)
      @private_issue.add_sub_issue!(sub_issue2, @owner.id)

      now = Time.now.beginning_of_day
      Timecop.freeze(now) do
        Hook::Event::SubIssuesEvent.expects(:new).with(
          parent_issue_id: @private_issue.id,
          child_issue_id: sub_issue1.id,
          actor_id: @owner.id,
          action: :sub_issue_removed,
          triggered_at: now
        )
        Hook::Event::SubIssuesEvent.expects(:new).with(
          parent_issue_id: @private_issue.id,
          child_issue_id: sub_issue2.id,
          actor_id: @owner.id,
          action: :sub_issue_removed,
          triggered_at: now
        )
        Hook::Event::SubIssuesEvent.expects(:new).with(
          parent_issue_id: @private_issue.id,
          child_issue_id: sub_issue1.id,
          actor_id: @owner.id,
          action: :parent_issue_removed,
          triggered_at: now
        )
        Hook::Event::SubIssuesEvent.expects(:new).with(
          parent_issue_id: @private_issue.id,
          child_issue_id: sub_issue2.id,
          actor_id: @owner.id,
          action: :parent_issue_removed,
          triggered_at: now
        )
        Hook::DeliverySystem.any_instance.expects(:generate_hookshot_payloads).times(5)

        @private_issue.generate_webhook_payload

        assert @private_issue.instance_variable_defined?(:@sub_issue_delivery_system)
      end
    end
  end

  context "#instrument_destruction" do
    test "raises an error if @delivery_system is not defined" do
      GitHub.context.push(actor_id: @owner.id)

      error = assert_raises(RuntimeError) { @private_issue.instrument_destruction }
      assert_match /must be called before `instrument_destruction`/, error.message
    end

    test "delivers the webhook payload if @delivery_system is defined" do
      GitHub.context.push(actor_id: @owner.id)
      Hook::DeliverySystem.any_instance.expects(:deliver_later)

      @private_issue.generate_webhook_payload
      @private_issue.instrument_destruction
    end
  end

  context "#instrument_hydro_event_update" do
    test "instruments an update for a title change via an explicit call to the method" do
      now = Time.now.beginning_of_day
      old_title = @private_issue.title
      new_title = "#{@private_issue.title} and more!"

      Timecop.freeze(now) do
        @private_issue.skip_hydro_update_event_instrumentation = true
        @private_issue.update!(title: new_title)
        @private_issue.instrument_hydro_update_event(previous_title: old_title, actor: @owner)

        expected_hydro_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(@owner),
          repository: Hydro::EntitySerializer.repository(@private_issue.repository),
          repository_owner: Hydro::EntitySerializer.user(@private_issue.repository.owner),
          issue: Hydro::EntitySerializer.issue(@private_issue),
          pull_request: nil,
          previous_title: old_title,
          current_title: new_title,
          previous_body: @private_issue.body,
          current_body: @private_issue.body,
          specimen_body: Hydro::EntitySerializer.specimen_data(@private_issue.body),
          specimen_title: Hydro::EntitySerializer.specimen_data(new_title),
        }

        with_hydro_publisher(GitHub.hydro_publisher) do
          assert_hydro_published(expected_hydro_message, schema: "github.v2.IssueUpdate", count: 1)
        end
      end
    end

    test "instruments an update for a body change via an explicit call to the method" do
      now = Time.now.beginning_of_day
      old_body = @private_issue.body
      new_body = "#{@private_issue.body} and more!"

      Timecop.freeze(now) do
        @private_issue.skip_hydro_update_event_instrumentation = true
        assert @private_issue.update_body(new_body, @owner)
        @private_issue.instrument_hydro_update_event(previous_body: old_body, actor: @owner)

        expected_hydro_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          spamurai_form_signals: nil,
          action_type: :UPDATE,
          content_type: :ISSUE,
          actor: Hydro::EntitySerializer.user(@owner),
          original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.IssueUpdate"),
          content_database_id: @private_issue.id,
          content_global_relay_id: @private_issue.global_relay_id,
          content_created_at: @private_issue.created_at,
          content_updated_at: @private_issue.updated_at,
          title: Hydro::EntitySerializer.specimen_data(@private_issue.title),
          content: Hydro::EntitySerializer.specimen_data(new_body),
          parent_content_author: nil,
          parent_content_database_id: nil,
          parent_content_global_relay_id: nil,
          parent_content_created_at: nil,
          parent_content_updated_at: nil,
          owner: Hydro::EntitySerializer.user(@private_issue.repository.owner),
          repository: Hydro::EntitySerializer.repository(@private_issue.repository),
          content_visibility: :PRIVATE,
        }

        with_hydro_publisher(GitHub.low_latency_hydro_publisher) do
          assert_hydro_published(expected_hydro_message, schema: "github.platform_health.v1.UserGeneratedContent", count: 1)
        end
      end
    end

    test "instruments an update for a title change via the after-commit hook" do
      GitHub.context.push(actor_id: @owner.id)
      now = Time.now.beginning_of_day
      old_title = @private_issue.title
      new_title = "#{@private_issue.title} and more!"

      Timecop.freeze(now) do
        @private_issue.update!(title: new_title)

        expected_hydro_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(@owner),
          repository: Hydro::EntitySerializer.repository(@private_issue.repository),
          repository_owner: Hydro::EntitySerializer.user(@private_issue.repository.owner),
          issue: Hydro::EntitySerializer.issue(@private_issue),
          pull_request: nil,
          previous_title: old_title,
          current_title: new_title,
          previous_body: @private_issue.body,
          current_body: @private_issue.body,
          specimen_body: Hydro::EntitySerializer.specimen_data(@private_issue.body),
          specimen_title: Hydro::EntitySerializer.specimen_data(new_title),
        }

        with_hydro_publisher(GitHub.hydro_publisher) do
          assert_hydro_published(expected_hydro_message, schema: "github.v2.IssueUpdate", count: 1)
        end
      end
    end

    test "instruments an update for a body change via the after-commit hook" do
      GitHub.context.push(actor_id: @owner.id)
      now = Time.now.beginning_of_day
      old_body = @private_issue.body
      new_body = "#{@private_issue.body} and more!"

      Timecop.freeze(now) do
        assert @private_issue.update_body(new_body, @owner)

        expected_hydro_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          spamurai_form_signals: nil,
          action_type: :UPDATE,
          content_type: :ISSUE,
          actor: Hydro::EntitySerializer.user(@owner),
          original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.IssueUpdate"),
          content_database_id: @private_issue.id,
          content_global_relay_id: @private_issue.global_relay_id,
          content_created_at: @private_issue.created_at,
          content_updated_at: @private_issue.updated_at,
          title: Hydro::EntitySerializer.specimen_data(@private_issue.title),
          content: Hydro::EntitySerializer.specimen_data(new_body),
          parent_content_author: nil,
          parent_content_database_id: nil,
          parent_content_global_relay_id: nil,
          parent_content_created_at: nil,
          parent_content_updated_at: nil,
          owner: Hydro::EntitySerializer.user(@private_issue.repository.owner),
          repository: Hydro::EntitySerializer.repository(@private_issue.repository),
          content_visibility: :PRIVATE,
        }

        with_hydro_publisher(GitHub.low_latency_hydro_publisher) do
          assert_hydro_published(expected_hydro_message, schema: "github.platform_health.v1.UserGeneratedContent", count: 1)
        end
      end
    end

    test "instruments an update for a title change via orchestration" do
      GitHub.context.push(actor_id: @owner.id)
      now = Time.now.beginning_of_day
      old_title = @private_issue.title
      new_title = "#{@private_issue.title} and more!"

      @private_issue.orchestrate_hydro_update_event_instrumentation = true

      Timecop.freeze(now) do

        @private_issue.update!(title: new_title)

        with_hydro_publisher(GitHub.hydro_publisher) do
          refute_hydro_messages(schema: "github.v2.IssueUpdate")
        end

        assert_performed_jobs 1, only: [IssueOrchestration.job_class] do
          perform_enqueued_jobs only: [IssueOrchestration.job_class]
        end

        expected_hydro_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(@owner),
          repository: Hydro::EntitySerializer.repository(@private_issue.repository),
          repository_owner: Hydro::EntitySerializer.user(@private_issue.repository.owner),
          issue: Hydro::EntitySerializer.issue(@private_issue),
          pull_request: nil,
          previous_title: old_title,
          current_title: new_title,
          previous_body: @private_issue.body,
          current_body: @private_issue.body,
          specimen_body: Hydro::EntitySerializer.specimen_data(@private_issue.body),
          specimen_title: Hydro::EntitySerializer.specimen_data(new_title),
        }

        with_hydro_publisher(GitHub.hydro_publisher) do
          assert_hydro_published(expected_hydro_message, schema: "github.v2.IssueUpdate", count: 1)
        end
      end
    end

    test "does not instrument an update when skipped even if opting into orchestration" do
      GitHub.context.push(actor_id: @owner.id)
      now = Time.now.beginning_of_day
      old_title = @private_issue.title
      new_title = "#{@private_issue.title} and more!"

      @private_issue.skip_hydro_update_event_instrumentation = true
      @private_issue.orchestrate_hydro_update_event_instrumentation = true

      assert_performed_jobs 1, only: [IssueOrchestration.job_class] do
        perform_enqueued_jobs only: [IssueOrchestration.job_class] do
          @private_issue.update!(title: new_title)
        end
      end

      with_hydro_publisher(GitHub.hydro_publisher) do
        refute_hydro_messages(schema: "github.v2.IssueUpdate")
      end
    end

    test "does not instrument an update when neither title or body has changed" do
      assert @private_issue.open?
      @private_issue.close!

      with_hydro_publisher(GitHub.hydro_publisher) do
        refute_hydro_messages(schema: "github.v2.IssueUpdate")
      end
    end
  end

  test "uses the editing user (not the original user) permissions when editing" do
    user = create(:user, plan: "medium")
    user_private_repo   = create(:private_repository, owner: user)
    owner_private_repo  = create(:private_repository, owner: @owner)
    user_private_issue  = create(:issue, repository: user_private_repo,  user: user)
    owner_private_issue = create(:issue, repository: owner_private_repo, user: @owner)

    user_private_reference  = [user_private_repo.name_with_display_owner,  user_private_issue.number].join("#")
    owner_private_reference = [owner_private_repo.name_with_display_owner, owner_private_issue.number].join("#")

    body  = "Hooray! an issue with some references: "
    body += user_private_reference + " "
    body += owner_private_reference

    issue = create(:issue, repository: @private_repo, user: @owner, body: body)

    assert_includes issue.body, "Hooray!"
    refute_includes issue.body_html, %Q[href="#{user_private_issue.permalink}"]
    assert_includes issue.body_html, %Q[href="#{owner_private_issue.permalink}"]

    body  = "Hooray! editing the issue with some references: "
    body += user_private_reference + " "
    body += owner_private_reference

    issue.update_body(body, user)
    issue = Issue.find(issue.id)

    assert_includes issue.body, "Hooray!"
    assert_includes issue.body_html, %Q[href="#{user_private_issue.permalink}"]
    refute_includes issue.body_html, %Q[href="#{owner_private_issue.permalink}"]
  end

  test "over comment limit" do
    issue = create(:issue, issue_comments_count: (Issue::COMMENT_LIMIT - 1))
    refute issue.over_comment_limit?

    issue = create(:issue, issue_comments_count: Issue::COMMENT_LIMIT)
    assert issue.over_comment_limit?
  end

  context "#is_searchable" do
    test "is searchable when not spammy", spammy_only: true do
      issue = create(:issue)
      assert issue.is_searchable?
    end

    test "is not searchable when user_hidden" do
      issue = create(:issue)
      issue.stubs(:user_hidden).returns(true)
      refute issue.is_searchable?
    end

    test "is not searchable when creator is spammy", spammy_only: true do
      issue = create(:issue)
      issue.safe_user.stubs(:read_attribute).with(:spammy).returns(true)
      refute issue.is_searchable?
    end
  end

  context "#synchronize_search_index" do
    test "adds to search index when a normal issue" do
      issue = create(:issue)
      assert_enqueued_jobs 1, only: AddToSearchIndexJob do
        issue.synchronize_search_index
      end
    end

    test "does not add user_hidden issue to the search index" do
      issue = create(:issue)
      issue.stubs(:user_hidden).returns(true)
      assert_enqueued_jobs 0, only: AddToSearchIndexJob do
        issue.synchronize_search_index
      end
    end

    test "does not add a spammy user created issue to the search index", spammy_only: true do
      issue = create(:issue)
      issue.safe_user.stubs(:read_attribute).with(:spammy).returns(true)
      assert_enqueued_jobs 0, only: AddToSearchIndexJob do
        issue.synchronize_search_index
      end
    end

    test "removes from search index when user_hidden" do
      issue = create(:issue)
      issue.stubs(:user_hidden).returns(true)
      assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["issue", issue.id, issue.repository_id] do
        issue.synchronize_search_index
      end
    end

    test "removes from search index when user spammy", spammy_only: true do
      issue = create(:issue)
      issue.safe_user.stubs(:read_attribute).with(:spammy).returns(true)
      assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["issue", issue.id, issue.repository_id] do
        issue.synchronize_search_index
      end
    end

    test "enqueue 1 synchronize job when adding labels" do
      issue = create(:issue)
      help_wanted_label = create(:label, repository: issue.repository, name: "help wanted")

      assert_enqueued_jobs 1, only: AddToSearchIndexJob do
        perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
          issue.add_labels([help_wanted_label])
        end
      end
    end

    test "enqueue 1 synchronize job when deleting labels" do
      issue = create(:issue)
      help_wanted_label = create(:label, repository: issue.repository, name: "help wanted")
      issue.add_labels([help_wanted_label])

      assert_enqueued_jobs 1, only: AddToSearchIndexJob do
        perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
          issue.delete_labels([help_wanted_label])
        end
      end
    end

    test "enqueue 1 synchronize job when clearing labels" do
      issue = create(:issue)
      help_wanted_label = create(:label, repository: issue.repository, name: "help wanted")
      issue.add_labels([help_wanted_label])

      assert_enqueued_jobs 1, only: AddToSearchIndexJob do
        perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
          issue.clear_labels
        end
      end
    end

    test "enqueue 1 synchronize job when replacing labels" do
      issue = create(:issue)
      help_wanted_label = create(:label, repository: issue.repository, name: "help wanted")

      assert_enqueued_jobs 1, only: AddToSearchIndexJob do
        perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
          issue.replace_labels([help_wanted_label])
        end
      end
    end

    test "enqueue 1 synchronize job when locking issue" do
      repo = create(:repository, owner: @owner, admin: @owner)
      issue = create(:issue, repository: repo)

      assert_enqueued_jobs 1, only: AddToSearchIndexJob do
        perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
          issue.lock(@owner)
        end
      end
    end

    test "enqueue 1 synchronize job when unlocking issue" do
      repo = create(:repository, owner: @owner, admin: @owner)
      issue = create(:issue, repository: repo)
      issue.lock(@owner)

      assert_enqueued_jobs 1, only: AddToSearchIndexJob do
        perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
          issue.unlock(@owner)
        end
      end
    end
  end

  context "adding an IssueComment" do
    test "issue and connected project item are touched when an IssueComment is added" do
      issue = create(:issue, repository: @private_repo, user: @owner)
      memex_project = create(:memex_project, owner: @owner)
      item = create(:memex_project_item, memex_project: memex_project, content: issue)

      issue_timestamp = issue.updated_at
      item_timestamp = item.updated_at

      Timecop.freeze(3.hours.from_now) do
        create :issue_comment, :wait_for_orchestration, issue: issue, body: "hello!", user: @owner

        TouchMemexProjectItemsJob.perform_now(issue)

        item.reload

        refute_equal issue.updated_at, issue_timestamp
        refute_equal item.updated_at, item_timestamp
      end
    end
  end

  test "is deleted with repository" do
    repo = create(:public_repository)
    issue = create(:issue, repository: repo)
    other_issue = create(:issue)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = repo
      config.expect_destroyed = [issue]
      config.expect_not_destroyed = [other_issue]
    end
  end
end

class IssuesDeleteableByTest < GitHub::TestCase
  test "for user owned repos is true when the user is an admin on the repo" do
    user = create(:user)
    repo = create(:repository, owner: user, admin: user, force_user_owned: true)
    issue = create(:issue, repository: repo)
    assert issue.deleteable_by?(user)
  end

  test "for user owned repos is false when the user isn't an admin on the repo" do
    user = create(:user)
    repo = create(:repository, owner: user, admin: user, force_user_owned: true)
    issue = create(:issue, repository: repo)
    refute issue.deleteable_by?(create(:user))
    refute issue.deleteable_by?(nil)
  end

  test "for org owned repos is true when the setting is enabled and the user is an admin on the repo" do
    org_admin = create(:user)
    repo_admin = create(:user)
    org = create(:organization, admin: org_admin)
    org.allow_members_can_delete_issues(actor: org_admin)

    repo = create(:repository, owner: org)
    team = create(:team, organization: org)
    team.add_member(repo_admin, adder: org_admin)
    team.add_repository(repo, :admin)

    issue = create(:issue, repository: repo)
    assert issue.deleteable_by?(org_admin)
    assert issue.deleteable_by?(repo_admin)
  end

  test "for org owned repos is true when the setting is disabled and the user is an org owner" do
    org_admin = create(:user)
    repo_admin = create(:user)
    org = create(:organization, admin: org_admin)
    org.disallow_members_can_delete_issues(actor: org_admin)

    repo = create(:repository, owner: org)
    team = create(:team, organization: org)
    team.add_member(repo_admin, adder: org_admin)
    team.add_repository(repo, :admin)

    issue = create(:issue, repository: repo)
    assert issue.deleteable_by?(org_admin)
    refute issue.deleteable_by?(repo_admin)
  end

  test "for org owned repos is false when the setting is enabled and the user is not an admin on the repo" do
    org_admin = create(:user)
    non_repo_admin = create(:user)
    org = create(:organization, admin: org_admin)
    org.allow_members_can_delete_issues(actor: org_admin)

    repo = create(:repository, owner: org)
    team = create(:team, organization: org)
    team.add_member(non_repo_admin, adder: org_admin)
    team.add_repository(repo, :read)

    issue = create(:issue, repository: repo)
    refute issue.deleteable_by?(non_repo_admin)
  end

  test "for org owned repos is false when the setting is disabled and the user is an admin on the repo" do
    org_admin = create(:user)
    repo_admin = create(:user)
    org = create(:organization, admin: org_admin)
    refute_predicate org, :members_can_delete_issues?

    repo = create(:repository, owner: org)
    team = create(:team, organization: org)
    team.add_member(repo_admin, adder: org_admin)
    team.add_repository(repo, :admin)

    issue = create(:issue, repository: repo)
    refute issue.deleteable_by?(repo_admin)
  end
end

class DeleteIssueFgpTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @org = create(:business_plus_organization)
    @user = create(:user)
    @private_repo = create(:repository, owner: @org)
    @org_admin = @org.admin
    @private_issue = create(:issue, repository: @private_repo)

    @team = create :team, organization: @org
    @team.add_member @user
  end

  test "user with delete_issue FGP can delete issue" do
    @org.allow_members_can_delete_issues(actor: @org_admin)
    refute @private_issue.deleteable_by?(@user)
    grant_custom_role(user: @user, target: @private_repo, fgps: [:delete_issue])
    assert @private_issue.deleteable_by?(@user)
  end

  test "user with delete_issue FGP can't delete issue if org setting allows it" do
    refute @private_issue.deleteable_by?(@user)
    grant_custom_role(user: @user, target: @private_repo, fgps: [:delete_issue])
    refute @private_issue.deleteable_by?(@user)
  end

  test "member of team with delete_issue FGP can delete issue if org setting allows it" do
    @org.allow_members_can_delete_issues(actor: @org_admin)
    refute @private_issue.deleteable_by?(@user)
    grant_custom_role(user: @user, target: @private_repo, fgps: [:delete_issue])
    assert @private_issue.deleteable_by?(@user)
  end

  test "member of team with delete_issue FGP cannot delete issue if org setting allows it but owning business force disallows it" do
    business = create(:business)
    business.add_organization(@org)

    @org.allow_members_can_delete_issues(actor: @org_admin)
    business.disallow_members_can_delete_issues(force: true, actor: @org_admin)
    @org.reload
    refute @org.members_can_delete_issues?
    grant_custom_role(user: @team, target: @private_repo, fgps: [:delete_issue])
    refute @private_issue.deleteable_by?(@user)
  end

  test "member of team with delete_issue FGP can delete issue if org setting allows and business does not force disallow it" do
    business = create(:business)
    business.add_organization(@org)

    @org.allow_members_can_delete_issues(actor: @org_admin)
    business.disallow_members_can_delete_issues(actor: @org_admin)
    @org.reload
    assert @org.members_can_delete_issues?

    grant_custom_role(user: @team, target: @private_repo, fgps: [:delete_issue])
    assert @private_issue.deleteable_by?(@user)
  end

  test "member of team with delete_issue FGP can delete issue if org setting denies but business forces allow it" do
    business = create(:business)
    business.add_organization(@org)

    @org.disallow_members_can_delete_issues(actor: @org_admin)
    business.allow_members_can_delete_issues(force: true, actor: @org_admin)
    @org.reload
    assert @org.members_can_delete_issues?

    grant_custom_role(user: @team, target: @private_repo, fgps: [:delete_issue])
    assert @private_issue.deleteable_by?(@user)
  end

  test "member of team with delete_issue FGP cannot delete issue if org setting forbids it " do
    refute @private_issue.deleteable_by?(@user)
    grant_custom_role(user: @team, target: @private_repo, fgps: [:delete_issue])
    refute @private_issue.deleteable_by?(@user)
  end

  test "user with unrelated FGP cannot delete issue" do
    @org.allow_members_can_delete_issues(actor: @org_admin)

    refute @private_issue.deleteable_by?(@user)
    grant_custom_role(user: @user, target: @private_repo, fgps: [:add_label])
    refute @private_issue.deleteable_by?(@user)
  end
end

class IssuesWithTeamsAndOrganizationsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @repo = create :repository, owner: @org
    @team = create :team, organization: @org
    @team.add_member @user
    @team.add_member @org.admins.first
    @team.add_repository @repo, :pull
  end

  test "create issue with team mention that author belongs to", feature_disabled: :notifyd_issue_watch_activity_notify do
    assert_performed_with job: SubscribeAndNotifyJob do
      issue = build :issue, repository: @repo, user: @user,
        body: "hey @#{@org.display_login}/#{@team.slug}"
      issue.save!
      assert issue.subscribed?(@user)
      assert issue.subscribed?(@org.admins.first)
    end
  end

  test "create issue with team mention that results in n subscribed issue events" do
    issue = build :issue, repository: @repo, user: @user, body: "hey @#{@org.display_login}/#{@team.slug}"
    assert_performed_with job: CreateSubscribedIssueEventsJob do
      issue.save!
    end
    assert_equal 2, issue.events.where(event: "subscribed").size
  end

  test "comment on issue with team mention that results in n subscribed issue events" do
    issue = create :issue, repository: @repo, user: @user
    issue_comment = create :issue_comment, :wait_for_orchestration, issue: issue, user: @user
    assert_performed_with job: CreateSubscribedIssueEventsJob do
      issue_comment.body = "hello @#{@org.display_login}/#{@team.slug}!"
      issue_comment.save!
      assert_equal 2, issue.events.where(event: "subscribed").size
    end
  end

  if GitHub.email_verification_enabled?
    test "allows user to edit issue where original author does not have verified emails", skip_with_all_emus: true do
      user = create(:user)
      admin = create(:user)
      issue = create(:issue, user: user)
      issue.repository.add_member(admin, action: :admin)

      # Setup that ensures that a user is forced to verify their email
      # This is a distinct check from GitHub.email_verification_enabled?
      GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
      admin.require_email_verification!
      user.require_email_verification!
      user.emails.verified.each(&:unverify!)
      admin.emails.first.verify!

      assert user.reload.must_verify_email?
      refute admin.reload.must_verify_email?

      # set modifying user to be the admin, to simulate
      # an admin editing a comment
      issue.modifying_user = admin
      issue.body = "updating test"
      issue.save!

      assert_equal "updating test", issue.reload.body
    end
  end
end

class IssuesWithBlobReferencesTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)

    base_ref = @repo.heads.find_or_build("master")

    base_ref.append_commit({ message: "a change", committer: @owner }, @owner) do |files|
      files.add("file001", "need\nthree\nlines")
      files.add("file002", "only\ntwo here")
    end
    @commit_oid  = @repo.refs["master"].commit.oid

    @bad_permalink  = build_permalink("9999999999999999999999999999999999999999", "foo", 1, 2)
    @permalink1     = build_permalink(@commit_oid, "file001", 1, 2)
    @permalink2     = build_permalink(@commit_oid, "file002", 1, 2)
    @permalink1_with_diff_lines = build_permalink(@commit_oid, "file001", 1, 3)
  end

  def build_permalink(commit_oid, filepath, range_start, range_end)
    "https://#{GitHub.urls.host_name}/#{@repo.name_with_display_owner}/blob/#{commit_oid}/#{filepath}\#L#{range_start}-L#{range_end}"
  end
end

# This one is broken out so we don't use a real cache in all the other tests
class IssueCreationRateLimitTest < GitHub::TestCase
  setup_once do
    enable_cache_storage
  end

  setup do
    reset_cache
  end

  teardown_once do
    disable_cache_storage
  end

  test "issues cannot be created faster than the rate limit" do
    enable_content_creation_rate_limiting
    user = create(:user)
    6.times do |_i|
      comment = create :issue, user: user
      assert_empty comment.errors
    end

    begin
      create :issue, user: user
    rescue ActiveRecord::RecordInvalid => e
      assert_match "submitted too quickly", e.message
    end
  end
end

if GitHub.spamminess_check_enabled? && !TestEnv.test_with_all_emus?
  class IssueSpamTest < GitHub::TestCase
    fixtures do
      @regular_viewer = create(:user)
      @anonymous_viewer = nil
      @staff_viewer = create :staff_admin_user
      @spammer = create(:user, spammy: true)

      @repo = create :repository, name: "rjd2", owner: @regular_viewer
      @spammy_issue = create :issue, repository: @repo, user: @spammer
      @issue = create :issue, repository: @repo, user: @regular_viewer
    end

    test "hides spammy issue from regular user" do
      assert !@issue.hide_from_user?(@spammer)
      assert @spammy_issue.hide_from_user?(@regular_viewer)
    end

    test "hides spammy issue from anonymous user" do
      assert !@issue.hide_from_user?(@anonymous_viewer)
      assert @spammy_issue.hide_from_user?(@anonymous_viewer)
    end

    test "doesn't hide spammy issue from staff user" do
      assert !@issue.hide_from_user?(@staff_viewer)
      assert !@spammy_issue.hide_from_user?(@staff_viewer)
    end

    test "doesn't hide spammy issue from user themself" do
      assert !@issue.hide_from_user?(@spammer)
      assert !@spammy_issue.hide_from_user?(@spammer)
    end

    test ".spammy returns only spammy issues" do
      assert_includes Issue.spammy, @spammy_issue
      refute_includes Issue.spammy, @issue
    end

    test ".not_spammy returns only not spammy issues" do
      assert_includes Issue.not_spammy, @issue
      refute_includes Issue.not_spammy, @spammy_issue
    end

    test ".filter_spam_for has spammy issues only visible to spammer" do
      assert_includes Issue.filter_spam_for(@spammer), @spammy_issue
      refute_includes Issue.filter_spam_for(@user), @spammy_issue
    end

    test ".filter_spam_for has spammy issues not visible anonymous users" do
      assert_includes Issue.filter_spam_for(nil), @issue
      refute_includes Issue.filter_spam_for(nil), @spammy_issue
    end

    test "saving a body strips spammy unicode characters" do
      issue = create :issue, repository: @repo, user: @repo.owner
      body = "test string " + "a" + ("\u034c" * 50)
      issue.body = body
      assert issue.save
      issue.reload
      assert_equal "test string a", issue.body
    end

    test "saving a body maintains legitimate unicode characters" do
      issue = create :issue, repository: @repo, user: @repo.owner
      body = "test string " + "a" + ("\u034c" * 3)
      issue.body = body
      assert issue.save
      issue.reload
      assert_equal "test string a" + ("\u034c" * 3), issue.body
    end
  end
end

class IssueBatchMethodsTest < GitHub::TestCase
  test "closed_by_commit_oids" do
    user = create(:user)
    repo = create(:repository, owner: user, from_example: :simple)

    issue = create(:issue, repository: repo, title: "issue title", body: "issue body", user: user)
    commit = repo.commits.create({ message: "commit 1 closes ##{issue.number}", committer: issue.user }, nil) { |_files| }
    commit2 = repo.commits.create({ message: "commit 2 closes ##{issue.number}", committer: issue.user }, nil) { |_files| }

    create(:issue_event, event: "referenced", issue: issue, repository: repo, commit_id: commit.oid)
    create(:issue_event, event: "referenced", issue: issue, repository: repo, commit_id: commit2.oid)

    create(:issue_event, event: "closed", issue: issue, actor: user, commit_id: commit.oid)
    create(:issue_event, event: "closed", issue: issue, actor: user, commit_id: commit2.oid)

    closed_by_commit_oids = issue.closed_by_commit_oids

    assert_includes closed_by_commit_oids, commit.oid
    assert_includes closed_by_commit_oids, commit2.oid
  end
end
