# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAdvisoryCommentTest < GitHub::TestCase
  include NewsiesHelper
  include StringFromBinaryTestHelper

  fixtures do
    @rando = create(:verified_user, login: "rando")
    @advisory_collab = create(:verified_user, login: "advisory-collab")
    @repository_collab = create(:verified_user, login: "repository-collab")
    @staff = create(:staff_admin_user, login: GitHub.staff_user_login)
    @advisory = create(:repository_advisory)
    @advisory_repo_owner = @advisory.repository.owner
    @advisory.add_collaborator(@advisory_collab)
    @advisory.repository.add_member(@repository_collab, action: :write)
    @comment = @advisory.comments.create(body: "test", user: @advisory_repo_owner)
    @comment_2 = @advisory.comments.create(body: "test 2", user: @advisory_collab)

    @pvr = create(:accepted_pvd_repo_advisory, author: @rando)
    @pvr.add_collaborator(@advisory_collab)
    @pvr_comment = @pvr.comments.create(body: "testing", user: @rando)
    @pvr_repo_owner = @pvr.repository.owner

    enable_notifications_for_user(@rando)
    enable_notifications_for_user(@advisory_collab)
  end

  setup do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  context "validation" do
    test "an advisory comment is invalid without an advisory" do
      assert_predicate @comment, :valid?
      @comment.repository_advisory = nil
      refute_predicate @comment, :valid?
    end

    test "an advisory comment is invalid without an author" do
      assert_predicate @comment, :valid?
      @comment.user = nil
      refute_predicate @comment, :valid?
    end

    test "an advisory comment is invalid without a body" do
      assert_predicate @comment, :valid?
      @comment.body = nil
      refute_predicate @comment, :valid?
    end

    test "an advisory comment is invalid without write permission" do
      assert_predicate @comment, :valid?
      @comment.user = @rando
      refute_predicate @comment, :valid?
    end

    test "an advisory comment is valid for advisory collaborators" do
      assert_predicate @comment, :valid?
      @comment.user = @advisory_collab
      assert_predicate @comment, :valid?
    end

    test "an advisory comment is invalid for repository collaborators" do
      assert_predicate @comment, :valid?
      @comment.user = @repository_collab
      refute_predicate @comment, :valid?
    end

    test "a comment can be created when the repository advisory is not published" do
      draft_repository_advisory = create(:draft_repository_advisory)
      draft_repository_advisory_comment = build(:repository_advisory_comment,
        repository_advisory: draft_repository_advisory
      )
      assert draft_repository_advisory_comment.save

      closed_repository_advisory = create(:closed_repository_advisory)
      closed_repository_advisory_comment = build(:repository_advisory_comment,
        repository_advisory: closed_repository_advisory
      )
      assert closed_repository_advisory_comment.save
    end

    test "when not given the custom validation context for form_submission, a comment can be created when the repository advisory is published" do
      published_repository_advisory = create(:published_repository_advisory)
      published_repository_advisory_comment = build(:repository_advisory_comment,
        repository_advisory: published_repository_advisory
      )

      assert published_repository_advisory_comment.save
    end

    test "when given the custom validation context for form_submission, a comment cannot be created if the repository advisory has already been published" do
      published_repository_advisory = create(:published_repository_advisory)
      repository_advisory_comment = build(:repository_advisory_comment,
        repository_advisory: published_repository_advisory
      )

      refute repository_advisory_comment.save(context: :form_submission)
    end

    test "an existing comment can still be updated after the repository advisory has been published" do
      repository_advisory = create(:draft_repository_advisory)
      repository_advisory_comment = create(:repository_advisory_comment,
        repository_advisory: repository_advisory,
      )
      repository_advisory.set_published

      repository_advisory_comment.body = "This is the new comment body"
      assert repository_advisory_comment.save
    end
  end

  context "notifications" do
    test "has a permalink url" do
      expected = "/#{@comment.repository.nwo}/security/advisories/#{@comment.repository_advisory.ghsa_id}#advisory-comment-#{@comment.id}"
      assert_equal expected, @comment.permalink(include_host: false)
    end

    test "uses the repository as the entity" do
      assert_equal @comment.repository, @comment.entity
    end

    test "sends notifications for mentions to collaborating users/PVR authors" do
      comment_with_author = create(:repository_advisory_comment, repository_advisory: @pvr, body: "@#{@pvr.author.login}")
      assert_delivered_web_notification(@pvr.author, comment_with_author, "mention")
      assert_delivered_email_notification(@pvr.author, comment_with_author, "mention")

      comment_with_collab = create(:repository_advisory_comment, repository_advisory: @pvr, body: "@#{@advisory_collab.login}")
      assert_delivered_web_notification(@advisory_collab, comment_with_collab, "mention")
      assert_delivered_email_notification(@advisory_collab, comment_with_collab, "mention")
    end

    test "does not send notifications for mentions to non-collaborating PVR authors" do
      @pvr.remove_collaborator(@pvr.author)
      comment = create(:repository_advisory_comment, repository_advisory: @pvr, body: "@#{@pvr.author.login}")

      refute_delivered_email_notification(@pvr.author, comment)
      refute_delivered_web_notification(@pvr.author, comment)
    end
  end

  test "supports emoji for body" do
    advisory = create(:repository_advisory)
    comment = advisory.comments.create(body: "we ❤️ emojis", user: advisory.repository.owner)

    assert_multibyte_tracked_changes(comment, :body)
  end

  context "abilities" do
    test "#viewer_can_update?, #viewer_can_delete? and viewer_can_read_user_content_edits? is true for collaborators " do
      valid_users = [@advisory_collab]
      invalid_users = [@rando, @repository_collab]
      functions_to_test = [:viewer_can_update?, :viewer_can_delete?, :viewer_can_read_user_content_edits?]
      memoized_variables = [:@viewer_can_update, :@viewer_can_delete, :@viewer_can_read_user_content_edits]

      functions_to_test.zip(memoized_variables).each do |function, variable|
        # test the valid users
        valid_users.each do |user|
          assert @comment_2.method(function).call(user), "#{function} should be true for #{user.login}"
          @comment_2.remove_instance_variable(variable)
        end

        invalid_users.each do |user|
          refute @comment_2.method(function).call(user), "#{function} should be false for #{user.login}"
          @comment_2.remove_instance_variable(variable)
        end

        refute @comment_2.method(function).call(nil), "#{function} should be false for nil"
      end
    end

    test "no one with insufficient advisory access can edit or delete a comment" do
      refute @comment.viewer_can_update?(@rando)
      refute @comment.viewer_can_update?(@repository_collab)

      refute @comment_2.viewer_can_update?(@rando)
      refute @comment_2.viewer_can_update?(@repository_collab)
    end

    test "no one can edit or delete a github-staff comment" do
      comment = @advisory.comments.create(body: "test", user: @staff)

      refute comment.viewer_can_update?(@advisory_collab)
      refute comment.viewer_can_update?(@advisory_repo_owner)

      refute comment.viewer_can_delete?(@advisory_collab)
      refute comment.viewer_can_delete?(@advisory_repo_owner)

    end

    test "collaborators can only edit or delete their own comments" do
      refute @comment.viewer_can_update?(@advisory_collab)
      refute @comment.viewer_can_delete?(@advisory_collab)

      assert @comment_2.viewer_can_update?(@advisory_collab)
      assert @comment_2.viewer_can_delete?(@advisory_collab)
    end

    test "pvr authors can only edit or delete their own comments" do
      pvr_owner_comment = @pvr.comments.create(body: "testing", user: @pvr_repo_owner)

      assert @pvr_comment.viewer_can_update?(@rando)
      assert @pvr_comment.viewer_can_delete?(@rando)

      refute pvr_owner_comment.viewer_can_update?(@rando)
      refute pvr_owner_comment.viewer_can_delete?(@rando)
    end

    test "repo maintainers can edit and delete any comment" do
      assert @comment.viewer_can_update?(@advisory_repo_owner)
      assert @comment.viewer_can_delete?(@advisory_repo_owner)

      assert @comment_2.viewer_can_update?(@advisory_repo_owner)
      assert @comment_2.viewer_can_delete?(@advisory_repo_owner)

      assert @pvr_comment.viewer_can_update?(@pvr_repo_owner)
      assert @pvr_comment.viewer_can_delete?(@pvr_repo_owner)
    end
  end
end
