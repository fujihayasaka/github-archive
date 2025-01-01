# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTest < GitHub::TestCase
  include DiscussionsTestHelper
  include GitHub::LoggerHelper
  include HydroTestHelpers
  include StringFromBinaryTestHelper

  fixtures do
    create_discussions_authz_fixtures

    @public_discussion = Timecop.freeze(1.day.ago) do
      create(:discussion, :question, repository: @repo)
    end

    @label0, @label1, @label2 = create_list(:label, 3, repository: @repo)

    private_discussion_author = create(:verified_user)
    @private_repo.add_member(private_discussion_author)
    @private_discussion = create(:discussion, repository: @private_repo,
      user: private_discussion_author)

    @org_discussion = create(:discussion, repository: @org_repo)
    @org_private_discussion = create(:discussion, repository: @org_private_repo)
    @org_without_default_permission_repo_discussion = create(:discussion,
      repository: @org_without_default_permission_repo,
    )
    @org_without_default_permission_private_repo_discussion = create(:discussion,
      repository: @org_without_default_permission_private_repo,
    )

    @business_internal_discussion = create(:discussion, :question, repository: @business_internal_repo)

    @spammer = create(:spammy_user, :verified)
    @staff = create(:verified_user, :staff)

    User.create_ghost
  end

  setup do
    @matrix = DiscussionsTestHelper::AccessMatrix.new(self)

    @matrix.setup_subjects(
      repo: @public_discussion,
      private_repo: @private_discussion,
      org_repo: @org_discussion,
      org_private_repo: @org_private_discussion,
      org_without_default_permission_repo: @org_without_default_permission_repo_discussion,
      org_without_default_permission_private_repo: @org_without_default_permission_private_repo_discussion,
      business_internal_repo: @business_internal_discussion,
    )
  end

  def matrix_lock_discussions
    @matrix.each_subject do |discussion|
      discussion.lock(actor: discussion.repository.in_organization? ? @admin : @owner)
    end
  end

  def matrix_turn_off_discussions
    @matrix.each_repo { |repo, admin| repo.turn_off_discussions(actor: admin, instrument: false) }
  end

  def matrix_lock_repos_for_migration
    @matrix.each_repo { |repo| repo.lock_for_migration }
  end

  def matrix_archive_repos
    @matrix.each_repo { |repo| repo.set_archived }
  end

  context ".body_with_poll" do
    test "returns given body when poll is nil" do
      body = "Hello world"
      assert_equal body, Discussion.body_with_poll(body, nil)
    end

    test "returns body combined with Markdown representation of poll" do
      body = "Hello world"
      poll = create(:discussion_poll, question: "How doth the little crocodile improve his shining tail?",
        option_texts: ["Pour the waters of the Nile on every golden scale", "Cheerfully grin",
                       "Neatly spread his claws"])
      expected = "Hello world\n\n----\n\nPoll: How doth the little crocodile improve his shining tail?\n\n" \
        "- Pour the waters of the Nile on every golden scale\n" \
        "- Cheerfully grin\n" \
        "- Neatly spread his claws"
      assert_equal expected, Discussion.body_with_poll(body, poll)
    end

    test "returns body combined with given string poll with extra space stripped" do
      body = "  Hello world\t  \n"
      poll = "foo\n"
      assert_equal "Hello world\n\n----\n\nPoll: foo", Discussion.body_with_poll(body, poll)
    end
  end

  context "#last_read_at_cache_key_for" do
    test "differentiates between viewers" do
      refute_equal @admin, @owner, "need two different users"

      key1 = @public_discussion.last_read_at_cache_key_for(viewer: @admin)
      key2 = @public_discussion.last_read_at_cache_key_for(viewer: @owner)

      assert_predicate key1, :present?
      assert_predicate key2, :present?
      refute_equal key1, key2
    end

    test "differentiates between discussions" do
      key1 = @public_discussion.last_read_at_cache_key_for(viewer: @admin)
      key2 = @private_discussion.last_read_at_cache_key_for(viewer: @admin)

      assert_predicate key1, :present?
      assert_predicate key2, :present?
      refute_equal key1, key2
    end

    test "returns nil for no viewer" do
      assert_nil @public_discussion.last_read_at_cache_key_for(viewer: nil)
    end
  end

  context "#dom_id" do
    test "returns nil for new discussion that hasn't been saved" do
      assert_nil Discussion.new.dom_id
    end

    test "returns a plain-text identifier for existing discussion" do
      assert_equal "discussion-#{@public_discussion.id}", @public_discussion.dom_id
    end

    test "returns different values for different discussions" do
      result1 = @public_discussion.dom_id
      result2 = @org_discussion.dom_id
      refute_equal result1, result2
    end
  end

  context "#permalink_id" do
    test "returns nil for new discussion that hasn't been saved" do
      assert_nil Discussion.new.permalink_id
    end

    test "includes the discussion's dom_id" do
      assert_equal "#{@public_discussion.dom_id}-permalink", @public_discussion.permalink_id
    end
  end

  context "#last_read_at_for" do
    test "returns nil when not given a viewer" do
      assert_nil @public_discussion.last_read_at_for(viewer: nil)
    end

    test "returns nil when no timestamp has been saved for the given viewer for the discussion" do
      assert_nil @public_discussion.last_read_at_for(viewer: @owner)
    end

    test "returns the saved time for the given viewer for that discussion" do
      time = Time.now
      assert @public_discussion.set_last_read_at_for(viewer: @owner, time: time)

      result = @public_discussion.last_read_at_for(viewer: @owner)

      refute_nil result
      assert_in_delta time, result, 1.second
    end
  end

  context "#set_last_read_at_for" do
    test "writes the given timestamp to the key-value store for the discussion + viewer" do
      expected_key = @public_discussion.last_read_at_cache_key_for(viewer: @owner)
      assert_nil Discussions::Kv.store.get(expected_key).value { nil }

      time = Time.now
      assert @public_discussion.set_last_read_at_for(viewer: @owner, time: time),
        "should have returned true to indicate success"

      result = Discussions::Kv.store.get(expected_key).value { nil }
      refute_nil result, "should have written a value to the key-value store in the expected place"
      assert_equal time.iso8601, result
    end

    test "returns false when no viewer is given" do
      refute @public_discussion.set_last_read_at_for(viewer: nil, time: Time.now)
    end
  end

  context "#title" do
    test "is stripped before validation" do
      @public_discussion.title = " my title "

      @public_discussion.validate

      assert_equal "my title", @public_discussion.title
    end
  end

  context "#last_reported_at" do
    test "returns date of latest abuse report for the discussion" do
      report = create(:abuse_report, reported_content: @org_discussion)
      assert_equal report.created_at, @org_discussion.last_reported_at
    end
  end

  context "#viewer_can_read_user_content_edits?" do
    test "requires read+" do
      @matrix.user_scenarios(
        :viewer_can_read_user_content_edits?,
        none: false,
        read: true,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end
  end

  context "#public?" do
    test "true for discussion in a public repository" do
      assert_predicate @public_discussion, :public?
    end

    test "false for discussion in a private repository" do
      private_repo = create(:private_repository, has_discussions: true)
      private_discussion = create(:discussion, repository: private_repo)
      refute_predicate private_discussion, :public?
    end
  end

  context "#in_organization?" do
    test "true for org discussion" do
      assert_predicate @org_discussion, :in_organization?
    end

    test "false for user-owned repo discussion" do
      refute_predicate @public_discussion, :in_organization?
    end
  end

  context "#from_issue" do
    test "returns an unsaved discussion initialized from a given issue" do
      issue = create(:issue, repository: @repo, user: @rando)
      category = @repo.discussion_categories.last

      discussion = Discussion.from_issue(issue, category: category)

      refute_nil discussion
      refute_predicate discussion, :persisted?
      assert_equal issue.id, discussion.issue_id
      assert_predicate discussion, :converting?
      assert_equal issue.issue_comments_count, discussion.comment_count
      assert_equal issue.user_hidden?, discussion.user_hidden?
      assert_equal @rando.id, discussion.user_id
      assert_equal @repo.id, discussion.repository_id
      assert_equal category, discussion.category
      assert_equal issue.title, discussion.title
      assert_equal issue.body, discussion.body
      assert_equal issue.created_at, discussion.created_at
      assert_equal issue.updated_at, discussion.updated_at
      refute_equal issue.number, discussion.number
    end

    test "sets ghost as the author if the issue author was deleted" do
      issue = create(:issue, repository: @repo, user: @rando)
      @rando.delete
      category = @repo.discussion_categories.last
      issue.reload

      discussion = Discussion.from_issue(issue, category: category)
      assert_predicate discussion.user, :ghost?
    end
  end

  context "#converted_from_issue?" do
    test "true for discussion with an issue_id and converted_at" do
      discussion = build(:discussion, issue_id: 123, converted_at: Time.now)
      assert_predicate discussion, :converted_from_issue?
    end

    test "false for discussion with an issue_id and converted_at that is still converting" do
      discussion = build(:discussion, issue_id: 123, converted_at: Time.now, state: :converting)
      refute_predicate discussion, :converted_from_issue?
    end

    test "false for discussion with blank issue_id and present converted_at" do
      discussion = build(:discussion, issue_id: nil, converted_at: Time.now)
      refute_predicate discussion, :converted_from_issue?
    end

    test "false for discussion with present team_post_id and present converted_at" do
      discussion = build(:discussion, team_post_id: 123, converted_at: Time.now)
      refute_predicate discussion, :converted_from_issue?
    end

    test "false for discussion with present issue_id and blank converted_at" do
      discussion = build(:discussion, issue_id: 123, converted_at: nil)
      refute_predicate discussion, :converted_from_issue?
    end
  end

  context "#converted_from_team_discussion?" do
    test "true for discussion with a team_post_id and converted_at" do
      discussion = build(:discussion, team_post_id: 123, converted_at: Time.now)
      assert_predicate discussion, :converted_from_team_discussion?
    end

    test "false for discussion with a team_post_id and converted_at when still converting" do
      discussion = build(:discussion, team_post_id: 123, converted_at: Time.now, state: :converting)
      refute_predicate discussion, :converted_from_team_discussion?
    end

    test "false for discussion with blank team_post_id and present converted_at" do
      discussion = build(:discussion, team_post_id: nil, converted_at: Time.now)
      refute_predicate discussion, :converted_from_team_discussion?
    end

    test "false for discussion with present issue_id and present converted_at" do
      discussion = build(:discussion, issue_id: 123, converted_at: Time.now)
      refute_predicate discussion, :converted_from_team_discussion?
    end

    test "false for discussion with present team_post_id and blank converted_at" do
      discussion = build(:discussion, team_post_id: 123, converted_at: nil)
      refute_predicate discussion, :converted_from_team_discussion?
    end
  end

  context ".from_team_post" do
    test "it returns a new discussion from an existing team post" do
      team_post = create(:discussion_post, title: "Team Post", body: "Team Post Body", user: @private_discussion.user)

      discussion = Discussion.from_team_discussion(team_post, repository: @private_repo, category: @private_repo.discussion_categories.last)

      assert_equal "Team Post", discussion.title
      assert_equal "Team Post Body", discussion.body
      assert_equal @private_repo, discussion.repository
      assert_equal @private_repo.discussion_categories.last, discussion.category
      assert discussion.valid?
    end
  end

  context "#async_reactable_by?" do
    test "true for read+" do
      @matrix.user_scenarios(
        :async_reactable_by?,
        none: false,
        read: true,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false when user is blocked by author" do
      @public_discussion.user.block(@rando)

      refute @public_discussion.async_reactable_by?(@rando).sync
    end
  end

  context "#can_comment? and #async_can_comment?" do
    test "requires read+ access" do
      @matrix.user_scenarios(
        :can_comment?,
        none: false,
        read: true,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "returns false for a nil actor" do
      refute @public_discussion.can_comment?(nil)
      refute @public_discussion.async_can_comment?(nil).sync
    end

    test "returns false when repository is archived" do
      matrix_archive_repos

      @matrix.user_scenarios(
        :can_comment?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    if GitHub.email_verification_enabled?
      test "returns false for user without verified email address" do
        refute @public_discussion.can_comment?(@unverified)
        refute @public_discussion.async_can_comment?(@unverified).sync
      end
    else
      test "returns true for user without verified email address" do
        assert @public_discussion.can_comment?(@unverified)
        assert @public_discussion.async_can_comment?(@unverified).sync
      end
    end

    test "return false when repository is locked" do
      matrix_lock_repos_for_migration

      @matrix.user_scenarios(
        :can_comment?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "requires write+ access when discussion locked" do
      matrix_lock_discussions

      @matrix.user_scenarios(
        :can_comment?,
        none: false,
        read: false,
        triage: false,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "returns true when repository owner has blocked user with write access" do
      blocked_user = create(:verified_user)
      @repo.add_member(blocked_user, action: :write)
      @owner.block(blocked_user)

      assert @public_discussion.can_comment?(blocked_user)
      assert @public_discussion.async_can_comment?(blocked_user).sync
    end

    test "returns true when organization repository owner has blocked user with admin access" do
      blocked_user = create(:verified_user)
      @org_repo.add_member(blocked_user, action: :admin)
      @org.block(blocked_user)

      assert @org_discussion.can_comment?(blocked_user)
      assert @org_discussion.async_can_comment?(blocked_user).sync
    end

    test "returns true when organization admin blocked user with repo admin access" do
      blocked_user = create(:verified_user)
      @org_repo.add_member(blocked_user, action: :admin)
      @org_admin.block(blocked_user)

      assert @org_discussion.can_comment?(blocked_user)
      assert @org_discussion.async_can_comment?(blocked_user).sync
    end

    test "returns false when repo has_discussions is false" do
      matrix_turn_off_discussions

      @matrix.user_scenarios(
        :can_comment?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "returns true for integrations with write+ permissions" do
      @matrix.bot_scenarios(
        :can_comment?,
        none: false,
        read: false,
        write: true,
      )
    end

    test "returns true for integrations with write+ permissions when the discussion is locked" do
      matrix_lock_discussions

      @matrix.bot_scenarios(
        :can_comment?,
        none: false,
        read: false,
        write: true,
      )
    end

    test "returns false for integrations when has_discussions is false" do
      matrix_turn_off_discussions

      @matrix.bot_scenarios(
        :can_comment?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "returns false for integrations when the repo is locked" do
      matrix_lock_repos_for_migration

      @matrix.bot_scenarios(
        :can_comment?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "returns false for integrations when the repo is archived" do
      matrix_archive_repos

      @matrix.bot_scenarios(
        :can_comment?,
        none: false,
        read: false,
        write: false,
      )
    end
  end

  context "#readable_by? and #async_readable_by?" do
    test "requires read+" do
      @matrix.user_scenarios(
        :readable_by?,
        none: false,
        read: true,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false for author of discussion when user no longer has access to repository" do
      discussion = create(:discussion, repository: @private_repo, user: @rando)
      refute discussion.readable_by?(@rando)
      refute discussion.async_readable_by?(@rando).sync
    end

    test "false when setting disabled" do
      matrix_turn_off_discussions

      @matrix.user_scenarios(
        :readable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "true for anonymous user in a public repository" do
      assert @public_discussion.readable_by?(nil)
      assert @public_discussion.async_readable_by?(nil).sync
    end

    test "false for anonymous user in a private repository" do
      refute @private_discussion.readable_by?(nil)
      refute @private_discussion.async_readable_by?(nil).sync
    end

    test "true for bot users of integrations with read+ access" do
      @matrix.bot_scenarios(
        :readable_by?,
        install_needed: false,
        discussions_permission_needed: false,
        none: false,
        read: true,
        write: true,
      )
    end

    test "false for bot user of integration when discussions are disabled" do
      matrix_turn_off_discussions

      @matrix.bot_scenarios(
        :readable_by?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "doesn't call authzd if repo is public" do
      ::Permissions::Enforcer.expects(:authorize).never

      @public_discussion.readable_by?(nil)
      @public_discussion.async_readable_by?(nil).sync
    end

    test "false when containing repository has been deleted" do
      @matrix.each_subject { |discussion| discussion.repository = nil }

      @matrix.user_scenarios(
        :readable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "true for read+ when owner of containing repository has been deleted" do
      # We can't use the matrix here because a bunch of access scenarios (business-owned internal repositories)
      # break without a valid owner.
      @private_discussion.repository.owner = nil

      assert @private_discussion.readable_by?(@collaborator)
      assert @private_discussion.async_readable_by?(@collaborator)
    end
  end

  context "#async_labelable_by? and #labelable_by?" do
    test "requires triage+" do
      @matrix.user_scenarios(
        :labelable_by?,
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "returns false for an anonymous user" do
      refute @org_discussion.async_labelable_by?(nil).sync
      refute @org_discussion.labelable_by?(nil)
    end

    test "requires write permissions for integrations" do
      @matrix.bot_scenarios(
        :labelable_by?,
        none: false,
        read: false,
        write: true,
      )
    end

    test "accepts actor: as a keyword argument for Issue compatibility" do
      assert @public_discussion.labelable_by?(actor: @owner)
    end
  end

  context "#poll_votable_by? and #async_votable_by?" do
    test "true for read+" do
      @matrix.user_scenarios(
        :poll_votable_by?,
        none: false,
        read: true,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )

      @matrix.user_scenarios(
        :async_poll_votable_by?,
        none: false,
        read: true,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false when user is blocked by author" do
      @public_discussion.user.block(@rando)
      refute @public_discussion.poll_votable_by?(@rando)
      refute @public_discussion.async_poll_votable_by?(@rando).sync
    end
  end

  context "#author" do
    test "returns the user if they exist" do
      discussion = build(:discussion, user: @owner)
      assert_equal @owner, discussion.author
    end

    test "returns the ghost user if the original user is gone" do
      @public_discussion.user = nil
      refute_nil @public_discussion.author
      assert_equal User.ghost, @public_discussion.author
    end
  end

  context "#authored_by_ghost?" do
    test "true when user does not exist" do
      @public_discussion.user = nil
      assert_predicate @public_discussion, :authored_by_ghost?
    end

    test "false when user exists" do
      refute_nil @public_discussion.user
      refute_predicate @public_discussion, :authored_by_ghost?
    end
  end

  context "#reference_from_commit" do
    test "allows us to call the method without raising an error" do
      event = Timecop.freeze(1.hour.ago) { create(:discussion_event, discussion: @public_discussion) }

      assert_nothing_raised do
        @public_discussion.reference_from_commit(event.actor, "some-commit-id")
      end
    end
  end

  context "validations" do
    test "body cannot be too long" do
      expected_characters = 65536
      body = "a" * (MYSQL_UNICODE_BLOB_LIMIT + 1)
      discussion = build(:discussion)

      discussion.body = body

      refute_predicate discussion, :valid?, "#{discussion.errors.full_messages}"
      assert_equal discussion.errors.full_messages.first, "Body is too long (maximum is #{expected_characters} characters)"
    end

    test "body can be empty if discussion category supports polls" do
      body = ""
      repo = create(:repository)
      poll_category = create(:discussion_category, supports_polls: true, repository: repo)
      discussion = build(:discussion, category: poll_category, repository: repo)

      discussion.body = body

      assert_predicate discussion, :valid?
    end

    test "requires a user at creation when in 'open' state" do
      discussion = Discussion.new
      refute_predicate discussion, :valid?
      assert_includes discussion.errors[:user], "can't be blank"
    end

    test "does not require a user at creation when in 'converting' state" do
      issue = create(:issue, repository: @repo)
      issue.user.delete
      issue.reload
      converting_discussion = Discussion.from_issue(issue, category: @repo.discussion_categories.last)
      assert_predicate converting_discussion, :converting?
      assert_predicate converting_discussion.user, :ghost?
      assert_predicate converting_discussion, :valid?
    end

    test "does not require a user on update" do
      discussion = create(:discussion)
      refute_nil discussion.user
      discussion.user = nil
      assert discussion.save
      assert_nil discussion.reload.user
    end

    test "requires a repository" do
      discussion = Discussion.new
      refute_predicate discussion, :valid?
      assert_includes discussion.errors[:repository], "must exist"
    end

    test "requires a category" do
      discussion = Discussion.new
      refute_predicate discussion, :valid?
      assert_includes discussion.errors[:category], "must exist"
    end

    test "requires a category within the same repository" do
      distant_category = create :discussion_category
      discussion = Discussion.new(repository: @repo, category: distant_category)
      refute_predicate discussion, :valid?
      assert_includes discussion.errors[:category], "must belong to the same repository"
    end

    test "requires an issue when converting" do
      discussion = Discussion.new(state: :converting)
      refute_predicate discussion, :valid?
      assert_includes discussion.errors[:issue], "must be specified if state = converting"
    end

    test "requires user to have a verified email address at creation" do
      unverified_user = create(:user)
      discussion = build(:discussion, user: unverified_user)
      refute_predicate discussion, :valid?
      assert_includes discussion.errors[:user], "must have a verified email address"
    end if GitHub.email_verification_enabled?

    test "does not require user to have a verified email address on update" do
      @public_discussion.user = create(:user)
      assert_predicate @public_discussion, :valid?
    end if GitHub.email_verification_enabled?

    test "does not require user to have verified email address at creation if converting from issue" do
      unverified_user = create(:user)
      discussion = build(:discussion, user: unverified_user, state: :converting,
        issue: create(:issue))
      assert_predicate discussion, :valid?
    end if GitHub.email_verification_enabled?

    test "does not require bot to have verified email address" do
      bot = make_integration_installation(target: @owner).bot
      discussion = build(:discussion, user: bot)
      assert_predicate discussion, :valid?
    end

    test "requires an error reason when in error state" do
      discussion = Discussion.new(state: :error)
      refute_predicate discussion, :valid?
      assert_includes discussion.errors[:error_reason], "must be specified when state = error"
    end

    test "requires the chosen comment be on the discussion" do
      discussion = create(:discussion)
      discussion_comment = create(:discussion_comment)

      discussion.chosen_comment = discussion_comment

      refute_predicate discussion, :valid?
      assert_includes discussion.errors[:chosen_comment], "is not for this discussion"
    end

    test "allows the chosen comment to be a child comment" do
      child_comment = create(:discussion_comment, :nested, discussion: @public_discussion)

      @public_discussion.chosen_comment = child_comment

      assert_predicate @public_discussion, :valid?
      refute_includes @public_discussion.errors[:chosen_comment], "cannot be a reply to another comment"
    end

    test "requires user not be blocked by the repo owner" do
      repo_owner = create(:user, login: "repoowner")
      repo = create(:repository, owner: repo_owner, has_discussions: true)
      blocked_user = create(:user, login: "blockeduser")
      repo_owner.block(blocked_user)
      discussion = build(:discussion, repository: repo, user: blocked_user)

      refute discussion.save
      assert_includes discussion.errors[:user], "cannot post at this time"
    end

    test "requires a valid discussion_type" do
      assert_raises ArgumentError do
        build(:discussion, discussion_type: :butts)
      end
    end

    test "requires user can announce if the new discussion is an announcement" do
      category = @repo.discussion_categories.find_by(name: "Announcements")
      category ||= create :discussion_category, repository: @repo, name: "Announcements", supports_announcements: true

      annnouncement = build(:discussion, category: category, repository: @repo, user: @rando)

      refute_predicate annnouncement, :valid?
      assert_includes annnouncement.errors[:category], "is not accessible to the actor"
    end

    test "requires user can announce when moving discussion to announcement category" do
      announcement = create(:discussion, :question, repository: @repo, user: @rando)
      assert_predicate announcement, :valid?

      category = @repo.discussion_categories.find_by(name: "Announcements")
      category ||= create(:discussion_category,
        repository: @repo,
        name: "Announcements",
        supports_announcements: true,
      )
      announcement.actor = @rando
      announcement.category = category
      refute_predicate announcement, :valid?
      assert_includes announcement.errors[:category], "is not accessible to the actor"
    end

    test "requires the selected category to not be marked for deletion" do
      category = create :discussion_category, repository: @repo
      category.mark_as_deleting!
      discussion = build :discussion, category: category

      refute_predicate discussion, :valid?
      assert_includes discussion.errors[:category], "is being deleted"
    end

    test "sets number on create, based on repository" do
      repo = create(:repository, has_discussions: true)

      discussion1 = build(:discussion, repository: repo)
      assert_nil discussion1.number
      assert discussion1.save
      assert_equal 1, discussion1.number

      discussion2 = build(:discussion, repository: repo)
      assert_nil discussion2.number
      assert discussion2.save
      assert_equal 2, discussion2.number

      other_repo = create(:repository, has_discussions: true)

      discussion3 = build(:discussion, repository: other_repo)
      assert_nil discussion3.number
      assert discussion3.save
      assert_equal 1, discussion3.number
    end

    context "when collaborator-only interaction limits are enabled" do
      test "non-collaborator cannot create a discussion" do
        interaction = RepositoryInteractionAbility.new(@org_repo)
        interaction.set_ability(:collaborators_only, @admin)

        ex = assert_raises(ActiveRecord::RecordInvalid) do
          create :discussion, repository: @org_repo, user: @rando
        end
        assert_equal "Validation failed: could not be created. Interactions on this repository have been restricted to collaborators only.",
          ex.message
      end

      test "collaborator can create a discussion" do
        interaction = RepositoryInteractionAbility.new(@org_repo)
        interaction.set_ability(:collaborators_only, @admin)

        discussion = create :discussion, repository: @org_repo, user: @writer
        assert_predicate discussion, :valid?
      end

      test "non-collaborator cannot edit their discussion" do
        interaction = RepositoryInteractionAbility.new(@org_repo)
        interaction.set_ability(:collaborators_only, @admin)

        refute @org_discussion.update_body("Brand new body", @org_discussion.user)

        assert_includes @org_discussion.errors[:base],
          "could not be created. Interactions on this repository have been restricted to collaborators only."
      end

      test "collaborator can edit the non-collaborator's discussion" do
        interaction = RepositoryInteractionAbility.new(@org_repo)
        interaction.set_ability(:collaborators_only, @admin)

        assert @org_discussion.update_body("Brand new body", @writer)

        assert_empty @org_discussion.errors[:base]
      end
    end if GitHub.interaction_limits_enabled?

    test "requires a body on create when not converting and category does not support polls" do
      repo = create(:repository)
      non_polls_category = create(:discussion_category, repository: repo, supports_polls: false)
      invalid_discussion = build(:discussion, state: :open, body: nil, repository: repo, category: non_polls_category)
      valid_discussion = build(:discussion, state: :open, body: "Hi", repository: repo, category: non_polls_category)

      refute_predicate invalid_discussion, :valid?
      assert_predicate valid_discussion, :valid?
    end

    test "does not require a body on create when converting" do
      issue = create(:issue, repository: @repo)
      discussion = build(
        :discussion,
        body: nil,
        category: @repo.discussion_categories.last,
        issue: issue,
        repository: @repo,
        state: :converting,
      )

      assert_predicate discussion, :valid?
    end

    test "does not require a body on update" do
      issue = create(:issue, repository: @repo)
      discussion = create(
        :discussion,
        :locked,
        body: nil,
        category: @repo.discussion_categories.last,
        issue: issue,
        repository: @repo,
        state: :converting,
      )

      assert_predicate discussion, :valid?
    end

    test "cannot change a poll's category to one that doesn't support polls" do
      repo = create(:repository, has_discussions: true)

      repo.discussion_categories.destroy_all

      polls_category = create(:discussion_category, repository: repo, name: "Cool Polls", supports_polls: true)
      not_polls_category = create(:discussion_category, repository: repo, name: "No Cool Polls", supports_polls: false)

      discussion = create(
        :discussion,
        body: "Hello this is the discussion body",
        category: polls_category,
        repository: repo,
      )

      discussion.update(category: not_polls_category)

      refute_predicate discussion, :valid?
    end

    test "can change a poll's category to one that does support polls" do
      repo = create(:repository, has_discussions: true)

      repo.discussion_categories.destroy_all

      polls_category = create(:discussion_category, repository: repo, name: "Cool Polls", supports_polls: true)
      not_polls_category = create(:discussion_category, repository: repo, name: "SUPER Cool Polls", supports_polls: true)

      discussion = create(
        :discussion,
        body: "Hello this is the discussion body",
        category: polls_category,
        repository: repo,
      )

      discussion.update(category: not_polls_category)

      assert_predicate discussion, :valid?
    end
  end

  test "cannot change a discussion in a non-poll supporting category to one that supports polls" do
    repo = create(:repository, has_discussions: true)

    repo.discussion_categories.destroy_all

    polls_category = create(:discussion_category, repository: repo, name: "Cool Polls", supports_polls: true)
    not_polls_category = create(:discussion_category, repository: repo, name: "No Cool Polls", supports_polls: false)

    discussion = create(
      :discussion,
      body: "Hello this is the discussion body",
      category: not_polls_category,
      repository: repo,
    )

    discussion.update(category: polls_category)

    refute_predicate discussion, :valid?
  end

  context "scopes" do
    test "commented_on_by filters to just discussions the user has commented on" do
      commenter = create(:verified_user)
      @private_repo.add_member(commenter)
      create(:discussion_comment, user: commenter, discussion: @private_discussion)
      create(:discussion_comment, user: commenter, discussion: @org_discussion)

      result = Discussion.commented_on_by(commenter)

      assert_includes result, @private_discussion
      assert_includes result, @org_discussion
      refute_includes result, @public_discussion
    end

    test "for_organization filters to just discussions in repositories in the given org" do
      org2 = create(:organization)
      org2_repo = create(:repository, owner: org2, has_discussions: true)
      org2_discussion = create(:discussion, repository: org2_repo)

      result = Discussion.for_organization(@org).
        where(id: [org2_discussion, @org_discussion, @public_discussion, @private_discussion])

      assert_includes result, @org_discussion
      refute_includes result, org2_discussion
      refute_includes result, @public_discussion
      refute_includes result, @private_discussion
    end

    test "for_organization returns an empty list when there is no organization" do
      repo = create(:repository, has_discussions: true)

      assert_empty repo.owner.discussions.for_organization(nil)
    end

    test "for_organization filters to only active repositories in the given org" do
      new_org = create(:organization)
      repo1 = create(:repository, owner: new_org, has_discussions: true)
      repo1_discussion = create(:discussion, repository: repo1)
      repo2 = create(:repository, owner: new_org, has_discussions: true)
      repo2_discussion = create(:discussion, repository: repo2)

      before_result = Discussion.for_organization(new_org)
      assert_includes before_result, repo1_discussion
      assert_includes before_result, repo2_discussion

      repo2.delete

      result = Discussion.for_organization(new_org)

      assert_includes result, repo1_discussion
      refute_includes result, repo2_discussion
    end

    test "for_organization can limit to specific repositories" do
      org = create(:organization)
      discussions = {}
      repos = create_list(:repository, 3, owner: org, has_discussions: true).tap do |repos|
        repos.each { |repo| discussions[repo.id] = create(:discussion, repository: repo) }
      end

      only_repo_ids = repos.first(2).map(&:id)
      expected_discussions = only_repo_ids.map { |id| discussions[id] }
      actual_discussions = Discussion.for_organization(org, only_repo_ids: only_repo_ids)

      assert_same_elements expected_discussions, actual_discussions
    end

    test "converted_from_issue_numbered returns discussion converted from an issue with given number" do
      create(:discussion, issue_id: 1, number: 123)

      discussion = Discussion.converted_from_issue_numbered(123).first
      discussion = T.must(discussion)

      refute_nil discussion
      assert_equal 123, discussion.number
      assert_equal 1, discussion.issue_id
    end

    test "for_repository filters by repository" do
      repo1 = create(:repository, has_discussions: true)
      repo2 = create(:repository, has_discussions: true)
      discussion1 = create(:discussion, repository: repo1)
      discussion2 = create(:discussion, repository: repo2)

      discussions = Discussion.for_repository(repo1)

      assert_includes discussions, discussion1
      refute_includes discussions, discussion2
    end

    test "authored_by filters by user" do
      user1 = create(:verified_user)
      user2 = create(:verified_user)
      discussion1 = create(:discussion, user: user1)
      discussion2 = create(:discussion, user: user2)

      discussions = Discussion.authored_by(user1)

      assert_includes discussions, discussion1
      refute_includes discussions, discussion2
    end

    test "answered filters to only answerable discussions with a chosen answer" do
      repo = create(:repository)
      answerable_category = create(
        :discussion_category,
        supports_mark_as_answer: true,
        repository: repo,
      )
      unanswerable_category = create(
        :discussion_category,
        supports_mark_as_answer: false,
        repository: repo,
      )
      answered_discussion = create(
        :discussion_with_answer,
        category: answerable_category,
        chosen_comment_id: 1,
        repository: repo,
        title: "discussion that has an answer",
      )
      previously_answered_discussion = create(
        :discussion,
        category: unanswerable_category,
        chosen_comment_id: 1,
        repository: repo,
        title: "discussion that used to be answerable and had an answer",
      )
      unanswerable_discussion = create(
        :discussion,
        category: unanswerable_category,
        repository: repo,
        title: "discussion that never had an answer and is unanswerable",
      )

      discussions = Discussion.answered

      assert_includes discussions, answered_discussion
      refute_includes discussions, previously_answered_discussion
      refute_includes discussions, unanswerable_discussion
    end

    test "unanswered filters to only discussions without a chosen answer" do
      repo = create(:repository)
      answerable_category = create(
        :discussion_category,
        supports_mark_as_answer: true,
        repository: repo,
      )
      unanswerable_category = create(
        :discussion_category,
        supports_mark_as_answer: false,
        repository: repo,
      )
      answered_discussion = create(
        :discussion_with_answer,
        category: answerable_category,
        chosen_comment_id: 1,
        repository: repo,
        title: "discussion that has an answer",
      )
      unanswered_discussion = create(
        :discussion,
        category: answerable_category,
        repository: repo,
        title: "discussion that does not have an answer and is answerable",
      )
      unanswerable_discussion = create(
        :discussion,
        category: unanswerable_category,
        repository: repo,
        title: "discussion that never had an answer and is unanswerable",
      )

      discussions = Discussion.unanswered

      assert_includes discussions, unanswered_discussion
      refute_includes discussions, answered_discussion
      refute_includes discussions, unanswerable_discussion
    end

    test "newest_first sorts the most recently created discussions first" do
      discussion1 = Timecop.freeze(1.year.ago) { create(:discussion) }
      discussion2 = create(:discussion)

      discussions = Discussion.where(id: [discussion1.id, discussion2.id]).newest_first

      assert_equal [discussion2, discussion1], discussions
    end

    test "oldest_first sorts the most recently created discussions first" do
      discussion1 = Timecop.freeze(1.year.ago) { create(:discussion) }
      discussion2 = create(:discussion)

      discussions = Discussion.where(id: [discussion1.id, discussion2.id]).oldest_first

      assert_equal [discussion1, discussion2], discussions
    end

    test "recently_bumped_first sorts the most recently bumped discussions first" do
      discussion1, discussion2 = Timecop.freeze(1.year.ago) do
        [create(:discussion), create(:discussion)]
      end
      Timecop.freeze(1.month.ago) do
        discussion1.touch(:bumped_at)
      end
      Timecop.freeze(1.day.ago) do
        discussion2.touch(:bumped_at)
      end

      discussions = Discussion.where(id: [discussion1.id, discussion2.id]).recently_bumped_first

      assert_equal [discussion2, discussion1], discussions
    end

    test "least_recently_updated_first sorts the least recently updated discussions first" do
      discussion1, discussion2 = Timecop.freeze(1.year.ago) do
        [create(:discussion), create(:discussion)]
      end
      Timecop.freeze(1.month.ago) do
        discussion1.touch
      end
      Timecop.freeze(1.day.ago) do
        discussion2.touch
      end

      discussions = Discussion.where(id: [discussion1.id, discussion2.id]).least_recently_updated_first

      assert_equal [discussion1, discussion2], discussions
    end

    test "upvotes only returns upvotes" do
      user = create(:verified_user)
      @repo.repository.add_member(user, action: :write)
      upvote = create(:discussion_vote, upvote: true, discussion: @public_discussion)

      assert_includes @public_discussion.upvotes, upvote
    end

    test "deletes votes when discussion is deleted" do
      # after_create hook will auto-create an upvote
      discussion = create(:discussion, user: @owner)
      vote = discussion.votes.first

      assert_difference("DiscussionVote.count", -1) do
        perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
          discussion.destroy
        end
      end

      refute DiscussionVote.exists?(vote.id)
    end

    context "category pins" do
      test "deletes category pin when discussion is deleted" do
        discussion = create(:discussion, user: @owner)
        category_pin = create(:discussion_category_pin, discussion: discussion, pinned_by: @owner)

        assert_difference "DiscussionCategoryPin.count", -1 do
          discussion.destroy
        end
      end

      test "deletes category pin when discussion's category is changed" do
        category1 = create :discussion_category, repository: @repo
        category2 = create :discussion_category, repository: @repo

        discussion = create(:discussion, user: @owner, repository: @repo, category: category1)
        category_pin = create(:discussion_category_pin, discussion: discussion, pinned_by: @owner)

        assert_difference "DiscussionCategoryPin.count", -1 do
          discussion.category = category2
          discussion.save
        end
      end
    end

    test "filter_by_categories filters by category" do
      repo = create(:repository, has_discussions: true)
      category1 = create :discussion_category, repository: repo
      category2 = create :discussion_category, repository: repo

      discussion1 = create(:discussion, repository: repo, category: category1)
      discussion2 = create(:discussion, repository: repo, category: category2)

      discussions = Discussion.filter_by_categories(category1.id)

      assert_includes discussions, discussion1
      refute_includes discussions, discussion2
    end

    test "most_upvoted_first sorts discussions by upvotes" do
      three_upvotes = create(:discussion)
      3.times { create(:discussion_vote, discussion: three_upvotes, upvote: true) }

      five_upvotes = create(:discussion)
      5.times { create(:discussion_vote, discussion: five_upvotes, upvote: true) }

      no_upvotes = create(:discussion)

      most_upvotes_first = Discussion
        .where(id: [three_upvotes.id, five_upvotes.id, no_upvotes.id])
        .most_upvotes_first

      assert_equal [five_upvotes, three_upvotes, no_upvotes], most_upvotes_first
    end
  end

  context "update time" do
    test "changing title changes discussion updated_at" do
      old_value = @public_discussion.updated_at

      @public_discussion.title = "something new"
      @public_discussion.save!

      refute_equal old_value, @public_discussion.reload.updated_at
    end

    test "changing body changes discussion updated_at" do
      old_value = @public_discussion.updated_at

      @public_discussion.update_body("brand new body", @public_discussion.user)

      refute_equal old_value, @public_discussion.reload.updated_at
    end

    test "updating discussion body triggers websocket messages" do
      discussion_summary_channel = GitHub::WebSocket::Channels.discussion_summary(@public_discussion)
      discussion_channel = GitHub::WebSocket::Channels.discussion(@public_discussion)

      GitHub::WebSocket.expects(:notify_discussion_channel).
          with(@public_discussion, discussion_channel, has_entries(gid: @public_discussion.global_relay_id)).
          returns([]).once

      GitHub::WebSocket.expects(:notify_discussion_channel).
          with(@public_discussion, discussion_summary_channel, has_entries(gid: @public_discussion.global_relay_id)).
          returns([]).once

      @public_discussion.update_body(Faker::Lorem.sentence, @public_discussion.user)
    end

    test "adding a comment changes discussion updated_at" do
      old_value = @public_discussion.updated_at

      create(:discussion_comment, discussion: @public_discussion)

      refute_equal old_value, @public_discussion.reload.updated_at
    end

    test "marking an answer changes discussion updated_at" do
      comment = Timecop.freeze(1.day.ago) do
        create(:discussion_comment, discussion: @public_discussion)
      end
      old_value = @public_discussion.updated_at

      comment.mark_as_answer

      refute_equal old_value, @public_discussion.reload.updated_at
    end

    test "converting from an issue sets discussion updated_at to conversion time" do
      issue = Timecop.freeze(1.week.ago) do
        create(:issue, repository: @repo, user: @rando)
      end
      converter = IssueToDiscussionConverter.new(issue, actor: @repo.owner)
      old_value = issue.updated_at

      Timecop.freeze do
        assert converter.prepare_for_conversion
        assert converter.finish_conversion

        refute_equal old_value, converter.discussion.updated_at
        assert_equal Time.zone.now.to_i, converter.discussion.updated_at.to_i
      end
    end
  end

  context ".author_login_suggestions_for" do
    test "returns unique alphabetical logins of discussion authors in the specified repository" do
      repo = create(:repository, has_discussions: true)
      author_b = create(:user, :verified, login: "big-bad-burly-biscuit")
      author_a = create(:user, :verified, login: "ANicePerson")
      author_c = create(:user, :verified, login: "catFan123")

      create(:discussion, repository: repo, user: author_a)
      create_pair(:discussion, repository: repo, user: author_c)
      create(:discussion, repository: repo, user: author_b)

      result = Discussion.author_login_suggestions_for(repo)

      assert_equal %w[ANicePerson big-bad-burly-biscuit catFan123], result
    end

    test "omits spammy user logins" do
      spammer = create(:spammy_user, :verified)
      repo = create(:repository, has_discussions: true)
      create(:discussion, repository: repo, user: spammer)

      assert_empty Discussion.author_login_suggestions_for(repo)
    end if GitHub.spamminess_check_enabled?

    test "sorts current viewer first" do
      repo = create(:repository, has_discussions: true)
      author_b = create(:user, :verified, login: "big-bad-burly-biscuit")
      author_a = create(:user, :verified, login: "ANicePerson")
      author_c = create(:user, :verified, login: "catFan123")

      create_pair(:discussion, repository: repo, user: author_a)
      create(:discussion, repository: repo, user: author_c)
      create(:discussion, repository: repo, user: author_b)

      result = Discussion.author_login_suggestions_for(repo, viewer: author_c)

      assert_equal %w[catFan123 ANicePerson big-bad-burly-biscuit], result
    end

    test "limits results to the most prolific authors" do
      repo = create(:repository, has_discussions: true)
      author_b = create(:user, :verified, login: "big-bad-burly-biscuit")
      author_a = create(:user, :verified, login: "ANicePerson")
      author_c = create(:user, :verified, login: "catFan123")

      # Two authors with only a single discussion apiece, but the most recent author should be included:
      travel_to(1.day.ago) { create(:discussion, repository: repo, user: author_a) }
      create(:discussion, repository: repo, user: author_c)

      # One author with 2 discussions, should be included:
      create_pair(:discussion, repository: repo, user: author_b)

      result = Discussion.author_login_suggestions_for(repo, viewer: author_c, limit: 2)

      assert_equal %w[catFan123 big-bad-burly-biscuit], result
    end
  end

  context "#viewer_can_update?" do
    test "require write+ for non-authors of discussion" do
      @matrix.user_scenarios(
        :viewer_can_update?,
        none: false,
        read: false,
        triage: false,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "true for author of discussion" do
      assert @public_discussion.viewer_can_update?(@public_discussion.user)
    end

    test "false for author of discussion when repo is locked" do
      @repo.lock_for_migration
      refute @public_discussion.reload.viewer_can_update?(@public_discussion.user)
    end

    test "false for anonymous user" do
      refute @public_discussion.viewer_can_update?(nil)
    end
  end

  context ".label_name_suggestions_for" do
    test "returns unique alphabetical names of discussion labels in the specified repository" do
      cardamom_label = create(:label, repository: @repo, name: "cardamom")
      anise_label = create(:label, repository: @repo, name: "anise")
      bay_leaf_label = create(:label, repository: @repo, name: "Bay-leaf")

      create(:applied_discussion_label, discussion: @public_discussion, label: bay_leaf_label, repository: @repo)
      create(:applied_discussion_label, discussion: @public_discussion, label: cardamom_label, repository: @repo)
      create(:applied_discussion_label, label: cardamom_label, repository: @repo)
      create(:applied_discussion_label, discussion: @public_discussion, label: anise_label, repository: @repo)

      result = Discussion.label_name_suggestions_for(@repo)

      assert_equal %w[anise Bay-leaf cardamom], result
    end

    test "limits results to the most widely used labels" do
      cardamom_label = create(:label, repository: @repo, name: "cardamom")
      anise_label = create(:label, repository: @repo, name: "anise")
      bay_leaf_label = create(:label, repository: @repo, name: "Bay-leaf")

      # Two labels with only a single discussion apiece, but the most recent discussion's label should be included:
      old_discussion = travel_to(1.day.ago) { create(:discussion, repository: @repo) }
      new_discussion = create(:discussion, repository: @repo)
      create(:applied_discussion_label, discussion: new_discussion, label: cardamom_label, repository: @repo)
      create(:applied_discussion_label, discussion: old_discussion, label: anise_label, repository: @repo)

      # One label with 2 discussions, should be included:
      create(:applied_discussion_label, discussion: @public_discussion, label: bay_leaf_label, repository: @repo)
      create(:applied_discussion_label, label: bay_leaf_label, repository: @repo)

      result = Discussion.label_name_suggestions_for(@repo, limit: 2)

      assert_equal %w[Bay-leaf cardamom], result
    end
  end

  context "#modifiable_by? and #async_modifiable_by?" do
    test "requires write+" do
      @matrix.user_scenarios(
        :modifiable_by?,
        none: false,
        read: false,
        triage: false,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "true for user who started discussion" do
      assert @public_discussion.modifiable_by?(@public_discussion.user)
      assert @public_discussion.async_modifiable_by?(@public_discussion.user).sync
    end

    test "false when setting is disabled" do
      matrix_turn_off_discussions

      @matrix.user_scenarios(
        :modifiable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "false when repository is archived" do
      matrix_archive_repos

      @matrix.user_scenarios(
        :modifiable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )

      refute @public_discussion.modifiable_by?(@public_discussion.user)
      refute @public_discussion.async_modifiable_by?(@public_discussion.user).sync
    end

    test "false for anonymous user" do
      refute @public_discussion.modifiable_by?(nil)
      refute @public_discussion.async_modifiable_by?(nil).sync
    end

    context "when interaction limits are enabled" do
      test "false for author of the discussion if not a collaborator" do
        interaction = RepositoryInteractionAbility.new(@org_repo)
        interaction.set_ability(:collaborators_only, @admin)

        refute @org_discussion.modifiable_by?(@public_discussion.user)
        refute @org_discussion.async_modifiable_by?(@public_discussion.user).sync
      end

      test "true for author of the discussion if collaborator on the repo" do
        interaction = RepositoryInteractionAbility.new(@org_repo)
        interaction.set_ability(:collaborators_only, @admin)

        assert @org_discussion.modifiable_by?(@writer)
        assert @org_discussion.async_modifiable_by?(@writer).sync
      end
    end if GitHub.interaction_limits_enabled?

    if GitHub.email_verification_enabled?
      test "false for author without verified email address" do
        @public_discussion.user.emails.map(&:unverify!)
        refute @public_discussion.modifiable_by?(@public_discussion.user)
        refute @public_discussion.async_modifiable_by?(@public_discussion.user).sync
      end
    else
      test "true for author without verified email address" do
        @public_discussion.user.emails.map(&:unverify!)
        assert @public_discussion.modifiable_by?(@public_discussion.user)
        assert @public_discussion.async_modifiable_by?(@public_discussion.user).sync
      end
    end

    test "true for bot users of integrations with write+ permissions" do
      @matrix.bot_scenarios(
        :modifiable_by?,
        none: false,
        read: false,
        write: true,
      )
    end

    test "false for bot users of integrations with discussions off" do
      matrix_turn_off_discussions

      @matrix.bot_scenarios(
        :modifiable_by?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "false for bot users of integrations on repos locked for migration" do
      matrix_lock_repos_for_migration

      @matrix.bot_scenarios(
        :modifiable_by?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "false for bot users of integrations on repos that are archived" do
      matrix_archive_repos

      @matrix.bot_scenarios(
        :modifiable_by?,
        none: false,
        read: false,
        write: false,
      )
    end
  end

  context "#category_modifiable_by? and #async_category_modifiable_by?" do
    test "requires triage+" do
      @matrix.user_scenarios(
        :category_modifiable_by?,
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "true for user who started discussion" do
      assert @public_discussion.category_modifiable_by?(@public_discussion.user)
      assert @public_discussion.async_category_modifiable_by?(@public_discussion.user).sync
    end

    test "false when setting is disabled" do
      matrix_turn_off_discussions

      @matrix.user_scenarios(
        :category_modifiable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "false when repository is archived" do
      matrix_archive_repos

      @matrix.user_scenarios(
        :category_modifiable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )

      refute @public_discussion.category_modifiable_by?(@public_discussion.user)
      refute @public_discussion.async_category_modifiable_by?(@public_discussion.user).sync
    end

    test "false for anonymous user" do
      refute @public_discussion.category_modifiable_by?(nil)
      refute @public_discussion.async_category_modifiable_by?(nil).sync
    end

    if GitHub.email_verification_enabled?
      test "false for author without verified email address" do
        @public_discussion.user.emails.map(&:unverify!)
        refute @public_discussion.category_modifiable_by?(@public_discussion.user)
        refute @public_discussion.async_category_modifiable_by?(@public_discussion.user).sync
      end
    else
      test "true for author without verified email address" do
        @public_discussion.user.emails.map(&:unverify!)
        assert @public_discussion.category_modifiable_by?(@public_discussion.user)
        assert @public_discussion.async_category_modifiable_by?(@public_discussion.user).sync
      end
    end

    test "true for bot users of integrations with write+ permissions" do
      @matrix.bot_scenarios(
        :category_modifiable_by?,
        none: false,
        read: false,
        write: true,
      )
    end

    test "false for bot users of integrations with discussions off" do
      matrix_turn_off_discussions

      @matrix.bot_scenarios(
        :category_modifiable_by?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "false for bot users of integrations on repos locked for migration" do
      matrix_lock_repos_for_migration

      @matrix.bot_scenarios(
        :category_modifiable_by?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "false for bot users of integrations on repos that are archived" do
      matrix_archive_repos

      @matrix.bot_scenarios(
        :category_modifiable_by?,
        none: false,
        read: false,
        write: false,
      )
    end
  end

  context "#participant_ids_by_discussion_id" do
    test "returns a hash of participant IDs by discussion ID" do
      comment = create(:discussion_comment, discussion: @public_discussion)
      discussion2 = create(:discussion, repository: @repo)

      results = Discussion.participant_ids_by_discussion_id([@public_discussion, discussion2],
        viewer: nil)

      assert_same_elements [@public_discussion.id, discussion2.id], results.keys
      assert_same_elements [@public_discussion.user_id, comment.user_id],
        results[@public_discussion.id]
      assert_equal [discussion2.user_id], results[discussion2.id]
    end

    test "excludes spammer ID when viewer can't see them" do
      spammy_comment = create(:discussion_comment, user: @spammer,
        discussion: @public_discussion)

      results = Discussion.participant_ids_by_discussion_id([@public_discussion],
        viewer: nil)
      assert_equal [@public_discussion.id], results.keys
      refute_includes results[@public_discussion.id], @spammer.id

      results = Discussion.participant_ids_by_discussion_id([@public_discussion],
        viewer: @spammer)
      assert_equal [@public_discussion.id], results.keys
      assert_includes results[@public_discussion.id], @spammer.id
    end if GitHub.spamminess_check_enabled?
  end

  context "#participants_by_discussion_id" do
    test "returns a hash of users by discussion ID" do
      comment = create(:discussion_comment, discussion: @public_discussion)
      discussion2 = create(:discussion, repository: @repo)
      discussions = [@public_discussion, discussion2]

      results = Discussion.participants_by_discussion_id(discussions,
        viewer: nil)

      assert_same_elements [@public_discussion.id, discussion2.id], results.keys
      assert_same_elements [@public_discussion.user, comment.user],
        results[@public_discussion.id]
      assert_equal [discussion2.user], results[discussion2.id]
    end

    test "returns participants for private discussions" do
      comment = create(:discussion_comment, discussion: @private_discussion)

      results = Discussion.participants_by_discussion_id(
        [@private_discussion],
        viewer: nil
      )
      assert_same_elements [@private_discussion.user, comment.user], results[@private_discussion.id]
    end

    test "excludes spammer when viewer can't see them" do
      spammy_comment = create(:discussion_comment, user: @spammer,
        discussion: @public_discussion)

      results = Discussion.participants_by_discussion_id([@public_discussion],
        viewer: nil)
      assert_equal [@public_discussion.id], results.keys
      refute_includes results[@public_discussion.id], @spammer

      results = Discussion.participants_by_discussion_id([@public_discussion],
        viewer: @spammer)
      assert_equal [@public_discussion.id], results.keys
      assert_includes results[@public_discussion.id], @spammer
    end if GitHub.spamminess_check_enabled?
  end

  context "#participants" do
    test "returns different cached value based on params" do
      discussion = create(:discussion)
      create(:discussion_comment, discussion: discussion)

      assert_equal 1, discussion.participants(limit: 1).count
      assert_equal 2, discussion.participants(limit: 5).count
    end
  end

  context "commented_on_and_visible_to scope" do
    test "includes public discussion commented on by user" do
      comment = create(:discussion_comment, discussion: @public_discussion)
      result = Discussion.commented_on_and_visible_to(comment.user)
      assert_includes result, @public_discussion
    end

    test "includes private discussion commented on by user" do
      commenter = create(:verified_user)
      @private_repo.add_member(commenter)
      comment = create(:discussion_comment, discussion: @private_discussion, user: commenter)

      result = Discussion.commented_on_and_visible_to(commenter)

      assert_includes result, @private_discussion
    end

    test "does not include public discussion commented on by different user" do
      assert_predicate @org_discussion.repository, :public?,
        "should be a public discussion for this test"
      comment1 = create(:discussion_comment, discussion: @org_discussion)
      comment2 = create(:discussion_comment, discussion: @public_discussion)
      refute_equal comment1.user, comment2.user,
        "need two separate commenters for this test"

      result = Discussion.commented_on_and_visible_to(comment2.user)

      refute_includes result, @org_discussion
    end

    test "does not include private discussion commented on by different user" do
      refute_predicate @private_discussion.repository, :public?,
        "should be a private discussion for this test"
      comment1 = create(:discussion_comment, discussion: @public_discussion)
      comment2 = create(:discussion_comment, discussion: @private_discussion)
      refute_equal comment1.user, comment2.user,
        "need two separate commenters for this test"

      result = Discussion.commented_on_and_visible_to(@public_discussion.user)

      refute_includes result, @private_discussion
    end

    test "does not include private discussion no longer visible to the author" do
      commenter = create(:verified_user)
      create(:discussion_comment, discussion: @private_discussion, user: commenter)
      refute @private_repo.readable_by?(commenter),
        "need user to not have access to the repo containing the discussion"

      result = Discussion.commented_on_and_visible_to(commenter)

      refute_includes result, @private_discussion
    end

    test "does not include discussion that is in a deleted public repository" do
      comment = create(:discussion_comment, discussion: @public_discussion)
      before_result = Discussion.commented_on_and_visible_to(comment.user)
      assert_includes before_result, @public_discussion

      @public_discussion.repository.destroy
      result = Discussion.commented_on_and_visible_to(comment.user)
      refute_includes result, @public_discussion
    end

    test "does not include discussion that is in a deleted private repository" do
      commenter = create(:verified_user)
      @private_repo.add_member(commenter)
      comment = create(:discussion_comment, discussion: @private_discussion, user: commenter)
      before_result = Discussion.commented_on_and_visible_to(commenter)
      assert_includes before_result, @private_discussion

      @private_repo.delete
      result = Discussion.commented_on_and_visible_to(commenter)
      refute_includes result, @private_discussion
    end
  end

  context "authored_by_and_visible_to scope" do
    test "includes public discussion authored by user" do
      result = Discussion.authored_by_and_visible_to(@public_discussion.user)
      assert_includes result, @public_discussion
    end

    test "includes private discussion authored by user" do
      result = Discussion.authored_by_and_visible_to(@private_discussion.user)
      assert_includes result, @private_discussion
    end

    test "does not include public discussion authored by different user" do
      refute_equal @public_discussion.user, @org_discussion.user,
        "should be different authors for this test"
      assert_predicate @org_discussion.repository, :public?,
        "should be a public discussion for this test"

      result = Discussion.authored_by_and_visible_to(@public_discussion.user)

      refute_includes result, @org_discussion
    end

    test "does not include private discussion authored by different user" do
      refute_equal @public_discussion.user, @private_discussion.user,
        "should be different authors for this test"
      refute_predicate @private_discussion.repository, :public?,
        "should be a private discussion for this test"

      result = Discussion.authored_by_and_visible_to(@public_discussion.user)

      refute_includes result, @private_discussion
    end

    test "does not include private discussion no longer visible to the author" do
      @private_discussion.repository.remove_member(@private_discussion.user)

      result = Discussion.authored_by_and_visible_to(@private_discussion.user)

      refute_includes result, @private_discussion
    end

    test "does not include a discussion in a deleted public repository" do
      before_result = Discussion.authored_by_and_visible_to(@public_discussion.user)
      assert_includes before_result, @public_discussion

      @public_discussion.repository.destroy
      result = Discussion.authored_by_and_visible_to(@public_discussion.user)
      refute_includes result, @public_discussion
    end

    test "does not include a discussion in a deleted private repository" do
      before_result = Discussion.authored_by_and_visible_to(@private_discussion.user)
      assert_includes before_result, @private_discussion

      @private_discussion.repository.destroy
      result = Discussion.authored_by_and_visible_to(@private_discussion.user)
      refute_includes result, @private_discussion
    end
  end

  context "#async_active_chosen_comment" do
    test "returns nil when not answered" do
      assert_nil @public_discussion.async_active_chosen_comment.sync
    end

    test "returns nil when the discussion's category does not support marking as answer" do
      create(:discussion_comment, :answer, discussion: @public_discussion)
      @public_discussion.category.update!(supports_mark_as_answer: false)
      assert_nil @public_discussion.async_active_chosen_comment.sync
    end

    test "returns the answer when the category does support marking as answer" do
      answer = create(:discussion_comment, :answer, discussion: @public_discussion)
      assert_equal @public_discussion.async_active_chosen_comment.sync, answer
    end
  end

  context "#chosen_comment_selected_by_user and #async_chosen_comment_selected_by_user" do
    test "returns nil when not answered" do
      assert_nil @public_discussion.chosen_comment_selected_by_user
      assert_nil @public_discussion.async_chosen_comment_selected_by_user.sync
    end

    test "returns the user who marked the answer when answered" do
      answer = create(:discussion_comment, discussion: @public_discussion)
      answer.actor = @owner
      assert answer.mark_as_answer, "need marking the answer to succeed for this test"

      assert_equal @owner, @public_discussion.chosen_comment_selected_by_user
      assert_equal @owner, @public_discussion.async_chosen_comment_selected_by_user.sync
    end

    test "returns nil when user who marked the answer is not known" do
      answer = create(:discussion_comment, discussion: @public_discussion)
      assert answer.mark_as_answer, "need marking the answer to succeed for this test"

      assert_nil @public_discussion.chosen_comment_selected_by_user
      assert_nil @public_discussion.async_chosen_comment_selected_by_user.sync
    end

    test "returns nil when the discussion's category does not support marking as answer" do
      answer = create(:discussion_comment, discussion: @public_discussion)
      answer.actor = @owner
      assert answer.mark_as_answer, "need marking the answer to succeed for this test"
      @public_discussion.category.update!(supports_mark_as_answer: false)

      assert_nil @public_discussion.chosen_comment_selected_by_user
      assert_nil @public_discussion.async_chosen_comment_selected_by_user.sync
    end
  end

  context "#async_chosen_comment_selected_at" do
    test "returns nil when not answered" do
      assert_nil @public_discussion.async_chosen_comment_selected_at.sync
    end

    test "returns the timestamp when a comment was chosen as the answer" do
      ts = 6.hours.ago.change(sec: 0) # Zero seconds to account for loss of precision being roundtripped in the DB
      Timecop.freeze(ts) do
        create(:discussion_comment, :answer, discussion: @public_discussion)
      end

      assert_equal ts, @public_discussion.async_chosen_comment_selected_at.sync
    end

    test "returns nil when the discussion's category does not support marking as answer" do
      create(:discussion_comment, :answer, discussion: @public_discussion)
      @public_discussion.category.update!(supports_mark_as_answer: false)

      assert_nil @public_discussion.async_chosen_comment_selected_at.sync
    end
  end

  context "#supports_mark_as_answer? and #async_supports_mark_as_answer?" do
    test "returns true for discussions in a category that supports answer marking" do
      marking = create :discussion_category, repository: @repo, supports_mark_as_answer: true
      discussion = create :discussion, repository: @repo, category: marking

      assert_predicate discussion, :supports_mark_as_answer?
      assert discussion.async_supports_mark_as_answer?.sync
    end

    test "returns false for discussions in a category that does not support answer marking" do
      nonmarking = create :discussion_category, repository: @repo, supports_mark_as_answer: false
      discussion = create :discussion, repository: @repo, category: nonmarking

      refute_predicate discussion, :supports_mark_as_answer?
      refute discussion.async_supports_mark_as_answer?.sync
    end
  end

  context "#supports_announcements? and #async_supports_announcements?" do
    test "returns true for discussions in a category that supports announcements" do
      announcements = @repo.discussion_categories.find_by(name: "Announcements")
      announcements ||= create :discussion_category, repository: @repo, name: "Announcements", supports_announcements: true
      discussion = create :discussion, repository: @repo, category: announcements, user: @owner

      assert_predicate discussion, :supports_announcements?
      assert discussion.async_supports_announcements?.sync
    end

    test "returns false for discussions in a category that does not support announcements" do
      general = @repo.discussion_categories.find_by(name: "General")
      discussion = create :discussion, repository: @repo, category: general

      refute_predicate discussion, :supports_announcements?
      refute discussion.async_supports_announcements?.sync
    end
  end

  context "#supports_polls? and #async_supports_polls?" do
    test "returns true for discussions in a category that supports announcements" do
      polls = @repo.discussion_categories.find_by(name: "A Poll Category")
      polls ||= create :discussion_category, repository: @repo, name: "A Poll Category", supports_polls: true
      discussion = create :discussion, repository: @repo, category: polls, user: @owner

      assert_predicate discussion, :supports_polls?
      assert discussion.async_supports_polls?.sync
    end

    test "returns false for discussions in a category that does not support announcements" do
      general = @repo.discussion_categories.find_by(name: "General")
      discussion = create :discussion, repository: @repo, category: general

      refute_predicate discussion, :supports_polls?
      refute discussion.async_supports_polls?.sync
    end
  end

  context "#async_can_toggle_answer?" do
    test "requires triage+" do
      @matrix.user_scenarios(
        :async_can_toggle_answer?,
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "true for discussion author" do
      assert @public_discussion.async_can_toggle_answer?(@public_discussion.user).sync
      assert @private_discussion.async_can_toggle_answer?(@private_discussion.user).sync
      assert @org_discussion.async_can_toggle_answer?(@org_discussion.user).sync
    end

    if GitHub.email_verification_enabled?
      test "false when user has no verified email" do
        @public_discussion.user.emails.map(&:unverify!)
        refute @public_discussion.async_can_toggle_answer?(@public_discussion.user).sync
      end
    else
      test "true even for user with no verified email" do
        @public_discussion.user.emails.map(&:unverify!)
        assert @public_discussion.async_can_toggle_answer?(@public_discussion.user).sync
      end
    end

    test "false when user is blocked by repo owner" do
      @owner.block(@public_discussion.user)
      refute @public_discussion.async_can_toggle_answer?(@public_discussion.user).sync
    end

    test "false when repo has discussions off" do
      matrix_turn_off_discussions

      @matrix.user_scenarios(
        :async_can_toggle_answer?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "false when repo is locked for migration" do
      matrix_lock_repos_for_migration

      @matrix.user_scenarios(
        :async_can_toggle_answer?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "false when repo is archived" do
      matrix_archive_repos

      @matrix.user_scenarios(
        :async_can_toggle_answer?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "true for bot users of integrations with write permissions" do
      @matrix.bot_scenarios(
        :async_can_toggle_answer?,
        none: false,
        read: false,
        write: true,
      )
    end

    test "false for bot users of integrations with discussions off" do
      matrix_turn_off_discussions

      @matrix.bot_scenarios(
        :async_can_toggle_answer?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "false for bot users of integrations on repos locked for migration" do
      matrix_lock_repos_for_migration

      @matrix.bot_scenarios(
        :async_can_toggle_answer?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "false for bot users of integrations on archived repos" do
      matrix_archive_repos

      @matrix.bot_scenarios(
        :async_can_toggle_answer?,
        none: false,
        read: false,
        write: false,
      )
    end
  end

  context "#answered_by_id" do
    test "returns nil when there is no chosen comment" do
      assert_nil @public_discussion.answered_by_id
    end

    test "returns the ID of the user who authored the chosen comment" do
      answered_by = create(:user, :verified)
      answer = create(:discussion_comment, discussion: @public_discussion, user: answered_by)
      @public_discussion.chosen_comment = answer

      assert_predicate @public_discussion.category, :supports_mark_as_answer?
      assert_equal answered_by.id, @public_discussion.answered_by_id
    end

    test "returns nil when the discussion category disallows marking answers" do
      answered_by = create(:user, :verified)
      answer = create(:discussion_comment, discussion: @private_discussion, user: answered_by)
      @private_discussion.chosen_comment = answer

      refute_predicate @private_discussion.category, :supports_mark_as_answer?
      assert_nil @private_discussion.answered_by_id
    end
  end

  context "#answered? and #async_answered?" do
    test "returns false if not answered" do
      refute_predicate @public_discussion, :answered?
      refute @public_discussion.async_answered?.sync
    end

    test "returns true if answered" do
      @public_discussion.chosen_comment = create(:discussion_comment)
      assert_predicate @public_discussion, :answered?
      assert @public_discussion.async_answered?.sync
    end

    test "returns false if answered but answer has been deleted" do
      discussion = create(:discussion_with_answer)
      assert_predicate discussion, :answered?

      discussion.chosen_comment.delete

      refute_nil discussion.chosen_comment_id
      refute_predicate discussion.reload, :answered?
      refute discussion.async_answered?.sync
    end
  end

  context "#unmark_answer_if_set" do
    test "returns true when discussion does not have an answer" do
      assert @public_discussion.unmark_answer_if_set(@public_discussion.user)
    end

    test "returns true when answer is unmarked" do
      discussion = create(:discussion_with_answer)

      assert_difference("DiscussionEvent.count") do
        assert discussion.unmark_answer_if_set(discussion.user)
      end
      assert_nil discussion.reload.chosen_comment
    end
  end

  context "#unanswered?" do
    test "returns true if not answered" do
      assert @public_discussion.unanswered?
    end

    test "returns false if answered" do
      @public_discussion.chosen_comment = create(:discussion_comment)
      refute @public_discussion.unanswered?
    end
  end

  context "last_transfer relation" do
    test "nil when discussion has not been transferred from its original repository" do
      assert_nil @public_discussion.last_transfer
    end

    test "returns the latest discussion transfer for the discussion" do
      transfer = create(:discussion_transfer, new_discussion: @public_discussion,
        actor: @owner)
      assert_equal transfer, @public_discussion.last_transfer
    end

    test "does not delete transfer record when discussion is deleted" do
      transfer = create(:discussion_transfer, new_discussion: @public_discussion,
        actor: @owner)

      assert_no_difference("DiscussionTransfer.count") do
        @public_discussion.destroy
      end

      assert DiscussionTransfer.exists?(transfer.id),
        "transfer record should not be deleted so that " \
        "DiscussionTransfer#find_from can still follow the trail of transfers"
    end
  end

  context "events relation" do
    test "deletes events when discussion is deleted" do
      event1 = create(:discussion_event, discussion: @public_discussion)
      event2 = create(:discussion_event, :comment, discussion: @public_discussion)

      assert_difference("DiscussionEvent.count", -2) do
        perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
          @public_discussion.destroy
        end
      end

      refute DiscussionEvent.exists?(event1.id)
      refute DiscussionEvent.exists?(event2.id)
    end
  end

  context "spotlight relation" do
    test "destroys spotlight when discussion is destroyed" do
      spotlight = create(:discussion_spotlight, discussion: @public_discussion)

      assert_difference(-> { DiscussionSpotlight.count }, -1) do
        @public_discussion.destroy
      end

      refute DiscussionSpotlight.exists?(spotlight.id)
    end
  end

  context "#upvote" do
    test "creates new vote when user hasn't voted already" do
      user = create(:verified_user)

      assert_difference("@public_discussion.votes.for_user(user).count") do
        assert @public_discussion.upvote(user)
      end
    end

    test "does not create new vote when user has voted already" do
      user = create(:verified_user)
      create(:discussion_vote, discussion: @public_discussion, user: user)

      assert_no_difference("DiscussionVote.count") do
        assert @public_discussion.upvote(user)
      end
    end

    test "allows mannequin to vote" do
      mannequin = Mannequin.new(source_login: "updoot", owner: @org_repo.owner).tap(&:save)

      assert_difference("@org_discussion.votes.for_user(mannequin).count") do
        assert @org_discussion.upvote(mannequin)
      end
    end
  end

  context "#vote_by" do
    test "returns existing vote for given user" do
      user = create(:verified_user)
      vote = create(:discussion_vote, discussion: @public_discussion, user: user)

      assert_equal vote, @public_discussion.vote_by(user, upvote: true)
    end

    test "returns nil when given user has not voted on the discussion" do
      user = create(:verified_user)

      assert_nil @public_discussion.vote_by(user, upvote: true)
    end
  end

  context "comments relation" do
    test "destroys comment when discussion is destroyed" do
      comment = create(:discussion_comment, discussion: @public_discussion)

      assert_difference("DiscussionComment.count", -1) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          @public_discussion.destroy
        end
      end
    end

    test "destroys parent comments when discussion is destroyed" do
      parent_comment = create(:discussion_comment, discussion: @public_discussion)
      create(:discussion_comment, discussion: @public_discussion, parent_comment: parent_comment)

      assert_difference("DiscussionComment.count", -2) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          @public_discussion.destroy
        end
      end
    end

    test "ordered by creation date ascending" do
      comment1 = Timecop.freeze(1.day.ago) do
        create(:discussion_comment, discussion: @public_discussion)
      end
      comment2 = Timecop.freeze(1.month.ago) do
        create(:discussion_comment, discussion: @public_discussion)
      end
      comment3 = Timecop.freeze(1.week.ago) do
        create(:discussion_comment, discussion: @public_discussion)
      end
      assert_equal [comment2, comment3, comment1], @public_discussion.comments
    end
  end

  context "#deletable_by? and #async_deletable_by?" do
    test "requires triage+" do
      @matrix.user_scenarios(
        :deletable_by?,
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false when discussions is turned off" do
      matrix_turn_off_discussions

      @matrix.user_scenarios(
        :deletable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "false when repository is archived" do
      matrix_archive_repos

      @matrix.user_scenarios(
        :deletable_by?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    if GitHub.email_verification_enabled?
      test "false for user who doesn't have verified email address" do
        @admin.emails.map(&:unverify!)
        refute @org_discussion.deletable_by?(@admin)
        refute @org_discussion.async_deletable_by?(@admin).sync
      end
    else
      test "true for user who doesn't have verified email address" do
        @admin.emails.map(&:unverify!)
        assert @org_discussion.deletable_by?(@admin)
        assert @org_discussion.async_deletable_by?(@admin).sync
      end
    end

    test "true for installations with write permissions" do
      @matrix.bot_scenarios(
        :deletable_by?,
        none: false,
        read: false,
        write: true,
      )
    end

    test "false for installations on repo with discussions off" do
      matrix_turn_off_discussions

      @matrix.bot_scenarios(
        :deletable_by?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "false for installations on repos that are locked for migration" do
      matrix_lock_repos_for_migration

      @matrix.bot_scenarios(
        :deletable_by?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "false for installations on archived repos" do
      matrix_archive_repos

      @matrix.bot_scenarios(
        :deletable_by?,
        none: false,
        read: false,
        write: false,
      )
    end
  end

  context "#add_labels" do
    test "adds new labels to the discussion" do
      @public_discussion.expects(:synchronize_search_index)

      @public_discussion.add_labels([@label0, @label1])
      assert_same_elements @public_discussion.labels, [@label0, @label1]
    end

    test "silently disregards already-applied labels" do
      @public_discussion.add_labels([@label1])

      @public_discussion.add_labels([@label0, @label1, @label2])
      assert_same_elements @public_discussion.labels, [@label0, @label1, @label2]
    end
  end

  context "#author_display_login" do
    test "returns the display login of the discussion's author" do
      author = create(:verified_user)
      author.update_attribute(:display_login, "HelloWorld")
      discussion = create(:discussion, repository: @repo, user: author)
      assert_equal "HelloWorld", discussion.author_display_login
    end

    test "returns the display login of the ghost user when author has been deleted" do
      discussion = create(:discussion, repository: @repo)
      discussion.user.delete
      assert_equal User.ghost.display_login, discussion.reload.author_display_login
    end
  end

  context "#repository_owner_login" do
    test "returns login of discussion's repository's owner" do
      owner = create(:user)
      repo = create(:repository, owner: owner, has_discussions: true)
      discussion = create(:discussion, repository: repo)

      assert_equal owner.login, discussion.repository_owner_login
    end

    test "does not load owner record" do
      # load discussion anew so none of its relations are loaded:
      discussion = Discussion.find(@public_discussion.id)

      assert_query_count_per_table({ users: 0 }) do
        assert_equal @repo.owner_display_login, discussion.repository_owner_login
      end
    end
  end

  context "#replace_labels" do
    test "adds and removes labels from the discussion" do
      @public_discussion.labels = [@label1]
      @public_discussion.expects(:synchronize_search_index)

      @public_discussion.replace_labels([@label0])
      assert_same_elements @public_discussion.labels, [@label0]
    end
  end

  context "#delete_labels" do
    test "removes applied labels from the discussion" do
      @public_discussion.labels = [@label0, @label1]
      @public_discussion.expects(:synchronize_search_index)

      @public_discussion.delete_labels([@label1])
      assert_same_elements @public_discussion.labels, [@label0]
    end

    test "silently disregards labels that are not already on the discussion" do
      @public_discussion.labels = [@label0, @label1]

      @public_discussion.delete_labels([@label2])

      assert_same_elements @public_discussion.labels, [@label0, @label1]
    end
  end

  context "#clear_labels" do
    test "removes all labels applied to the discussion" do
      @public_discussion.labels = [@label0, @label1]
      @public_discussion.expects(:synchronize_search_index)

      @public_discussion.clear_labels

      assert_empty @public_discussion.labels
    end
  end

  context "#og_image_url" do
    test "returns enhanced opengraph image url with correct cache key" do
      # calculate expected cache key from specific resource attributes
      cache_key = Digest::SHA256.hexdigest(
        [
          @public_discussion.updated_at,
          @repo.name,
          @repo.owner_id,
        ].join(":")
      )

      # enhanced opengraph url with expected cache slug
      image_url = "#{GitHub.og_image_generator_base_url}/#{cache_key}#{@public_discussion.permalink(include_host: false)}"

      assert_equal image_url, @public_discussion.og_image_url
    end
  end

  context "#detect_comment_language" do
    test "does not queue job on Enterprise" do
      assert_no_enqueued_jobs only: DetectCommentLanguageJob do
        @public_discussion.update_body(Faker::Lorem.sentence, @public_discussion.user)
      end
    end if GitHub.enterprise?

    test "does not queue job to detect language when other attribute is updated", skip_enterprise: true do
      assert_no_enqueued_jobs only: DetectCommentLanguageJob do
        @public_discussion.update(title: Faker::Lorem.sentence)
      end
    end

    test "queues job to detect language when the discussion is created", skip_enterprise: true do
      discussion = create(:discussion)

      DetectCommentLanguageJob.expects(:enqueue_once_per_interval)
        .with(
          has_entries(
            args: [discussion.id, "Discussion"],
            unique_id: "Discussion:#{discussion.id}",
            interval: 10.minutes,
            run_at_beginning_of_interval: true
          )
        )

      discussion.run_callbacks(:commit)
    end

    test "queues job to detect language when the discussion body is updated", skip_enterprise: true do
      assert_enqueued_jobs 1, only: DetectCommentLanguageJob do
        @public_discussion.update_body(Faker::Lorem.sentence, @public_discussion.user)
      end
    end

    test "uses enqueue_once_per_interval when the discussion body is updated", skip_enterprise: true do
      DetectCommentLanguageJob.expects(:enqueue_once_per_interval)
        .with(
          has_entries(
            args: [@public_discussion.id, "Discussion"],
            unique_id: regexp_matches(/^Discussion:#{@public_discussion.id}:\d+$/),
            interval: 10.minutes,
            run_at_beginning_of_interval: true
          )
        )

      @public_discussion.update_body(Faker::Lorem.sentence, @public_discussion.user)
    end

    test "enqueues job only once in 10 minutes interval if discussion body is updated multiple times", skip_enterprise: true do
      Timecop.freeze do
        assert_enqueued_jobs 1, only: DetectCommentLanguageJob do
          @public_discussion.update_body(Faker::Lorem.sentence, @public_discussion.user)
          @public_discussion.detect_comment_language
        end
        Timecop.travel(11.minutes.from_now) do
          assert_enqueued_jobs 1, only: DetectCommentLanguageJob do
            @public_discussion.update_body("Me gusta mucho GitHub", @public_discussion.user)
            @public_discussion.detect_comment_language
          end
        end
      end
    end

    test "enqueues multiple jobs within interval if body changed", skip_enterprise: true do
      assert_enqueued_jobs 2, only: DetectCommentLanguageJob do
        @public_discussion.detect_comment_language
        @public_discussion.update_body("Me gusta mucho GitHub", @public_discussion.user)
      end
    end
  end

  context "daily contributors count job" do
    test "scheduled on creation" do
      ts = Time.zone.parse("2021-09-01 12:00:00 UTC")
      assert_enqueued_with(job: CommunityInsights::DiscussionsDailyContributorsJob, args: [@repo.id, ts.to_date]) do
        create(:discussion, repository: @repo, created_at: ts)
      end
    end

    test "scheduled on deletion" do
      ts = Time.zone.parse("2021-09-01 12:00:00 UTC")
      discussion = perform_enqueued_jobs(only: CommunityInsights::DiscussionsDailyContributorsJob) do
        create(:discussion, repository: @repo, created_at: ts)
      end

      assert_enqueued_with(job: CommunityInsights::DiscussionsDailyContributorsJob, args: [@repo.id, ts.to_date]) do
        discussion.destroy
      end
    end
  end

  context "Hydro events", skip_enterprise: true do
    test "logs event on creation for a public discussion", skip_enterprise: true do
      travel_to Time.now do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
        GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

        # default fixture uses an open ended
        discussion = create(:discussion, :with_instrumentation, created_from_category_template: true)

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          discussion: Hydro::EntitySerializer.discussion(discussion),
          category: Hydro::EntitySerializer.discussion_category(discussion.category),
          spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
          specimen_body: Hydro::EntitySerializer.specimen_data(discussion.body),
          specimen_title: Hydro::EntitySerializer.specimen_data(discussion.title),
          repository: Hydro::EntitySerializer.repository(discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(discussion.repository.owner),
          author: Hydro::EntitySerializer.user(discussion.user),
          body: discussion.body,
          body_html: "#{discussion.body_html}",
          feature_flags: []
        }

        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCreate")
        assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionCreate")

        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: discussion.repository.id,
          repository: Hydro::EntitySerializer.repository(discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(discussion.repository.owner),
          actor_id: discussion.user.id,
          actor: Hydro::EntitySerializer.user(discussion.user),
          discussion_id: discussion.id,
          discussion: Hydro::EntitySerializer.discussion(discussion),
          lock_status: :LOCK_STATUS_UNLOCKED,
          pin_status: :PIN_STATUS_UNPINNED,
          announcement: false,
          org_or_repo_level: :ORG_OR_REPO_LEVEL_REPO,
          action: :ACTION_DISCUSSION_CREATED,
          action_timestamp: Time.now,
          discussion_format: :DISCUSSION_FORMAT_OPEN_ENDED,
          category_id: discussion.category.id,
          converted_from_issue: false,
          converted_issue_id: nil,
          specimen_title: Hydro::EntitySerializer.specimen_data(discussion.title),
          specimen_body: Hydro::EntitySerializer.specimen_data(discussion.body),
          created_from_category_template: true,
          state: :STATE_OPEN,
          state_reason: :STATE_REASON_UNKNOWN,
        }

        assert_hydro_published(message_v2, schema: "github.discussions.v2.Discussions")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.Discussions")
      end
    end

    test "logs event on creation for a private discussion", skip_enterprise: true do
      travel_to Time.now do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
        GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

        private_repo = create(:private_repository, has_discussions: true)
        discussion = create(:discussion, :with_instrumentation, repository: private_repo)

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          discussion: Hydro::EntitySerializer.discussion(discussion),
          category: Hydro::EntitySerializer.discussion_category(discussion.category),
          spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
          repository: Hydro::EntitySerializer.repository(private_repo),
          repository_owner: Hydro::EntitySerializer.user(private_repo.owner),
          author: Hydro::EntitySerializer.user(discussion.user),
          # Don't save content for private discussions
          specimen_body: nil,
          specimen_title: nil,
          body: discussion.body,
          body_html: "#{discussion.body_html}",
          feature_flags: []
        }

        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCreate")
        assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionCreate")

        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: private_repo.id,
          repository: Hydro::EntitySerializer.repository(private_repo),
          repository_owner: Hydro::EntitySerializer.user(private_repo.owner),
          actor_id: discussion.user.id,
          actor: Hydro::EntitySerializer.user(discussion.user),
          discussion_id: discussion.id,
          discussion: Hydro::EntitySerializer.discussion(discussion),
          lock_status: :LOCK_STATUS_UNLOCKED,
          pin_status: :PIN_STATUS_UNPINNED,
          announcement: false,
          org_or_repo_level: :ORG_OR_REPO_LEVEL_REPO,
          action: :ACTION_DISCUSSION_CREATED,
          action_timestamp: Time.now,
          discussion_format: :DISCUSSION_FORMAT_OPEN_ENDED,
          category_id: discussion.category.id,
          converted_from_issue: false,
          converted_issue_id: nil,
          specimen_title: nil,
          specimen_body: nil,
          created_from_category_template: false,
          state: :STATE_OPEN,
          state_reason: :STATE_REASON_UNKNOWN,
        }

        assert_hydro_published(message_v2, schema: "github.discussions.v2.Discussions")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.Discussions")
      end
    end

    test "logs event for converting discussion missing an author", skip_enterprise: true do
      travel_to Time.now do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
        GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

        issue = create(:issue)
        discussion = create(:discussion, :with_instrumentation, :converting, issue: issue, user: nil)

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          discussion: Hydro::EntitySerializer.discussion(discussion),
          category: Hydro::EntitySerializer.discussion_category(discussion.category),
          spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
          specimen_body: Hydro::EntitySerializer.specimen_data(discussion.body),
          specimen_title: Hydro::EntitySerializer.specimen_data(discussion.title),
          repository: Hydro::EntitySerializer.repository(discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(discussion.repository.owner),
          author: Hydro::EntitySerializer.user(User.ghost),
          body: discussion.body,
          body_html: "#{discussion.body_html}",
          feature_flags: []
        }

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published(message, schema: "github.discussions.v1.DiscussionCreate")
          assert_hydro_messages(count: 1, schema: "github.discussions.v1.DiscussionCreate")
        end

        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: discussion.repository.id,
          repository: Hydro::EntitySerializer.repository(discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(discussion.repository.owner),
          actor_id: User.ghost.id,
          actor: Hydro::EntitySerializer.user(User.ghost),
          discussion_id: discussion.id,
          discussion: Hydro::EntitySerializer.discussion(discussion),
          lock_status: :LOCK_STATUS_UNLOCKED,
          pin_status: :PIN_STATUS_UNPINNED,
          announcement: false,
          org_or_repo_level: :ORG_OR_REPO_LEVEL_REPO,
          action: :ACTION_DISCUSSION_CREATED,
          action_timestamp: Time.now,
          discussion_format: :DISCUSSION_FORMAT_OPEN_ENDED,
          category_id: discussion.category.id,
          # the discussion is in the process of being converted from an issue
          # so the issue_id is yet set and the converted_from_issue flag is false
          converted_from_issue: false,
          converted_issue_id: discussion.issue_id,
          specimen_title: Hydro::EntitySerializer.specimen_data(discussion.title),
          specimen_body: Hydro::EntitySerializer.specimen_data(discussion.body),
          created_from_category_template: false,
          state: :STATE_CONVERTING,
          state_reason: :STATE_REASON_UNKNOWN,
        }

        assert_hydro_published(message_v2, schema: "github.discussions.v2.Discussions")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.Discussions")
      end
    end

    test "Discussion create publishes github.platform_health.v1.UserGeneratedContent" do
      discussion = create(:discussion, :with_instrumentation)

      message = {
        request_context: nil,
        spamurai_form_signals: nil,
        action_type: :CREATE,
        content_type: :DISCUSSION,
        actor: Hydro::EntitySerializer.user(discussion.user),
        original_type_url: GitHub::Config::HydroConfig.build_type_url("github.discussions.v1.DiscussionCreate"),
        content_database_id: discussion.id,
        content_global_relay_id: discussion.global_relay_id,
        content_created_at: discussion.created_at,
        content_updated_at: discussion.updated_at,
        title: Hydro::EntitySerializer.specimen_data(discussion.title),
        content: Hydro::EntitySerializer.specimen_data(discussion.body),
        parent_content_author: nil,
        parent_content_database_id: nil,
        parent_content_global_relay_id: nil,
        parent_content_created_at: nil,
        parent_content_updated_at: nil,
        owner: Hydro::EntitySerializer.repository_owner(discussion.repository),
        repository: Hydro::EntitySerializer.repository(discussion.repository),
        content_visibility: :PUBLIC,
        content_url: Hydro::EntitySerializer.url_for_model(discussion),
      }

      with_hydro_publisher(GitHub.user_generated_content_hydro_publisher) do
        assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
      end
    end

    test "logs event on deletion of discussion" do
      travel_to Time.now do
        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        @public_discussion.actor = @staff
        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          discussion: Hydro::EntitySerializer.discussion(@public_discussion),
          category: Hydro::EntitySerializer.discussion_category(@public_discussion.category),
          actor: Hydro::EntitySerializer.user(@staff),
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
          author: Hydro::EntitySerializer.user(@public_discussion.user),
        }

        @public_discussion.destroy

        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionDelete")

        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @public_discussion.repository.id,
          repository: Hydro::EntitySerializer.repository(@public_discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(@public_discussion.repository.owner),
          actor_id: @public_discussion.actor.id,
          actor: Hydro::EntitySerializer.user(@public_discussion.actor),
          discussion_id: @public_discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@public_discussion),
          lock_status: :LOCK_STATUS_UNLOCKED,
          pin_status: :PIN_STATUS_UNPINNED,
          announcement: false,
          org_or_repo_level: :ORG_OR_REPO_LEVEL_REPO,
          action: :ACTION_DISCUSSION_DELETED,
          action_timestamp: Time.now,
          # the @public_discussion instance is a question and answers discussion
          discussion_format: :DISCUSSION_FORMAT_QUESTION_ANSWER,
          category_id: @public_discussion.category.id,
          converted_from_issue: false,
          converted_issue_id: nil,
          specimen_title: Hydro::EntitySerializer.specimen_data(@public_discussion.title),
          specimen_body: Hydro::EntitySerializer.specimen_data(@public_discussion.body),
          created_from_category_template: false,
          state: :STATE_OPEN,
          state_reason: :STATE_REASON_UNKNOWN,
        }

        assert_hydro_published(message_v2, schema: "github.discussions.v2.Discussions")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.Discussions")
      end
    end

    test "logs event on discussion update when title changes" do
      travel_to Time.now do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        @public_discussion.actor = @staff
        new_title = "Something borrowed, something blue"

        @public_discussion.update(title: new_title)

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          discussion: Hydro::EntitySerializer.discussion(@public_discussion.reload),
          previous_category: Hydro::EntitySerializer.discussion_category(@public_discussion.category),
          current_category: Hydro::EntitySerializer.discussion_category(@public_discussion.category),
          actor: Hydro::EntitySerializer.user(@staff),
          specimen_title: Hydro::EntitySerializer.specimen_data(new_title),
          specimen_body: Hydro::EntitySerializer.specimen_data(@public_discussion.body),
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
          author: Hydro::EntitySerializer.user(@public_discussion.user),
          feature_flags: []
        }
        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionUpdate")

        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @public_discussion.repository.id,
          repository: Hydro::EntitySerializer.repository(@public_discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(@public_discussion.repository.owner),
          actor_id: @public_discussion.actor.id,
          actor: Hydro::EntitySerializer.user(@public_discussion.actor),
          discussion_id: @public_discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@public_discussion),
          lock_status: :LOCK_STATUS_UNLOCKED,
          pin_status: :PIN_STATUS_UNPINNED,
          announcement: false,
          org_or_repo_level: :ORG_OR_REPO_LEVEL_REPO,
          action: :ACTION_DISCUSSION_UPDATED,
          action_timestamp: Time.now,
          # the @public_discussion instance is a question and answers discussion
          discussion_format: :DISCUSSION_FORMAT_QUESTION_ANSWER,
          category_id: @public_discussion.category.id,
          converted_from_issue: false,
          converted_issue_id: nil,
          specimen_title: Hydro::EntitySerializer.specimen_data(@public_discussion.title),
          specimen_body: Hydro::EntitySerializer.specimen_data(@public_discussion.body),
          created_from_category_template: false,
          state: :STATE_OPEN,
          state_reason: :STATE_REASON_UNKNOWN,
        }

        assert_hydro_published(message_v2, schema: "github.discussions.v2.Discussions")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.Discussions")
      end
    end

    test "logs event on discussion update when body changes" do
      travel_to Time.now do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        @public_discussion.actor = @staff
        new_body = "Something borrowed, something blue"

        @public_discussion.update_body(new_body, @staff)

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          discussion: Hydro::EntitySerializer.discussion(@public_discussion.reload),
          previous_category: Hydro::EntitySerializer.discussion_category(@public_discussion.category),
          current_category: Hydro::EntitySerializer.discussion_category(@public_discussion.category),
          actor: Hydro::EntitySerializer.user(@staff),
          specimen_title: Hydro::EntitySerializer.specimen_data(@public_discussion.title),
          specimen_body: Hydro::EntitySerializer.specimen_data(new_body),
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
          author: Hydro::EntitySerializer.user(@public_discussion.user),
          feature_flags: []
        }
        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionUpdate")


        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @public_discussion.repository.id,
          repository: Hydro::EntitySerializer.repository(@public_discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(@public_discussion.repository.owner),
          actor_id: @public_discussion.actor.id,
          actor: Hydro::EntitySerializer.user(@public_discussion.actor),
          discussion_id: @public_discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@public_discussion),
          lock_status: :LOCK_STATUS_UNLOCKED,
          pin_status: :PIN_STATUS_UNPINNED,
          announcement: false,
          org_or_repo_level: :ORG_OR_REPO_LEVEL_REPO,
          action: :ACTION_DISCUSSION_UPDATED,
          action_timestamp: Time.now,
          # the @public_discussion instance is a question and answers discussion
          discussion_format: :DISCUSSION_FORMAT_QUESTION_ANSWER,
          category_id: @public_discussion.category.id,
          converted_from_issue: false,
          converted_issue_id: nil,
          specimen_title: Hydro::EntitySerializer.specimen_data(@public_discussion.title),
          specimen_body: Hydro::EntitySerializer.specimen_data(@public_discussion.body),
          created_from_category_template: false,
          state: :STATE_OPEN,
          state_reason: :STATE_REASON_UNKNOWN,
        }

        assert_hydro_published(message_v2, schema: "github.discussions.v2.Discussions")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.Discussions")
      end
    end

    test "logs event on discussion update when category changes" do
      travel_to Time.now do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        @public_discussion.actor = @staff
        new_category = create(:discussion_category, repository: @repo)
        old_category = @public_discussion.category

        @public_discussion.update!(category: new_category)

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          discussion: Hydro::EntitySerializer.discussion(@public_discussion.reload),
          previous_category: Hydro::EntitySerializer.discussion_category(old_category),
          current_category: Hydro::EntitySerializer.discussion_category(new_category),
          actor: Hydro::EntitySerializer.user(@staff),
          specimen_title: Hydro::EntitySerializer.specimen_data(@public_discussion.title),
          specimen_body: Hydro::EntitySerializer.specimen_data(@public_discussion.body),
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
          author: Hydro::EntitySerializer.user(@public_discussion.user),
          feature_flags: []
        }
        assert_hydro_published(message, schema: "github.discussions.v1.DiscussionUpdate")


        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @public_discussion.repository.id,
          repository: Hydro::EntitySerializer.repository(@public_discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(@public_discussion.repository.owner),
          actor_id: @public_discussion.actor.id,
          actor: Hydro::EntitySerializer.user(@public_discussion.actor),
          discussion_id: @public_discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@public_discussion),
          lock_status: :LOCK_STATUS_UNLOCKED,
          pin_status: :PIN_STATUS_UNPINNED,
          announcement: false,
          org_or_repo_level: :ORG_OR_REPO_LEVEL_REPO,
          action: :ACTION_DISCUSSION_UPDATED,
          action_timestamp: Time.now,
          # the @public_discussion instance is a question and answers discussion
          discussion_format: :DISCUSSION_FORMAT_QUESTION_ANSWER,
          category_id: @public_discussion.category.id,
          converted_from_issue: false,
          converted_issue_id: nil,
          specimen_title: Hydro::EntitySerializer.specimen_data(@public_discussion.title),
          specimen_body: Hydro::EntitySerializer.specimen_data(@public_discussion.body),
          created_from_category_template: false,
          state: :STATE_OPEN,
          state_reason: :STATE_REASON_UNKNOWN,
        }

        assert_hydro_published(message_v2, schema: "github.discussions.v2.Discussions")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.Discussions")
      end
    end

    test "does not include specimen data for private repo on discussion update" do
      travel_to Time.now do
        SecretScanning::Features::Repo::ContentScanning.any_instance.stubs(:enabled?).returns(false)

        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
        GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
        @private_discussion.actor = @staff

        @private_discussion.update(title: "Something borrowed, something blue")

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          discussion: Hydro::EntitySerializer.discussion(@private_discussion.reload),
          previous_category: Hydro::EntitySerializer.discussion_category(@private_discussion.category),
          current_category: Hydro::EntitySerializer.discussion_category(@private_discussion.category),
          actor: Hydro::EntitySerializer.user(@staff),
          spamurai_form_signals: Hydro::EntitySerializer.spamurai_form_signals(spamurai_form_signals),
          specimen_title: nil,
          specimen_body: nil,
          repository: Hydro::EntitySerializer.repository(@private_repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
          author: Hydro::EntitySerializer.user(@private_discussion.user),
          feature_flags: []
        }

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published(message, schema: "github.discussions.v1.DiscussionUpdate")
        end


        message_v2 = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @private_discussion.repository.id,
          repository: Hydro::EntitySerializer.repository(@private_discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(@private_discussion.repository.owner),
          actor_id: @private_discussion.actor.id,
          actor: Hydro::EntitySerializer.user(@private_discussion.actor),
          discussion_id: @private_discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@private_discussion),
          lock_status: :LOCK_STATUS_UNLOCKED,
          pin_status: :PIN_STATUS_UNPINNED,
          announcement: false,
          org_or_repo_level: :ORG_OR_REPO_LEVEL_REPO,
          action: :ACTION_DISCUSSION_UPDATED,
          action_timestamp: Time.now,
          # the @private_discussion instance is a question and answers discussion
          discussion_format: :DISCUSSION_FORMAT_OPEN_ENDED,
          category_id: @private_discussion.category.id,
          converted_from_issue: false,
          converted_issue_id: nil,
          specimen_title: nil,
          specimen_body: nil,
          created_from_category_template: false,
          state: :STATE_OPEN,
          state_reason: :STATE_REASON_UNKNOWN,
        }

        assert_hydro_published(message_v2, schema: "github.discussions.v2.Discussions")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.Discussions")
      end
    end

    test "Discussion update publishes github.platform_health.v1.UserGeneratedContent" do
      discussion = create(:discussion)
      reset_hydro
      discussion.update!(title: "Something borrowed, something blue", actor: @staff)

      message = {
        request_context: nil,
        spamurai_form_signals: nil,
        action_type: :UPDATE,
        content_type: :DISCUSSION,
        actor: Hydro::EntitySerializer.user(@staff),
        original_type_url: GitHub::Config::HydroConfig.build_type_url("github.discussions.v1.DiscussionUpdate"),
        content_database_id: discussion.id,
        content_global_relay_id: discussion.global_relay_id,
        content_created_at: discussion.created_at,
        content_updated_at: discussion.updated_at,
        title: Hydro::EntitySerializer.specimen_data(discussion.title),
        content: Hydro::EntitySerializer.specimen_data(discussion.body),
        parent_content_author: nil,
        parent_content_database_id: nil,
        parent_content_global_relay_id: nil,
        parent_content_created_at: nil,
        parent_content_updated_at: nil,
        owner: Hydro::EntitySerializer.repository_owner(discussion.repository),
        repository: Hydro::EntitySerializer.repository(discussion.repository),
        content_visibility: :PUBLIC,
        content_url: Hydro::EntitySerializer.url_for_model(discussion),
      }

      with_hydro_publisher(GitHub.user_generated_content_hydro_publisher) do
        assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
      end
    end

    test "logs an event when the user adds a discussion label" do
      Timecop.freeze do
        @public_discussion.actor = @staff
        @public_discussion.add_labels([@label0])

        message = {
          repository_id: @repo.id,
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
          discussion_id: @public_discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@public_discussion),
          actor_id: @staff&.id,
          actor: Hydro::EntitySerializer.user(@staff),
          action: :ACTION_LABEL_ADDED,
          action_timestamp: Time.now,
          label_id: @label0.id
        }

        assert_hydro_published(message, schema: "github.discussions.v2.DiscussionsLabel")
      end
    end

    test "logs an event when the user removes a discussion label" do
      Timecop.freeze do
        @public_discussion.actor = @staff
        @public_discussion.labels = [@label0, @label1]
        @public_discussion.delete_labels([@label1])

        message = {
          repository_id: @repo.id,
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@owner),
          discussion_id: @public_discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@public_discussion),
          actor_id: @staff&.id,
          actor: Hydro::EntitySerializer.user(@staff),
          action: :ACTION_LABEL_REMOVED,
          action_timestamp: Time.now,
          label_id: @label1.id
        }

        assert_hydro_published(message, schema: "github.discussions.v2.DiscussionsLabel")
      end
    end
  end

  [:title, :body].each do |field|
    test "supports emoji for #{field}" do
      private_repo = create(:private_repository, has_discussions: true)
      private_discussion = create(:discussion, :repository => private_repo, field => "we ❤️ emojis")

      assert_multibyte_tracked_changes(private_discussion, field)

      public_repo = create(:repository, has_discussions: true)
      public_discussion = create(:discussion, :repository => public_repo, field => "we ❤️ emojis")

      assert_multibyte_tracked_changes(public_discussion, field)
    end
  end

  test "audit_log_update_event" do
    events = subscribe "discussion.update"
    discussion = create(:discussion)
    old_title = discussion.title
    reset_hydro
    discussion.update!(title: "Something borrowed, something blue", actor: @staff)

    expected_payload = {
      actor: @staff.login,
      actor_id: @staff.id,
      old_title: old_title,
    }

    assert event = events.pop, "a discussion.update event was expected"
    assert_equal "discussion.update", event.name
    assert_subset_hash expected_payload, event.payload
  end

  context "#orphaned?" do
    test "returns true if parent repository does not exist" do
      # Set the repo id to an id that doesn't exist
      @public_discussion.update(repository_id: 1234566343)
      assert_predicate @public_discussion, :orphaned?
    end

    test "returns true if associated discussion category does not exist" do
      # Set the category id to an id that doesn't exist
      @public_discussion.update_attribute(:discussion_category_id, 1234566343)
      assert_predicate @public_discussion, :orphaned?
    end

    test "returns false otherwise" do
      # a well constructed discussion should pass
      refute_predicate @public_discussion, :orphaned?
    end
  end

  context "async_formatted_body" do
    test "returns the formatted body used for creating a new issue" do
      formatted_body = DiscussionOpTextFormatter.new(@public_discussion).format
      assert_equal @public_discussion.async_formatted_body.sync, formatted_body
    end

    test "returns the formatted body used for creating a new issue when user has been deleted" do
      @public_discussion.user = nil
      formatted_body = DiscussionOpTextFormatter.new(@public_discussion).format

      assert_equal @public_discussion.async_formatted_body.sync, formatted_body
    end
  end
end

class DiscussionTimelineItemsForTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, has_discussions: true)
    @discussion = create(:discussion, repository: @repo)
    @event = Timecop.freeze(1.hour.ago) { create(:discussion_event, discussion: @discussion) }
    @created_issue_event = Timecop.freeze(1.hour.ago) { create(:discussion_event, discussion: @discussion, event_type: :created_issue) }
    @comment = Timecop.freeze(50.minutes.ago) { create(:discussion_comment, discussion: @discussion) }
    @group_event1 = Timecop.freeze(40.minutes.ago) do
      create(:discussion_event, discussion: @discussion, comment: @comment,
        event_type: "answer_marked")
    end
    @group_event2 = Timecop.freeze(30.minutes.ago) do
      create(:discussion_event, discussion: @discussion, comment: @comment, actor: @group_event1.actor,
        event_type: "answer_unmarked")
    end
    @viewer = create(:user)
  end

  setup do
    @event_group = DiscussionEventGroup.new([@group_event1, @group_event2])
  end

  context "#bumped_at" do
    test "is updated when discussion body is changed" do
      discussion = travel_to(1.month.ago) { create(:discussion) }

      assert_changes -> { discussion.reload.bumped_at } do
        discussion.update!(body: "it's the new me")
      end
    end

    test "is updated when a top-level comment is added" do
      discussion = travel_to(1.month.ago) { create(:discussion) }

      assert_changes -> { discussion.bumped_at } do
        create(:discussion_comment, discussion: discussion)
      end
    end

    test "is updated when a nested comment is added" do
      discussion = travel_to(1.month.ago) { create(:discussion) }

      assert_changes -> { discussion.bumped_at } do
        create(:discussion_comment, :nested, discussion: discussion)
      end
    end

    test "is not updated when a comment is deleted" do
      discussion, comment = travel_to(1.month.ago) do
        discussion = create(:discussion)
        comment = create(:discussion_comment, discussion: discussion)
        [discussion, comment]
      end

      assert_no_changes -> { discussion.bumped_at } do
        comment.destroy
      end
    end

    test "is not updated when other discussion attributes change" do
      discussion = travel_to(1.month.ago) { create(:discussion) }
      comment = create(:discussion_comment, discussion: discussion)

      assert_no_changes -> { discussion.reload.bumped_at } do
        discussion.update!(
          category: create(:discussion_category, repository: discussion.repository),
          chosen_comment: comment,
          title: "don't bump me",
        )
        create(:discussion_reaction, discussion: discussion)
        create(:discussion_spotlight, discussion: discussion)

        comment.update!(body: "ch ch ch chaaanges")
        discussion.lock(actor: discussion.user)
        discussion.unlock(actor: discussion.user)
      end
    end
  end

  context "#participant_count" do
    test "it returns the number of unique commenters plus the discussion author count" do
      discussion = create(:discussion)
      participant_one = create(:verified_user)
      participant_two = create(:verified_user)
      create(:discussion_comment, discussion: discussion, user: discussion.author)
      create(:discussion_comment, discussion: discussion, user: participant_one)
      create(:discussion_comment, discussion: discussion, user: participant_one)
      create(:discussion_comment, discussion: discussion, user: participant_two)
      create(:discussion_comment, discussion: discussion, user: discussion.author)
      create(:discussion_comment, discussion: discussion, user: participant_two)

      count = discussion.participant_count(viewer: @discussion.user)
      assert_equal 3, count
    end

    if GitHub.spamminess_check_enabled?
      test "exclude spammy users" do
        discussion = create(:discussion)
        participant = create(:verified_user)
        spammy_user = create(:verified_user)
        create(:discussion_comment, discussion: discussion, user: discussion.author)
        create(:discussion_comment, discussion: discussion, user: participant)
        create(:discussion_comment, discussion: discussion, user: spammy_user)
        spammy_user.mark_as_spammy

        count = discussion.participant_count(viewer: @discussion.user)
        assert_equal 2, count
      end
    end
  end

  context "multiple_target_for_conditional_access" do
    test "computes TFCA for multiple discussion" do
      discussions = create_list(:discussion, 5)
      result = Discussion.multiple_target_for_conditional_access(discussions)
      expected = discussions.each_with_object({}) { |v, h| h[v] = v.repository.owner }
      assert_equal expected, result
    end
  end

  test "creates an upvote after create" do
    discussion = assert_difference("DiscussionVote.count", 1) do
      create(:discussion)
    end

    assert_equal 1, discussion.votes.count
  end

  test "notifies the socket subscribers when the chosen comment has been updated" do
    discussion = create(:discussion, :question)
    old_answer, new_answer = create_pair(:discussion_comment, discussion: discussion)
    discussion.comments.stubs(:find_by).with(id: old_answer.id).returns(old_answer)
    discussion.comments.stubs(:find_by).with(id: new_answer.id).returns(new_answer)

    old_answer.expects(:notify_socket_subscribers).twice
    new_answer.expects(:notify_socket_subscribers).once

    discussion.update(chosen_comment_id: old_answer.id)
    discussion.update(chosen_comment_id: new_answer.id)
  end
end

class DiscussionRateLimitTest < GitHub::TestCase
  include RateLimitedCreationTestHelpers

  fixtures do
    @user = create(:verified_user)
    @repo = create(:repository, owner: @user, has_discussions: true)
    @creation_limit = 10
    # we have to halve the expected discussions because each discussion creation
    # also creates an upvote, which counts against the user's creation limit
    @expected_discussions = @creation_limit / 2
  end

  setup_once do
    enable_cache_storage
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    reset_cache
    reset_redis_rate_limiter
  end

  teardown_once do
    disable_cache_storage
  end

  test "disallows new creation when rate limit is exceeded" do
    enable_content_creation_rate_limiting
    Timecop.freeze do
      GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
        assert_create_limited_to(@expected_discussions, repo: @repo, creator: @user, type: :discussion)
      end
    end
  end

  test "can apply a dynamic rate limit configuration" do
    enable_content_creation_rate_limiting
    enable_feature_flag(:discussions_dynamic_creation_rate_limits)

    # Make sure the limits we're going to use below are stricter than the defaults.
    assert T.must(GitHub::RateLimitedCreation.limits[:user_minute]) > @creation_limit

    with_dynamic_rate_limits_for_discussions(user_minute: @creation_limit) do
      assert_create_limited_to(@expected_discussions, repo: @repo, creator: @user, type: :discussion)
    end

    assert_incremented_stat(
      "rate_limited_creation",
      tags: ["subject:discussion", "name:per_user_minute", "config_type:dynamic"]
    )
  end

  test "does not apply a dynamic rate limit configuration by default" do
    enable_content_creation_rate_limiting
    disable_feature_flag(:discussions_dynamic_creation_rate_limits)

    GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
      with_dynamic_rate_limits_for_discussions(user_minute: @expected_discussions - 1) do
        assert_create_limited_to(@expected_discussions, type: :discussion)
      end
    end

    assert_incremented_stat(
      "rate_limited_creation",
      tags: ["subject:discussion", "name:per_user_minute", "config_type:static"]
    )
  end

  test "does not rate limit creation of discussions when rate limiting is disabled" do
    disable_content_creation_rate_limiting
    category = create :discussion_category, repository: @repo
    Timecop.freeze do
      GitHub::RateLimitedCreation.use_custom_limits(user_minute: @creation_limit) do
        @expected_discussions.times do
          @repo.discussions.create(title: "question", body: "??", user: @user, category: category)
        end

        discussion = @repo.discussions.new(title: "question", body: "??", user: @user, category: category)
        assert discussion.save
        assert_empty discussion.errors
      end
    end
  end

  test "deleted with repository" do
    discussion = create(:discussion)

    assert_difference("Discussion.count", -1) do
      perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
        discussion.repository.remove(@member, synchronous: true)
        discussion.repository.purge(synchronous: true)
      end
    end

    refute Discussion.exists?(discussion.id)
  end

  test "counts as contributions" do
    repo = create(:public_repository)
    user = create(:verified_user)
    refute repo.contributor?(user, type: Discussion)

    category = create(:discussion_category, repository: repo)
    create(:discussion, user: user, repository: repo, category: category)

    assert repo.contributor?(user, type: Discussion)
  end
end
