# typed: true
# frozen_string_literal: true

require "test_helper"
require "hydro/schemas/github/event_payload_attachment/v0/issue_comment_attachment_pb"
require "hydro/schemas/github/event_payload_attachment/v0/entities/issue_comment_pb"

class IssueCommentTest < GitHub::TestCase
  include HydroTestHelpers
  include PullRequestIntegrationTestHelpers
  include DogstatsTestHelpers

  ROLES = GitHub::MinimizeComment::ROLES

  setup_once do
    enable_cache_storage
  end

  setup do
    reset_cache
  end

  teardown_once do
    disable_cache_storage
  end

  fixtures do
    @random_user = create(:user)
    @comment = create(:issue_comment)
    @comment_repo = @comment.issue.repository
    @comment_repo.turn_on_discussions(actor: @comment_repo.owner, instrument: false)
    @contributor_repository = create(:repository)

    example_repo :simple, @comment_repo

    @org = create(:organization)
    @org_member = create(:user)
    @org.add_member(@org_member)
    @org_owned_repo = create(:repository, owner: @org)
    @org_issue = create(:issue, repository: @org_owned_repo)
    @org_collab = create(:user)
    @org_owned_repo.add_member(@org_collab)
    @repo_collab = create(:user)
    @comment_repo.add_member(@repo_collab)
    @author = create(:user)
    @maintainer = create(:user)
    @org_owned_repo.add_member(@author, action: :read)
    @org_owned_repo.add_member(@maintainer, action: :write)
    @staff_user = create(:staff_admin_user)
    @org_owned_comment = create(:issue_comment, issue: @org_issue)

    @contributor_issue = create(:issue, repository: @contributor_repository)
    @collaborator_repository = create(:repository)
    @collaborator_issue = create(:issue, repository: @collaborator_repository)

    make_trusted_oauth_apps_owner
    @actions_app = create(:launch_integration)
    refute_nil @actions_app
  end

  def add_template_config(repo, user, config_name)
    repo.add_member user
    example_repo :simple, repo
    commit = repo.commits.create({ message: "Add org issue template config", author: user }) do |files|
      files.add ".github/ISSUE_TEMPLATE/config.yml", <<~MARKDOWN
        blank_issues_enabled: false
        contact_links:
          - name: #{config_name}
            about: faq
            url: http://stackoverflow.com
      MARKDOWN
    end
    repo.refs["refs/heads/master"].update(commit, user)
  end

  context "discussions" do
    test "cannot update an issue comment after beginning issue conversion to a discussion" do
      discussion = create(:discussion, issue: @comment.issue, repository: @comment_repo,
        number: @comment.issue.number)

      refute @comment.update_body("Brand new body", @comment.user)

      refute_predicate @comment, :valid?
      assert_includes @comment.errors[:base],
        "Cannot be modified since the issue has been converted to a discussion."
    end

    test "cannot create an issue comment after beginning issue conversion to a discussion" do
      issue = create(:issue, repository: @comment_repo)
      discussion = create(:discussion, issue: issue, repository: @comment_repo, number: issue.number)

      comment = build(:issue_comment, issue: issue, repository: @comment_repo)

      refute_predicate comment, :valid?
      assert_includes comment.errors[:base],
        "Cannot be modified since the issue has been converted to a discussion."
    end
  end

  test "does not check for spam when comment is destroyed without a repo" do
    comment_id = @comment.id

    # This test is not testing the never-to-be-used-in-production :tm: path of going through the comment to delete
    # the repository, instead it is testing that destroying a dangling comment should work. Therefore, I'm catching any
    # post-transaction issue update orchestration failure.
    @comment.repository.delete rescue ActiveRecord::RecordInvalid

    @comment.reload

    IssueComment.any_instance.expects(:enqueue_check_for_spam).never

    # Same here - the issue is dangling and therefore we'll get a validation error when validating the update orchestration.
    # The final results - that the repository and issue comment is deleted - should still hold.
    @comment.destroy rescue ActiveRecord::RecordInvalid

    assert !IssueComment.find_by(id: comment_id), "Comment should have been removed, a transaction probably failed in the background"
  end

  test "does not check for spam at all when destroyed" do
    IssueComment.any_instance.expects(:enqueue_check_for_spam).never
    @comment.destroy
  end

  test "permalink for pull request comment" do
    # avoid making a real PR since it's so complicated to set up.
    Issue.any_instance.stubs(:pull_request?).returns(true)

    expected = "%s/pull/%d#issuecomment-%d" % [
      @comment.repository.permalink,
      @comment.issue.number,
      @comment.id,
    ]
    assert_equal expected, @comment.permalink
  end

  context "#generate_issue_event" do
    test "creates an event when someone else deletes the comment" do
      modifying_user = create(:user)
      @comment.stubs(:modifying_user).returns(modifying_user)

      @comment.destroy
      issue_event = @comment.issue.events.last

      assert issue_event
      assert_equal issue_event.event, "comment_deleted"
      assert_equal issue_event.actor, modifying_user
      assert_equal issue_event.subject, @comment.user
    end

    test "does not create an event when a comment is deleted by author" do
      @comment.destroy
      assert_equal @comment.issue.events.count, 0
    end
  end

  test "can destroy comment after the repository and issue are gone" do
    c_id = @comment.id

    @comment.repository.delete
    @comment.issue.delete

    @comment.reload
    @comment.destroy

    assert !IssueComment.find_by(id: c_id), "The IssueComment should have been sanely deleted. Check the destructor chain."
  end

  test "can destroy repository under issue comment without the transaction failing" do
    c_id = @comment.id
    r_id = @comment.repository.id

    # This test is not testing the never-to-be-used-in-production :tm: path of going through the comment to delete
    # the repository, instead it is testing that destroying a dangling comment should work. Therefore, I'm catching any
    # post-transaction issue update orchestration failure.
    @comment.repository.delete rescue ActiveRecord::RecordInvalid

    @comment.reload

    # Same here - the issue is dangling and therefore we'll get a validation error when validating the update orchestration.
    # The final results - that the repository and issue comment is deleted - should still hold.
    @comment.destroy rescue ActiveRecord::RecordInvalid

    assert !Repository.find_by(id: r_id), "Repository should have ben removed, a transaction probably failed in the background"
    assert !IssueComment.find_by(id: c_id), "Comment should have been removed, a transaction probably failed in the background"
  end

  test "bodies should be UTF-8" do
    body = "Have a glass of \xF0\x9F\x8D\xB7"
    @comment.body = body
    assert @comment.save
    @comment.reload
    assert_equal Encoding::UTF_8, @comment.body.encoding
    assert_equal body, @comment.body
    assert_equal Encoding::UTF_8, @comment.compressed_body.encoding
    assert_equal body, @comment.compressed_body
  end

  context "assigning body" do
    test "assigning a body also assigns a compressed_body" do
      body = "uncompressed issue body"
      @comment.body = body
      assert_equal body, @comment.body
      assert_equal body, @comment.compressed_body
    end

    test "reassigning a body should reassign the compressed_body" do
      body = "uncompressed issue body"
      @comment.body = body
      @comment.save
      new_body = "new uncompressed issue body"
      @comment.body = new_body
      assert_equal new_body, @comment.body
      assert_equal new_body, @comment.compressed_body
    end
  end

  context "updates pull_request timestamp" do
    test "updates pull request updated_at column on creation" do
      pull = Timecop.travel(1.hour.ago) do
        create(:pull_request, :disable_disk_access)
      end
      original_updated_at = pull.updated_at

      pull.issue.reload

      perform_enqueued_jobs(only: [IssueOrchestration.job_class, IssueCommentOrchestration.job_class]) do
        create(:issue_comment, issue: pull.issue)
      end

      assert_operator pull.reload.updated_at, :>, original_updated_at
    end

    test "updates pull request updated_at column on edit" do
      pull = create(:pull_request, :disable_disk_access)
      comment = create(:issue_comment, issue: pull.issue)
      original_updated_at = pull.updated_at

      pull.issue.reload

      Timecop.travel(1.hour.from_now) do
        perform_enqueued_jobs(only: [IssueOrchestration.job_class, IssueCommentOrchestration.job_class]) do
          comment.update_body("updated content", comment.user)
        end
      end

      assert_operator pull.reload.updated_at, :>, original_updated_at
    end

    test "updates pull request updated_at column on destroy" do
      pull = create(:pull_request, :disable_disk_access)
      comment = create(:issue_comment, issue: pull.issue)
      original_updated_at = pull.updated_at

      pull.issue.reload

      Timecop.travel(1.hour.from_now) do
        perform_enqueued_jobs(only: [IssueOrchestration.job_class, IssueCommentOrchestration.job_class]) do
          assert comment.destroy
        end
      end

      assert_operator pull.reload.updated_at, :>, original_updated_at
    end
  end

  context "readable_by?" do
    test "is true when the comment is on an issue that is readable by the user" do
      assert @comment.readable_by?(create(:user))
    end

    test "is false when the comment is on an issue that is not readable by the user" do
      @comment.repository.update_attribute(:private, true)

      refute @comment.readable_by?(create(:user))
    end

    test "is false when the comment has no issue" do
      @comment.issue.delete
      @comment.reload

      refute @comment.readable_by?(create(:user))
    end
  end

  context "#async_minimizable_by?" do
    test "returns whether the given user can minimize the comment" do
      collab = create(:user)
      @comment_repo.add_member(collab)

      assert @comment.async_minimizable_by?(@comment_repo.owner).sync
      assert @comment.async_minimizable_by?(collab).sync
      refute @comment.async_minimizable_by?(create(:user)).sync
      assert @comment.async_minimizable_by?(create(:staff_admin_user)).sync

      assert @org_owned_comment.async_minimizable_by?(@org_collab).sync
      assert @org_owned_comment.async_minimizable_by?(create(:staff_admin_user)).sync
      refute @org_owned_comment.async_minimizable_by?(create(:user)).sync
      refute @org_owned_comment.async_minimizable_by?(@org_member).sync


      @org.block(@org_owned_comment.user)

      assert @org_owned_comment.async_minimizable_by?(@org_collab).sync
      assert @org_owned_comment.async_minimizable_by?(create(:staff_admin_user)).sync
      refute @org_owned_comment.async_minimizable_by?(create(:user)).sync
      refute @org_owned_comment.async_minimizable_by?(@org_member).sync
    end

    test "returns true for comment authored by user" do
      collab = create(:user)
      @comment_repo.add_member(collab, action: :read)
      comment = create(:issue_comment, repository: @comment_repo, user: collab)
      assert comment.async_minimizable_by?(collab).sync
    end

    if GitHub.organization_moderators_enabled?
      test "returns true for organization moderator" do
        @org.moderation.add_moderator(@org_member, actor: @org.admin)
        assert @org.moderator?(@org_member)
        assert @org_owned_comment.async_minimizable_by?(@org_member).sync
      end

      test "returns false for organization moderator in private repo" do
        @org_owned_repo.update!(public: false)
        assert_predicate @org_owned_repo, :private?
        @org.moderation.add_moderator(@org_member, actor: @org.admin)
        assert @org.moderator?(@org_member)
        refute @org_owned_comment.async_minimizable_by?(@org_member).sync
      end
    end

    test "returns false for user without write access if minimizing other users comment" do
      collab = create(:user)
      @comment_repo.add_member(collab, action: :read)
      refute @comment.async_minimizable_by?(collab).sync
    end

    unless GitHub.enterprise?
      test "returns false for the Actions App on a public repo when it does not have permission" do
        random_repo = create(:public_repository, name: "random-repo")
        comment_repo = create(:public_repository, name: "comment-repo")

        installation = make_integration_installation(
          integration: @actions_app,
          repository: comment_repo,
          permissions: { "issues" => :write },
        )

        scoped_installation = make_scoped_integration_installation(
          parent: installation,
          repositories: [comment_repo],
          permissions: { "issues" => :write },
        )

        issue = create(:issue, repository: comment_repo)
        comment = create(:issue_comment, issue: issue, user: scoped_installation.bot)

        random_installation = make_integration_installation(
          integration: @actions_app,
          repository: random_repo,
          permissions: { "issues" => :write },
        )

        random_scoped_installation = make_scoped_integration_installation(
          parent: random_installation,
          repositories: [random_repo],
          permissions: { "issues" => :write },
        )

        refute comment.async_minimizable_by?(random_scoped_installation.bot).sync
      end

      test "returns true for the Actions App on a public repo when it has permission" do
        comment_repo = create(:public_repository, name: "comment-repo")

        installation = make_integration_installation(
          integration: @actions_app,
          repository: comment_repo,
          permissions: { "issues" => :write },
        )

        scoped_installation = make_scoped_integration_installation(
          parent: installation,
          repositories: [comment_repo],
          permissions: { "issues" => :write },
        )

        issue = create(:issue, repository: comment_repo)
        comment = create(:issue_comment, issue: issue, user: scoped_installation.bot)

        assert comment.async_minimizable_by?(scoped_installation.bot).sync
      end
    end
  end

  context "#async_viewer_can_update?" do
    test "returns whether the given user can edit the issue" do
      issue = @comment.issue
      refute_predicate issue, :locked?

      repo   = issue.repository
      owner  = repo.owner
      collab = create(:user)
      author = issue.user
      user   = create(:user)
      staff  = create(:staff_admin_user)

      repo.add_member(collab)

      # author is not a repo collab
      refute_includes repo.members, author

      assert @comment.async_viewer_can_update?(owner).sync
      assert @comment.async_viewer_can_update?(collab).sync
      assert @comment.async_viewer_can_update?(author).sync
      refute @comment.async_viewer_can_update?(staff).sync
      refute @comment.async_viewer_can_update?(user).sync
      refute @comment.async_viewer_can_update?(nil).sync

      assert issue.lock(owner)
      assert_predicate issue, :locked?

      # Find a new object so that we don't keep any cached ivars around
      @comment = IssueComment.find(@comment.id)

      assert @comment.async_viewer_can_update?(owner).sync
      assert @comment.async_viewer_can_update?(collab).sync
      refute @comment.async_viewer_can_update?(author).sync
      refute @comment.async_viewer_can_update?(staff).sync
      refute @comment.async_viewer_can_update?(user).sync
      refute @comment.async_viewer_can_update?(nil).sync
    end

    test "with anonymous user and ghost author" do
      @comment.user.destroy
      @comment.reload

      assert_nil @comment.user

      refute @comment.async_viewer_can_update?(nil).sync
    end

    test "with locked thread" do
      issue = @comment.issue
      assert !issue.locked?

      repo   = issue.repository
      owner  = repo.owner
      collab = create(:user)
      author = @comment.user
      user   = create(:user)
      staff  = create(:staff_admin_user)

      repo.add_member(collab)

      # author is not a repo collab
      refute_includes repo.members, author

      assert issue.lock(owner)
      assert issue.locked?

      assert @comment.async_viewer_can_update?(owner).sync
      assert @comment.async_viewer_can_update?(collab).sync
      refute @comment.async_viewer_can_update?(author).sync
      refute @comment.async_viewer_can_update?(user).sync
      refute @comment.async_viewer_can_update?(nil).sync
    end

    test "with archived repository" do
      issue = @comment.issue
      assert !issue.locked?

      repo   = issue.repository
      owner  = repo.owner
      collab = create(:user)
      author = @comment.user
      user   = create(:user)
      staff  = create(:staff_admin_user)

      repo.add_member(collab)

      # author is not a repo collab
      refute_includes repo.members, author

      repo.set_archived
      assert issue.locked?

      refute @comment.async_viewer_can_update?(owner).sync
      refute @comment.async_viewer_can_update?(collab).sync
      refute @comment.async_viewer_can_update?(author).sync
      refute @comment.async_viewer_can_update?(user).sync
      refute @comment.async_viewer_can_update?(nil).sync
    end
  end

  context "#async_viewer_cannot_update_reasons" do
    test "returns a list of reason codes that describe why the the given user can not edit" do
      issue = @comment.issue
      refute_predicate issue, :locked?

      repo   = issue.repository
      owner  = repo.owner
      collab = create(:user)
      author = issue.user
      user   = create(:user)
      staff  = create(:staff_admin_user)

      repo.add_member(collab)

      # author is not a repo collab
      refute_includes repo.members, author

      assert_empty @comment.async_viewer_cannot_update_reasons(owner).sync
      assert_empty @comment.async_viewer_cannot_update_reasons(collab).sync
      assert_empty @comment.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:insufficient_access], @comment.async_viewer_cannot_update_reasons(staff).sync
      assert_equal [:insufficient_access], @comment.async_viewer_cannot_update_reasons(user).sync
      assert_equal [:login_required], @comment.async_viewer_cannot_update_reasons(nil).sync

      # owner has blocked author
      repo.owner.block(author)
      assert_equal [:insufficient_access], @comment.async_viewer_cannot_update_reasons(owner).sync
      assert_equal [:insufficient_access], @comment.async_viewer_cannot_update_reasons(collab).sync
      assert_equal [:insufficient_access], @comment.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:insufficient_access], @comment.async_viewer_cannot_update_reasons(staff).sync
      assert_equal [:insufficient_access], @comment.async_viewer_cannot_update_reasons(user).sync
      assert_equal [:login_required], @comment.async_viewer_cannot_update_reasons(nil).sync
      repo.owner.unblock(author)

      # author has blocked collab
      author.block(collab)
      assert_empty @comment.async_viewer_cannot_update_reasons(owner).sync
      assert_equal [:insufficient_access], @comment.async_viewer_cannot_update_reasons(collab).sync
      assert_empty @comment.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:insufficient_access], @comment.async_viewer_cannot_update_reasons(staff).sync
      assert_equal [:insufficient_access], @comment.async_viewer_cannot_update_reasons(user).sync
      assert_equal [:login_required], @comment.async_viewer_cannot_update_reasons(nil).sync
      author.unblock(collab)

      # collab has blocked author
      collab.block(author)
      assert_empty @comment.async_viewer_cannot_update_reasons(owner).sync
      assert_equal [:insufficient_access], @comment.async_viewer_cannot_update_reasons(collab).sync
      assert_empty @comment.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:insufficient_access], @comment.async_viewer_cannot_update_reasons(staff).sync
      assert_equal [:insufficient_access], @comment.async_viewer_cannot_update_reasons(user).sync
      assert_equal [:login_required], @comment.async_viewer_cannot_update_reasons(nil).sync
      collab.unblock(author)

      assert issue.lock(owner)
      assert_predicate issue, :locked?

      # Find a new object so that we don't keep any cached ivars around
      @comment = IssueComment.find(@comment.id)

      assert_empty @comment.async_viewer_cannot_update_reasons(owner).sync
      assert_empty @comment.async_viewer_cannot_update_reasons(collab).sync
      assert_equal [:locked], @comment.async_viewer_cannot_update_reasons(author).sync
      assert_equal [:locked, :insufficient_access], @comment.async_viewer_cannot_update_reasons(staff).sync
      assert_equal [:locked, :insufficient_access], @comment.async_viewer_cannot_update_reasons(user).sync
      assert_equal [:login_required], @comment.async_viewer_cannot_update_reasons(nil).sync
    end

    context "when interaction limits are enabled" do
      test "returns insufficient_access for non-collaborator author" do
        comment = create :issue_comment, repository: @org_owned_repo, user: @random_user
        assert_empty comment.async_viewer_cannot_update_reasons(@random_user).sync

        interaction = RepositoryInteractionAbility.new(@org_owned_repo)
        interaction.set_ability(:collaborators_only, @org.admins.first)

        assert_equal [:insufficient_access], comment.async_viewer_cannot_update_reasons(@random_user).sync
      end

      test "returns empty list for maintainer author" do
        comment = create :issue_comment, repository: @org_owned_repo, user: @author
        interaction = RepositoryInteractionAbility.new(@org_owned_repo)
        interaction.set_ability(:collaborators_only, @org.admins.first)
        assert_empty comment.async_viewer_cannot_update_reasons(@maintainer).sync
      end
    end
  end

  context "#async_viewer_can_create_issue?" do
    test "viewer cannot create a blank issue if not collaborator" do
      local_repo = create :repository, owner: @org, name: "local"
      user = create :user
      viewer = create :user

      # adds a config with blank_issues_enabled = false
      add_template_config(local_repo, user, "local_config")
      assert !@comment.async_viewer_can_create_issue?(viewer, local_repo).sync
    end

    test "viewer can create blank issue if collab" do
      local_repo = create :repository, owner: @org, name: "local"
      user = create :user
      viewer = create :user

      # adds a config with blank_issues_enabled = false
      add_template_config(local_repo, user, "local_config")
      local_repo.add_member viewer

      local_repo.add_member viewer
      assert @comment.async_viewer_can_create_issue?(viewer, local_repo).sync
    end
  end

  context "#async_viewer_can_delete?" do
    test "returns whether the given user can delete the issue" do
      issue = @comment.issue
      refute_predicate issue, :locked?

      repo   = issue.repository
      owner  = repo.owner
      collab = create(:user)
      author = issue.user
      user   = create(:user)
      staff  = create(:staff_admin_user)

      repo.add_member(collab)

      # author is not a repo collab
      refute_includes repo.members, author

      assert @comment.async_viewer_can_delete?(owner).sync
      assert @comment.async_viewer_can_delete?(collab).sync
      assert @comment.async_viewer_can_delete?(author).sync
      assert @comment.async_viewer_can_delete?(staff).sync
      refute @comment.async_viewer_can_delete?(user).sync
      refute @comment.async_viewer_can_delete?(nil).sync

      assert issue.lock(owner)
      assert_predicate issue, :locked?

      # Find a new object so that we don't keep any cached ivars around
      issue = Issue.find(issue.id)

      assert @comment.async_viewer_can_delete?(owner).sync
      assert @comment.async_viewer_can_delete?(collab).sync
      refute @comment.async_viewer_can_delete?(author).sync
      assert @comment.async_viewer_can_delete?(staff).sync
      refute @comment.async_viewer_can_delete?(user).sync
      refute @comment.async_viewer_can_delete?(nil).sync
    end

    test "can delete ghost user comments" do
      issue = @comment.issue
      repo   = issue.repository
      owner  = repo.owner
      @comment.user.destroy
      @comment.reload

      assert @comment.async_viewer_can_delete?(owner).sync
    end

    test "owner can delete blocked user comments" do
      author = @comment.user
      owner = @comment.repository.owner
      owner.block(author)
      assert @comment.async_viewer_can_delete?(owner).sync
    end

    test "owner can delete blocking user comments" do
      author = @comment.user
      owner = @comment.repository.owner
      author.block(owner)
      assert @comment.async_viewer_can_delete?(owner).sync
    end
  end

  context "#preload_viewer_attributes" do
    test "viewer as repo collaborator" do
      collab = create(:user)
      @comment_repo.add_member(collab)

      @comment.preload_viewer_attributes(collab, @comment_repo)

      assert @comment.viewer_can_minimize?
      assert @comment.viewer_can_update?
      assert_equal [], @comment.viewer_cannot_update_reasons
      assert @comment.viewer_can_delete?
    end

    test "viewer as repo collaborator in read-only mode" do
      collab = create(:user)
      @comment_repo.add_member(collab, action: :read)

      @comment.preload_viewer_attributes(collab, @comment_repo)

      refute @comment.viewer_can_minimize?
      refute @comment.viewer_can_update?
      refute @comment.viewer_can_delete?
    end

    test "viewer as org collaborator" do
      @org_owned_comment.preload_viewer_attributes(@org_collab, @comment_repo)

      assert @org_owned_comment.viewer_can_minimize?
      assert @org_owned_comment.viewer_can_update?
      assert @org_owned_comment.viewer_can_delete?
    end

    test "viewer as repo collaborator when issue is locked" do
      collab = create(:user)
      @comment_repo.add_member(collab)

      issue = @comment.issue
      repo = issue.repository
      assert issue.lock(repo.owner)
      assert_predicate issue, :locked?

      @comment = IssueComment.find(@comment.id)
      @comment.preload_viewer_attributes(collab, @comment_repo)

      assert @comment.viewer_can_update?
      assert @comment.viewer_can_delete?
    end

    test "viewer as an author and a collaborator with read access to repository" do
      collab = create(:user)
      @comment_repo.add_member(collab, action: :read)
      comment = create(:issue_comment, repository: @comment_repo, user: collab)

      comment.preload_viewer_attributes(collab, @commen_repo)

      assert comment.viewer_can_minimize?
    end

    test "viewer as an author and not a repo collaborator" do
      issue = @comment.issue
      refute_predicate issue, :locked?
      author = issue.user
      repo = issue.repository

      refute_includes repo.members, author
      @comment.preload_viewer_attributes(author, repo)

      assert @comment.viewer_can_update?
      assert @comment.viewer_can_delete?
      assert_equal [], @comment.viewer_cannot_update_reasons

      # repo archived
      repo.set_archived
      assert issue.locked?
      @comment.preload_viewer_attributes(author, repo)

      refute @comment.viewer_can_update?
      refute @comment.viewer_can_delete?
      assert_equal [:locked], @comment.viewer_cannot_update_reasons
    end
  end

  test "uses the editing user (not the original user) permissions when editing" do
    issue = @comment.issue
    repo  = issue.repository
    owner = repo.owner
    owner.update(plan: "medium")

    user = create(:user, plan: "medium")
    user_private_repo   = create(:private_repository, owner: user)
    owner_private_repo  = create(:private_repository, owner: owner)
    user_private_issue  = create(:issue, repository: user_private_repo,  user: user)
    owner_private_issue = create(:issue, repository: owner_private_repo, user: owner)

    user_private_reference  = [user_private_repo.name_with_owner,  user_private_issue.number].join("#")
    owner_private_reference = [owner_private_repo.name_with_owner, owner_private_issue.number].join("#")

    body  = "Hooray! a comment with some references: "
    body += user_private_reference + " "
    body += owner_private_reference

    comment = create(:issue_comment, repository: repo, issue: issue, user: owner, body: body)

    assert_includes comment.body, "Hooray!"
    refute_includes comment.body_html, %Q[href="#{user_private_issue.permalink}"]
    assert_includes comment.body_html, %Q[href="#{owner_private_issue.permalink}"]

    body  = "Hooray! editing the comment with some references: "
    body += user_private_reference + " "
    body += owner_private_reference

    comment.update_body(body, user)
    comment = IssueComment.find(comment.id)

    assert_includes comment.body, "Hooray!"
    assert_includes comment.body_html, %Q[href="#{user_private_issue.permalink}"]
    refute_includes comment.body_html, %Q[href="#{owner_private_issue.permalink}"]
  end

  test "persists integration id in user_content_edits when edited via integration" do
    issue = @comment.issue
    repo  = issue.repository
    owner = repo.owner

    installation = make_integration_installation(repository: repo, permissions: { "issues" => :write })
    integration = installation.integration

    assert_empty @comment.user_content_edits

    @comment.update_body("Hooray! editing the comment via integrations!", owner, performed_via_integration: integration)

    assert_equal integration.id, @comment.user_content_edits.last.performed_by_integration_id
  end

  test "validates comment limit" do
    issue = create(:issue, issue_comments_count: (Issue::COMMENT_LIMIT - 1))
    comment = create(:issue_comment, issue: issue)
    assert_empty comment.errors

    begin
      issue = create(:issue, issue_comments_count: Issue::COMMENT_LIMIT)
      comment = create(:issue_comment, issue: issue)
    rescue ActiveRecord::RecordInvalid => e
      assert_match "Commenting is disabled on issues with more than 2500 comments", e.message
    end
  end

  test "validates that the repo owner has not blocked the comment author" do
    issue = create(:issue)
    repo_owner = issue.repository.owner
    blocked_user = create(:user)
    repo_owner.block(blocked_user)

    ex = assert_raises(ActiveRecord::RecordInvalid) do
      create(:issue_comment, user: blocked_user, issue: issue)
    end
    assert_equal "Validation failed: User is blocked", ex.message
  end

  test "validates that the issue creator has not blocked the comment author" do
    issue = create(:issue)
    issue_creator = issue.user
    blocked_user = create(:user)
    issue_creator.block(blocked_user)

    ex = assert_raises(ActiveRecord::RecordInvalid) do
      create(:issue_comment, user: blocked_user, issue: issue)
    end
    assert_equal "Validation failed: User is blocked", ex.message
  end

  context "interaction limit validations" do
    test "pass on creation when the author is allowed" do
      interaction = RepositoryInteractionAbility.new(@org_owned_repo)
      interaction.set_ability(:collaborators_only, @org.admins.first)

      create :issue_comment, repository: @org_owned_repo, user: @maintainer, issue: @org_issue
    end

    test "fail on creation when the author is not allowed" do
      interaction = RepositoryInteractionAbility.new(@org_owned_repo)
      interaction.set_ability(:collaborators_only, @org.admins.first)

      ex = assert_raises(ActiveRecord::RecordInvalid) do
        create :issue_comment, repository: @org_owned_repo, user: @random_user
      end
      assert_equal "Validation failed: could not be created. Interactions on this repository have been restricted to collaborators only.",
        ex.message
    end

    test "pass on update when the editor is allowed" do
      comment = create :issue_comment, repository: @org_owned_repo, user: @random_user

      interaction = RepositoryInteractionAbility.new(@org_owned_repo)
      interaction.set_ability(:collaborators_only, @org.admins.first)

      assert comment.update_body("hello!", @maintainer)
      assert_empty comment.errors[:base]
    end

    test "fail on update when the editor is not allowed" do
      comment = create :issue_comment, repository: @org_owned_repo, user: @random_user

      interaction = RepositoryInteractionAbility.new(@org_owned_repo)
      interaction.set_ability(:collaborators_only, @org.admins.first)

      refute comment.update_body("hello!", @random_user)

      assert_includes comment.errors[:base],
        "could not be created. Interactions on this repository have been restricted to collaborators only."
    end
  end

  test "refutes issue comments on locked repo not within migration" do
    Repository.any_instance.stubs(:locked_on_migration?).returns(true)
    refute @comment.valid?
    assert_includes_match /has been locked for migration/,
      @comment.errors.full_messages
  end

  test "accepts issue comments on locked repo within migration" do
    Repository.any_instance.stubs(:locked_on_migration?).returns(true)
    GitHub.stubs(:importing?).returns(true)
    assert @comment.valid?
  end

  test "does not allow a repo to be archived" do
    Repository.any_instance.stubs(:archived?).returns(true)
    refute @comment.valid?
    assert_includes_match /unable to create comment because issue is locked/,
      @comment.errors.full_messages
  end

  if GitHub.email_verification_enabled?
    test "validates that the modifying user must have a verified email" do
      @comment.user.stubs(:content_creation_requires_email_verification?).returns(true)
      assert @comment.user.must_verify_email?,
        "Bad assumption: User is not required to verify their email address."
      @comment.body = "Something is different, did you get a haircut?"
      refute @comment.valid?
      assert_includes_match /email address must be verified/,
        @comment.errors.full_messages
    end

    test "users with verified emails can edit unverified users' comments" do
      @comment.user = create(:verified_user)
      @comment.user.stubs(:must_verify_email?).returns(true)
      @comment.stubs(:modifying_user).returns(create(:user))
      assert @comment.valid?
    end

    test "users with verified emails can comment" do
      @comment.user = create(:verified_user)
      @comment.user.stubs(:content_creation_requires_email_verification?).returns(true)
      assert @comment.valid?
    end
  end

  test "doesn't raise when user is missing" do
    @comment.user = nil
    @comment.valid?
  end

  test "doesn't subscribe mentioned users when the author is spammy", feature_disabled: :notifyd_issue_watch_activity_notify do
    issue = create(:issue)
    spammy_user = create(:user, login: "spammy", plan: "medium", spammy: true)
    mentioned_user = create(:user, login: "innocent", plan: "medium")
    issue_comment = create(:issue_comment, :wait_for_orchestration,
      user: spammy_user,
      body: "Hey @innocent, lookit this",
    )
    refute issue_comment.subscribed?(mentioned_user)
  end

  test "doesn't subscribed mentioned users when the author is blocked", feature_disabled: :notifyd_issue_watch_activity_notify do
    issue = create(:issue)
    mean_user = create :user, login: "meanie"
    mentioned_user = create :user, login: "nice-person"
    mentioned_user.block(mean_user)
    issue_comment = create(:issue_comment, :wait_for_orchestration,
      user: mean_user,
      body: "Hey @nice-person I am mean.",
    )
    refute issue_comment.subscribed?(mentioned_user)
  end

  test "only subscribes to issue on create" do
    issue = create(:issue)

    issue.expects(:subscribe).with(issue.user, :comment).once
    issue_comment = create(:issue_comment, :wait_for_orchestration,
      issue: issue,
      user: issue.user,
      body: "hello world",
    )

    issue.expects(:subscribe).with(issue.user, :comment).never
    issue_comment.update!(body: "foo bar")
  end

  test "its thread for notifications is the issue" do
    assert_equal @comment.issue, @comment.notifications_thread
  end

  test "rate limited per user" do
    enable_content_creation_rate_limiting
    user = create(:user)
    begin
      GitHub::RateLimitedCreation.use_custom_limits(user_minute: 1) do
        comment = create :issue_comment, user: user
        assert_empty comment.errors
        create :issue_comment, user: user
      end
    rescue ActiveRecord::RecordInvalid => e
      assert_match "submitted too quickly", e.message
    end
  end

  context "IssueCommentEvent spammy tests" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      skip "spamminess checks are not enabled on Enterprise" unless GitHub.spamminess_check_enabled?
    end

    test "is triggered if the comment is not spammy" do
      T.unsafe(GitHub).reset_stratocaster

      comment = T.let(nil, T.untyped)
      perform_enqueued_jobs(only: ProcessEventJob) { comment = create(:issue_comment, :wait_for_orchestration) }

      assert event = GitHub.stratocaster_store.last, "expected a stratocaster event to be triggered"
      assert_equal "IssueCommentEvent", event.event_type
      assert_equal comment.id, event.payload["comment"]["id"]
    end

    test "is NOT triggered if the comment is spammy" do
      T.unsafe(GitHub).reset_stratocaster

      spammer = create :user, spammy: true
      comment = T.let(nil, T.untyped)
      perform_enqueued_jobs(only: ProcessEventJob) { comment = create :issue_comment, user: spammer }

      assert comment.spammy?
      refute GitHub.stratocaster_store.all.detect { |e| e.event_type == "IssueCommentEvent" }, "expected NO stratocaster event to be triggered for a spammy comment"
    end
  end

  context "Instrumentation" do
    test "issue_comment.create is triggered when creating an issue comment" do
      events = subscribe "issue_comment.create"
      comment = create(:issue_comment, :wait_for_orchestration)
      expected_payload = {
        repo: comment.repository.nwo,
        repo_id: comment.repository.id,
        public_repo: comment.repository.public?,
        issue_id: comment.issue.id,
        issue_comment_id: comment.id,
        spammy: comment.spammy?,
        allowed: false,
        body: comment.body,
      }

      assert event = events.pop, "expected an instrumentation event"
      assert_equal expected_payload, event.payload
    end

    test "issue_comment create event is published to hydro" do
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")

        issue_creator = create(:user)
        issue = create :issue, user: issue_creator
        repository = issue.repository
        actor = create(:user)
        mentioned_user = create(:user)
        issue_comment = create :issue_comment, :wait_for_orchestration, user: actor, issue: issue, body: "@#{mentioned_user} yeah?"

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(actor),
          repository: Hydro::EntitySerializer.repository(repository),
          repository_owner: Hydro::EntitySerializer.user(repository.owner),
          issue: Hydro::EntitySerializer.issue(issue),
          issue_creator: Hydro::EntitySerializer.user(issue_creator),
          issue_comment: Hydro::EntitySerializer.issue_comment(issue_comment),
          body: issue_comment.body,
          specimen_body: Hydro::EntitySerializer.specimen_data(issue_comment.body),
        }

        with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
          assert_hydro_published(message, schema: "github.v1.IssueCommentCreate")
        end
      end
    end

    test "IssueComment create publishes github.platform_health.v1.UserGeneratedContent" do
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        issue_creator = create(:user)
        issue = create :issue, user: issue_creator
        repository = issue.repository
        actor = create(:user)
        mentioned_user = create(:user)
        reset_hydro

        issue_comment = create :issue_comment, :wait_for_orchestration, user: actor, issue: issue, body: "@#{mentioned_user} yeah?"

        message = {
          request_context: nil,
          spamurai_form_signals: nil,
          action_type: :CREATE,
          content_type: :ISSUE_COMMENT,
          actor: Hydro::EntitySerializer.user(actor),
          original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.IssueCommentCreate"),
          content_database_id: issue_comment.id,
          content_global_relay_id: issue_comment.global_relay_id,
          content_created_at: issue_comment.created_at,
          content_updated_at: issue_comment.updated_at,
          content: Hydro::EntitySerializer.specimen_data(issue_comment.body),
          parent_content_author: Hydro::EntitySerializer.user(issue_creator),
          parent_content_database_id: issue.id,
          parent_content_global_relay_id: issue.global_relay_id,
          parent_content_created_at: issue.created_at,
          parent_content_updated_at: issue.updated_at,
          owner: Hydro::EntitySerializer.user(repository.owner),
          repository: Hydro::EntitySerializer.repository(repository),
          content_visibility: :PUBLIC,
          content_url: Hydro::EntitySerializer.url_for_model(issue_comment),
        }

        with_hydro_publisher(GitHub.user_generated_content_hydro_publisher) do
          assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
        end
      end
    end

    test "issue_comment update event is published to hydro" do
      GitHub.context.push(actor_ip: "3ffe:505:2::1")
      GitHub.context.push(user_agent: "test agent")

      issue_creator = create(:user)
      issue = create :issue, user: issue_creator
      repository = issue.repository
      actor = create(:user)
      issue_comment = create :issue_comment, user: actor, issue: issue, body: "Old Body"
      issue_comment.update!(body: "New Body")

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(actor),
        repository: Hydro::EntitySerializer.repository(repository),
        repository_owner: Hydro::EntitySerializer.user(repository.owner),
        issue: Hydro::EntitySerializer.issue(issue),
        issue_creator: Hydro::EntitySerializer.user(issue_creator),
        issue_comment: Hydro::EntitySerializer.issue_comment(issue_comment),
        current_specimen_body: Hydro::EntitySerializer.specimen_data(issue_comment.body),
        previous_specimen_body: Hydro::EntitySerializer.specimen_data("Old Body"),
      }

      with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
        assert_hydro_published(message, schema: "github.v1.IssueCommentUpdate")
      end
    end

    test "IssueComment update publishes github.platform_health.v1.UserGeneratedContent" do
      issue_creator = create(:user)
      issue = create :issue, user: issue_creator
      repository = issue.repository
      actor = create(:user)
      issue_comment = create :issue_comment, user: actor, issue: issue, body: "Old Body"
      reset_hydro

      issue_comment.update!(body: "New Body")

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        spamurai_form_signals: nil,
        action_type: :UPDATE,
        content_type: :ISSUE_COMMENT,
        actor: Hydro::EntitySerializer.user(actor),
        original_type_url: GitHub::Config::HydroConfig.build_type_url("github.v1.IssueCommentUpdate"),
        content_database_id: issue_comment.id,
        content_global_relay_id: issue_comment.global_relay_id,
        content_created_at: issue_comment.created_at,
        content_updated_at: issue_comment.updated_at,
        content: Hydro::EntitySerializer.specimen_data(issue_comment.body),
        parent_content_author: Hydro::EntitySerializer.user(issue_creator),
        parent_content_database_id: issue.id,
        parent_content_global_relay_id: issue.global_relay_id,
        parent_content_created_at: issue.created_at,
        parent_content_updated_at: issue.updated_at,
        owner: Hydro::EntitySerializer.user(repository.owner),
        repository: Hydro::EntitySerializer.repository(repository),
        content_visibility: :PUBLIC,
        content_url: Hydro::EntitySerializer.url_for_model(issue_comment),
      }

      with_hydro_publisher(GitHub.user_generated_content_hydro_publisher) do
        assert_hydro_published(message, schema: "github.platform_health.v1.UserGeneratedContent")
      end
    end

    test "creating issue comment for pull request published a hydro event" do
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        pull_request = setup_pull_request
        repository = pull_request.repository
        GitHub.hydro_publisher.sink&.messages&.clear
        issue_comment = create :issue_comment, :wait_for_orchestration, user: pull_request.user, issue: pull_request.issue

        expected_feature_flags = ["login_revocation_for_credential_in_url_enabled"]

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(pull_request.user),
          repository_owner: Hydro::EntitySerializer.user(repository.owner),
          repository: Hydro::EntitySerializer.repository(repository),
          issue: Hydro::EntitySerializer.issue(pull_request.issue),
          issue_comment: Hydro::EntitySerializer.issue_comment(issue_comment),
          body: issue_comment.body,
          feature_flags: expected_feature_flags,
        }

        with_hydro_publisher(GitHub.hydro_publisher) do
          assert_hydro_published(message, schema: "github.v1.PullRequestTimelineCommentCreate")
        end
      end
    end

    test "issue_comment.update is triggered when updating an issue comment's body" do
      events = subscribe "issue_comment.update"
      comment = create(:issue_comment, body: "Old Body")

      modifying_user = create(:user)
      comment.stubs(:modifying_user).returns(modifying_user)
      comment.update!(body: "New Body")

      expected_payload = {
        issue_id: comment.issue.id,
        issue_comment_id: comment.id,
        spammy: comment.spammy?,
        old_body: "Old Body",
        body: "New Body",
        repo: comment.repository.nwo,
        private_repo: comment.repository.private?,
        repo_id: comment.repository.id,
        public_repo: comment.repository.public?,
        allowed: false,
      }

      assert event = events.pop, "expected an instrumentation event"
      assert_equal expected_payload, event.payload
    end

    test "issue_comment.update is not triggered when body content does not change on update" do
      events = subscribe "issue_comment.update"
      comment = create(:issue_comment, body: "Old Body")

      comment.update!(body: comment.body)

      assert_empty events
    end

    test "issue_comment.destroy is triggered when an issue comment is destroyed" do
      events = subscribe "issue_comment.destroy"
      comment = create(:issue_comment)
      comment.destroy
      expected_payload = {
        issue_id: comment.issue.id,
        issue_comment_id: comment.id,
        spammy: comment.spammy?,
        repo: comment.repository.nwo,
        repo_id: comment.repository_id,
        public_repo: comment.repository.public?,
        body: comment.body,
        allowed: false,
        author: comment.user.login,
        author_id: comment.user.id
      }

      assert event = events.pop, "expected an instrumentation event"
      assert_equal expected_payload, event.payload
    end

    test "instruments hydro.schemas.events_platform.v0.Tier1Event hydro event when issue comment is deleted and feature flag is enabled" do
      now = Time.now.beginning_of_day
      Timecop.freeze(now) do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          mock_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
          Events::Tier1EventPublisher.expects(:new_guid).returns(mock_guid).at_least_once

          last_writes = {
            mysql1: { gtid: "000-000", time: Time.now.to_i * 1000 },
            repositories: { gtid: "000-000", time: Time.now.to_i * 1000 }
          }
          DatabaseSelector::ReplicationState.expects(:current).at_least_once.returns(DatabaseSelector::ReplicationState.new)
          DatabaseSelector::ReplicationState.any_instance.expects(:to_hash).at_least_once.returns(last_writes)

          comment = create(:issue_comment)

          GitHub.flipper[:events_v2_publish_tier1_event].enable(Events::ParentAsActor.repo_actor(comment.repository.id))

          attachment = Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment.new({
            issue_comment: Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::IssueComment.new({
              id: comment.id,
              issue_id: comment.issue_id,
              user_id: Google::Protobuf::Int64Value.new(value: comment.user_id),
              created_at: Google::Protobuf::Timestamp.new(seconds: comment.created_at.to_i),
              updated_at: Google::Protobuf::Timestamp.new(seconds: comment.updated_at.to_i),
              repository_id: comment.repository_id,
              formatter: Google::Protobuf::StringValue.new(value: comment.formatter.to_s),
              user_hidden: comment.user_hidden,
              performed_by_integration_id: nil,
              comment_hidden: comment.comment_hidden ? 1 : 0,
              comment_hidden_reason: nil,
              comment_hidden_classifier: nil,
              comment_hidden_by: nil,
              compressed_body: Google::Protobuf::BytesValue.new(value: comment.read_attribute_before_type_cast(:compressed_body).to_s),
            })
          })

          message = {
            guid: mock_guid,
            type: :EVENT_TYPE_ISSUE_COMMENT,
            action: :EVENT_ACTION_DELETED,
            target: {
              primary_entity: {
                type: :ENTITY_TYPE_ISSUE_COMMENT,
                id: comment.id.to_s,
                graphql_global_relay_id: comment.global_relay_id,
                graphql_next_global_id: comment.next_global_id,
              },
              related_entities: [{
                type: :ENTITY_TYPE_REPOSITORY,
                id: comment.repository.id.to_s,
                graphql_global_relay_id: comment.repository.global_relay_id,
                graphql_next_global_id: comment.repository.next_global_id,
              },
              {
                type: :ENTITY_TYPE_ISSUE,
                id: comment.issue.id.to_s,
                graphql_global_relay_id: comment.issue.global_relay_id,
                graphql_next_global_id: comment.issue.next_global_id,
              }],
            },
            triggered_at: now,
            actor: {
              type: :ENTITY_TYPE_USER,
              id: comment.modifying_user.id.to_s,
              graphql_global_relay_id: comment.modifying_user.global_relay_id,
              graphql_next_global_id: comment.modifying_user.next_global_id,
            },
            event_attachment: {
              type_url: "type.googleapis.com/hydro.schemas.github.event_payload_attachment.v0.IssueCommentAttachment",
              message: T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment).encode(attachment)
            },
            target_repository_id: comment.repository.id,
            target_organization_id: comment.repository&.organization_id,
            target_business_id: comment.repository&.organization&.business&.id,
          }
          delivery_system = mock("delivery_system")
          delivery_system.expects(:generate_hookshot_payloads).once
          delivery_system.expects(:deliver_later).once
          Hook::DeliverySystem.expects(:new).with do |params|
            assert_equal mock_guid, params.event_guid
          end.once.returns(delivery_system)

          comment.destroy

          assert_hydro_published(message, schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: "events_platform.v0.IssueComment", ignore_extra_keys: true)
        end
      end
    end

    test "instruments hydro.schemas.events_platform.v0.Tier1Event hydro event when issue comment is deleted with common guid" do
      Hook.stubs(:delivers_in_test?).returns(true)
      now = Time.now.beginning_of_day
      Timecop.freeze(now) do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          mock_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
          Events::Tier1EventPublisher.expects(:new_guid).returns(mock_guid).at_least_once

          last_writes = {
            mysql1: { gtid: "000-000", time: Time.now.to_i * 1000 },
            repositories: { gtid: "000-000", time: Time.now.to_i * 1000 }
          }
          DatabaseSelector::ReplicationState.expects(:current).at_least_once.returns(DatabaseSelector::ReplicationState.new)
          DatabaseSelector::ReplicationState.any_instance.expects(:to_hash).at_least_once.returns(last_writes)

          comment = create(:issue_comment)

          GitHub.flipper[:events_v2_publish_tier1_event].enable(Events::ParentAsActor.repo_actor(comment.repository.id))

          attachment = Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment.new({
            issue_comment: Hydro::Schemas::Github::EventPayloadAttachment::V0::Entities::IssueComment.new({
              id: comment.id,
              issue_id: comment.issue_id,
              user_id: Google::Protobuf::Int64Value.new(value: comment.user_id),
              created_at: Google::Protobuf::Timestamp.new(seconds: comment.created_at.to_i),
              updated_at: Google::Protobuf::Timestamp.new(seconds: comment.updated_at.to_i),
              repository_id: comment.repository_id,
              formatter: Google::Protobuf::StringValue.new(value: comment.formatter.to_s),
              user_hidden: comment.user_hidden,
              performed_by_integration_id: nil,
              comment_hidden: comment.comment_hidden ? 1 : 0,
              comment_hidden_reason: nil,
              comment_hidden_classifier: nil,
              comment_hidden_by: nil,
              compressed_body: Google::Protobuf::BytesValue.new(value: comment.read_attribute_before_type_cast(:compressed_body)&.to_s),
            })
          })

          message = {
            guid: mock_guid,
            type: :EVENT_TYPE_ISSUE_COMMENT,
            action: :EVENT_ACTION_DELETED,
            target: {
              primary_entity: {
                type: :ENTITY_TYPE_ISSUE_COMMENT,
                id: comment.id.to_s,
                graphql_global_relay_id: comment.global_relay_id,
                graphql_next_global_id: comment.next_global_id,
              },
              related_entities: [{
                type: :ENTITY_TYPE_REPOSITORY,
                id: comment.repository.id.to_s,
                graphql_global_relay_id: comment.repository.global_relay_id,
                graphql_next_global_id: comment.repository.next_global_id,
              },
              {
                type: :ENTITY_TYPE_ISSUE,
                id: comment.issue.id.to_s,
                graphql_global_relay_id: comment.issue.global_relay_id,
                graphql_next_global_id: comment.issue.next_global_id,
              }],
            },
            triggered_at: now,
            actor: {
              type: :ENTITY_TYPE_USER,
              id: comment.modifying_user.id.to_s,
              graphql_global_relay_id: comment.modifying_user.global_relay_id,
              graphql_next_global_id: comment.modifying_user.next_global_id,
            },
            event_attachment: {
              type_url: "type.googleapis.com/hydro.schemas.github.event_payload_attachment.v0.IssueCommentAttachment",
              message: T.unsafe(Hydro::Schemas::Github::EventPayloadAttachment::V0::IssueCommentAttachment).encode(attachment)
            },
            target_repository_id: comment.repository.id,
            target_organization_id: comment.repository&.organization_id,
            target_business_id: comment.repository&.organization&.business&.id,
          }
          comment.destroy

          assert_hydro_published(message, schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: "events_platform.v0.IssueComment", ignore_extra_keys: true)
        end
      end
    end

    test "does not instrument hydro.schemas.events_platform.v0.Tier1Event hydro event when issue comment is deleted and events_2_publish_tier1_event feature flag is disabled" do
      now = Time.now.beginning_of_day
      Timecop.freeze(now) do
        with_hydro_publisher(GitHub.sync_hydro_publisher) do
          mock_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
          Events::Tier1EventPublisher.expects(:new_guid).returns(mock_guid).at_least_once

          last_writes = {
            mysql1: { gtid: "000-000", time: Time.now.to_i * 1000 },
            repositories: { gtid: "000-000", time: Time.now.to_i * 1000 }
          }
          DatabaseSelector::ReplicationState.expects(:current).at_least_once.returns(DatabaseSelector::ReplicationState.new)
          DatabaseSelector::ReplicationState.any_instance.expects(:to_hash).at_least_once.returns(last_writes)

          comment = create(:issue_comment)

          GitHub.flipper[:events_v2_publish_tier1_event].disable

          comment.destroy
          assert_hydro_messages(count: 0, schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: "events_platform.v0.IssueComment")
        end
      end
    end

    test "issue_comment.destroy contains an org if the repo is part of an org" do
      events = subscribe "issue_comment.destroy"
      org = create(:organization)
      comment = create(:issue_comment, issue: create(:issue, repository: create(:repository, owner: org)))
      comment.destroy
      expected_payload = {
        issue_id: comment.issue.id,
        issue_comment_id: comment.id,
        spammy: comment.spammy?,
        repo: comment.repository.nwo,
        repo_id: comment.repository_id,
        public_repo: comment.repository.public?,
        org: org.to_s,
        org_id: org.id,
        body: comment.body,
        allowed: false,
        author: comment.user.login,
        author_id: comment.user.id
      }

      assert event = events.pop, "expected an instrumentation event"
      assert_equal expected_payload, event.payload
    end

    test "issue_comment.destroy does not raise errors when the user does not exist" do
      comment = create(:issue_comment)
      user = comment.user

      user.delete
      comment.reload

      refute comment.user
      comment.destroy
    end

    test "issue_comment.update contains an org if the repo is part of an org" do
      events = subscribe "issue_comment.update"
      org = create(:organization)
      old_body = "comment"
      new_body = "butts"
      comment = create(:issue_comment, issue: create(:issue, repository: create(:repository, owner: org)), body: old_body)
      modifying_user = create(:user)
      comment.stubs(:modifying_user).returns(modifying_user)
      comment.update!(body: new_body)
      expected_payload = {
        issue_id: comment.issue.id,
        issue_comment_id: comment.id,
        spammy: comment.spammy?,
        old_body: old_body,
        body: new_body,
        repo: comment.repository.nwo,
        repo_id: comment.repository.id,
        public_repo: comment.repository.public?,
        org: org.to_s,
        org_id: org.id,
        allowed: false,
        private_repo: comment.repository.private?,
      }

      assert event = events.pop, "expected an instrumentation event"
      assert_equal expected_payload, event.payload
    end
  end

  test "destroys if the issue no longer exists" do
    org = create(:organization)
    ephemeral_issue = create(:issue, repository: create(:repository, owner: org))
    comment = create(:issue_comment, issue: ephemeral_issue)

    ephemeral_issue.delete
    comment.reload
    assert comment.destroy
    assert_nil IssueComment.find_by(id: comment.id)
  end

  test "deletes issue comment reactions in background" do
    IssueCommentReaction.react(
      user: @comment.user,
      subject_id: @comment.id,
      content: "tada"
    )
    assert_equal IssueCommentReaction.count, 1

    only = [DestroyDependentRecordsJob]
    perform_enqueued_jobs(only: only) do
      @comment.destroy
    end

    assert_performed_jobs 1
    assert_equal IssueCommentReaction.count, 0
  end

  context "#duplicate_issues" do
    test "doesn't return issues when keyword syntax is incorrect" do
      duplicate_issue = create(:issue, repository: @comment_repo)
      second_duplicate_issue = create(:issue, repository: @comment_repo)
      nonconforming_comment_bodies = [
        "This is a duplicate of ##{duplicate_issue.number}",
        "Duplicate of ##{duplicate_issue.number}. Duplicate of ##{second_duplicate_issue.number}",
        "Duplicate of ##{duplicate_issue.number}.\n Also this cleans up the UI",
        "Duplicate of ##{duplicate_issue.number}\n Also this cleans up the UI",
      ]

      nonconforming_comment_bodies.each do |comment_body|
        @comment.body = comment_body

        assert_empty @comment.duplicate_issues
      end
    end

    test "returns issues marked as duplicates by issue number" do
      duplicate_issue = create(:issue, repository: @comment_repo)

      @comment.body = "Duplicate of ##{duplicate_issue.number}"

      assert_same_elements [duplicate_issue], @comment.duplicate_issues
    end

    test "returns issues marked as duplicates by URL" do
      dupe_issue1 = create(:issue, repository: @comment_repo)
      dupe_issue1_url = "#{GitHub.url}/#{@comment_repo.nwo}/issues/#{dupe_issue1.number}"

      @comment.body = "Duplicate of #{dupe_issue1_url}"

      assert_equal [dupe_issue1], @comment.duplicate_issues
    end

    test "returns issues marked as duplicates by repo name with owner and issue number" do
      dupe_issue1 = create(:issue, repository: @comment_repo)

      @comment.body = "Duplicate of #{@comment_repo.nwo}##{dupe_issue1.number}"

      assert_same_elements [dupe_issue1], @comment.duplicate_issues
    end

    test "does not include issue when it is not marked as a duplicate" do
      duplicate_issue = create(:issue, repository: @comment_repo)

      @comment.body = "This line is a duplicate of some logic that was added in " +
                      "##{duplicate_issue.number}. Can you DRY it up?"

      assert_empty @comment.duplicate_issues
    end
  end

  unless GitHub.enterprise?
    test "fails validation if user is comment blocked" do
      User::InteractionAbility.stubs(:interaction_allowed?).returns(false)
      User::InteractionAbility.stubs(:ban_expiry).returns(DateTime.now + 1.day)
      begin
        comment = create(:issue_comment)
      rescue ActiveRecord::RecordInvalid => e
        assert_includes e.message, "suspended for 1 day"
      end
    end
  end

  context "restricted by repository comment checks" do
    context "sock puppet ban" do
      test "denies a 0-day account" do
        RepositoryInteractionAbility.stubs(:sockpuppet_disallowed_enabled?).returns(true)

        begin
          comment = create(:issue_comment)
        rescue ActiveRecord::RecordInvalid => e
          assert_includes e.message, "new users"
        end
      end

      test "allows a 3 day old account" do
        RepositoryInteractionAbility.stubs(:sockpuppet_disallowed_enabled?).returns(true)
        User.any_instance.stubs(:created_at).returns(3.days.ago)

        comment = create(:issue_comment)
        assert comment.valid?
      end

      test "allows a contributor that is new" do
        RepositoryInteractionAbility.stubs(:sockpuppet_disallowed_enabled?).returns(true)

        contributor = create(:user)
        CommitContribution.create(repository: @contributor_repository, user: contributor)
        comment = create(:issue_comment, issue: @contributor_issue, user: contributor)
        assert (Time.current - contributor.created_at) / 1.hour < RepositoryInteractionAbility::TIME_LIMIT_HOURS

        assert comment.valid?
      end

      test "allows a collaborator that is new" do
        RepositoryInteractionAbility.stubs(:sockpuppet_disallowed_enabled?).returns(true)

        collaborator = create(:user)
        @collaborator_repository.add_member(collaborator)
        comment = create(:issue_comment, issue: @collaborator_issue, user: collaborator)
        assert (Time.current - collaborator.created_at) / 1.hour < RepositoryInteractionAbility::TIME_LIMIT_HOURS

        assert comment.valid?
      end
    end

    context "prior contributor" do
      test "denies a non-contributor" do
        RepositoryInteractionAbility.stubs(:contributors_only_enabled?).returns(true)

        begin
          comment = create(:issue_comment, issue: @contributor_issue)
        rescue ActiveRecord::RecordInvalid => e
          assert_includes e.message, "prior contributors only"
        end
      end

      test "allows a contributor" do
        RepositoryInteractionAbility.stubs(:contributors_only_enabled?).returns(true)

        contributor = create(:user)
        CommitContribution.create(repository: @contributor_repository, user: contributor)
        comment = create(:issue_comment, issue: @contributor_issue, user: contributor)
        assert comment.valid?
      end

      test "allows a collaborator that has not contributed" do
        RepositoryInteractionAbility.stubs(:contributors_only_enabled?).returns(true)

        collaborator = create(:user)
        @collaborator_repository.add_member(collaborator)
        comment = create(:issue_comment, issue: @collaborator_issue, user: collaborator)
        refute @collaborator_issue.repository.contributor?(collaborator)
        assert comment.valid?
      end
    end

    context "collaborator" do
      test "denies a non-collaborator" do
        RepositoryInteractionAbility.stubs(:collaborators__only_enabled?).returns(true)

        begin
          comment = create(:issue_comment, issue: @collaborator_issue)
        rescue ActiveRecord::RecordInvalid => e
          assert_includes e.message, "collaborators only"
        end
      end

      test "allows a collaborator" do
        RepositoryInteractionAbility.stubs(:collaborators__only_enabled?).returns(true)

        collaborator = create(:user)
        @collaborator_repository.add_member(collaborator)
        comment = create(:issue_comment, issue: @collaborator_issue, user: collaborator)
        assert comment.valid?
      end
    end
  end unless GitHub.enterprise?

  context "unminimize a comment" do
    test "only staff can unminimize staff comment" do
      @org_owned_comment.update(comment_hidden_by: ROLES[:minimized_by_staff])
      refute @org_owned_comment.async_unminimizable_by?(@author).sync
      refute @org_owned_comment.async_unminimizable_by?(@maintainer).sync
      assert @org_owned_comment.async_unminimizable_by?(create(:staff_admin_user)).sync
    end

    test "maintainer & staff can unminimize maintainer-minimized comment" do
      @org_owned_comment.update(comment_hidden_by: ROLES[:minimized_by_maintainer])
      assert @org_owned_comment.async_unminimizable_by?(@maintainer).sync
      assert @org_owned_comment.async_unminimizable_by?(@staff_user).sync
      refute @org_owned_comment.async_unminimizable_by?(@author).sync
    end

    test "maintainer, staff & the commenting author can unminimize author-minimized comment" do
      comment_author = create(:verified_user)
      author_comment = create(:issue_comment, issue: @org_issue, user: comment_author)

      author_comment.update(comment_hidden_by: ROLES[:minimized_by_author])
      assert author_comment.async_unminimizable_by?(@maintainer).sync
      assert author_comment.async_unminimizable_by?(@staff_user).sync
      refute author_comment.async_unminimizable_by?(@author).sync
      assert author_comment.async_unminimizable_by?(comment_author).sync
    end

    test "contributor cannot unminimize maintainer-minimized comment" do
      @org_owned_comment.update(comment_hidden_by: ROLES[:minimized_by_maintainer])
      refute @org_owned_comment.async_unminimizable_by?(@author).sync
      assert @org_owned_comment.async_unminimizable_by?(@staff_user).sync # Admin doesn't sync, it doesn't go async when actor is admin
    end

    test "stores the right comment hidden by value" do
      author_minimized_comment = create(:issue_comment, issue: @org_issue, repository: @org_owned_repo)
      author_minimized_comment.set_minimized(@author, "reason", "spam", @author, staff = false)

      maintainer_minimized_comment = create(:issue_comment, issue: @org_issue, repository: @org_owned_repo)
      maintainer_minimized_comment.set_minimized(@maintainer, "reason", "spam", @author, staff = false)

      staff_minimized_comment = create(:issue_comment, issue: @org_issue, repository: @org_owned_repo)
      staff_minimized_comment.set_minimized(@staff_user, "reason", "spam", @author, staff = true)


      assert_equal("minimized_by_author", author_minimized_comment.comment_hidden_by)
      assert_equal("minimized_by_maintainer", maintainer_minimized_comment.comment_hidden_by)
      assert_equal("minimized_by_staff", staff_minimized_comment.comment_hidden_by)
    end
  end

  context "live updates" do
    test "notifies pull timeline on update" do
      Timecop.freeze do
        pull    = create(:pull_request, :disable_disk_access)
        comment = create(:issue_comment, issue: pull.issue)

        data = {
          timestamp: Time.now.to_i,
          wait: comment.default_live_updates_wait,
          reason: "issue comment ##{comment.id} updated",
          gid: comment.global_relay_id,
        }

        channel = GitHub::WebSocket::Channels.pull_request_timeline(pull)
        GitHub::WebSocket.stubs(:notify_pull_request_channel).returns([])
        GitHub::WebSocket.expects(:notify_pull_request_channel).with(pull, channel, data).returns([]).once

        comment.update_body("new content", comment.user)
      end
    end

    test "notifies issue timeline on update" do
      Timecop.freeze do
        issue   = create(:issue)
        comment = create(:issue_comment, issue: issue)

        data = {
          timestamp: Time.now.to_i,
          wait: comment.default_live_updates_wait,
          reason: "issue comment ##{comment.id} updated",
          gid: comment.global_relay_id,
        }

        channel = GitHub::WebSocket::Channels.issue_timeline(issue)
        GitHub::WebSocket.stubs(:notify_issue_channel).returns([])
        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, channel, data).returns([]).once

        comment.update_body("new content", comment.user)
      end
    end

    test "updating issue comment triggers websocket copilot summary messages" do
      Timecop.freeze do
        issue                  = create(:issue)
        issue_channel          = GitHub::WebSocket::Channels.issue(issue)
        issue_timeline_channel = GitHub::WebSocket::Channels.issue_timeline(issue)
        issue_summary_channel  = GitHub::WebSocket::Channels.issue_summary(issue)

        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, issue_channel, anything).returns([]).once
        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, issue_timeline_channel, anything).returns([]).once
        GitHub::WebSocket.expects(:notify_issue_channel).with(issue, issue_summary_channel, anything).returns([]).twice

        comment = create(:issue_comment, issue: issue)
        comment.update_body("new content", comment.user)
      end
    end
  end

  context "slash commands" do
    test "detects slash commands on save on org owned issue" do
      GitHub.flipper[:embedded_slash_commands].enable

      comment = build(:issue_comment, issue: @org_issue, body: "contains a \n/command")
      assert comment.contains_slash_commands?
      assert comment.should_process_slash_commands?

      assert_enqueued_with(job: ProcessEmbeddedSlashCommandsJob) do
        comment.save
      end
    end

    test "doesn't detect slash commands on save on user owned issue" do
      GitHub.flipper[:embedded_slash_commands].enable

      comment = build(:issue_comment, issue: @collaborator_issue, body: "contains a \n/command")
      assert comment.contains_slash_commands?
      refute comment.should_process_slash_commands?

      assert_no_enqueued_jobs(only: ProcessEmbeddedSlashCommandsJob) do
        comment.save
      end
    end

    test "doesn't detect slash commands on save if feature flag is disabled" do
      GitHub.flipper[:embedded_slash_commands].disable

      comment = build(:issue_comment, issue: @org_issue, body: "contains a \n/command")
      assert comment.contains_slash_commands?
      refute comment.should_process_slash_commands?

      assert_no_enqueued_jobs(only: ProcessEmbeddedSlashCommandsJob) do
        comment.save
      end
    end

    test "doesn't detect slash commands on update of on org owned issue" do
      GitHub.flipper[:embedded_slash_commands].enable

      comment = create(:issue_comment, issue: @org_issue, body: "contains a \n/command")
      assert comment.contains_slash_commands?
      assert comment.should_process_slash_commands?

      assert_no_enqueued_jobs(only: ProcessEmbeddedSlashCommandsJob) do
        comment.save
      end
    end

    test "doesn't detect slash commands if one is not present" do
      GitHub.flipper[:embedded_slash_commands].enable

      comment = build(:issue_comment, issue: @org_issue, body: "does not contain a command")
      refute comment.contains_slash_commands?
      refute comment.should_process_slash_commands?

      assert_no_enqueued_jobs(only: ProcessEmbeddedSlashCommandsJob) do
        comment.save
      end
    end
  end

  context "issue orchestrations" do
    test "does not create an orchestration when issue comment count is updated" do
      issue = create(:issue, :wait_for_orchestration)
      issue.reload # reset issue.previous_changes

      perform_enqueued_jobs(only: IssueCommentOrchestrationJob) do
        create(:issue_comment, issue: issue)
      end

      orchestration_count = UpdateIssueOrchestration.where(issue_id: issue.id).count

      assert_equal 1, orchestration_count
    end
  end

  test "updating a comment calls attach_matching_assets once" do
    Attachment.expects(:attach).once

    @comment.update_body "New content", @comment.user

    assert_dogstats_distribution 1, "attach_matching_assets.inline.time", tags: ["class:issue_comment"]
  end

  test "updating a comment doesn't call attach_matching_assets during an issue transfer" do
    @comment.expects(:attach_matching_assets).never
    @comment.stubs(:issue_transfer).returns(true)

    @comment.update_body "New content", @comment.user
  end

  # We want to keep the transaction around `update_body` as short as possible.
  # This test ensures that we don't accidentally add any dependencies to `body_html` within
  # the transaction because that leads to expensive data loading and Markdown/HTML parsing.
  test "updating a comment doesn't run markdown pipelines during transaction" do
    IssueComment.transaction do
      @comment.expects(:body_html).never
      @comment.update_body "New content", @comment.user
      @comment.expects(:body_html).once
    end
  end
end
