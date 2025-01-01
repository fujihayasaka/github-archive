# typed: true
# frozen_string_literal: true

require "test_helper"

class MannequinAssociationRewriterTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @email = "user@github.com"
    @user = create(:user)
    create(:verified_user_email, user: @user, email: @email)
    @org  = create(:organization, admin: @user)
    @mannequin = create(:mannequin, email: @email, owner: @org)
    @repo = create(:repository, organization: @org, owner: @org)
    @issue = create(:issue, repository: @repo)
  end

  setup do
    @rewriter = MannequinAssociationRewriter.new(@mannequin, @user)
  end

  context "rewrites the right associations" do
    test "rewrites assignments" do
      assignment = build(:assignment, assignee: @mannequin, issue: @issue, repository_id: @repo.id)
      assignment.save(validate: false)

      @rewriter.rewrite!

      assignment.reload
      assert_equal assignment.assignee_id, @user.id
    end

    test "rewrites attachments" do
      attachment = Attachment.create(attacher: @mannequin, asset: create(:user_asset), attachable: @issue, entity: @repo)

      @rewriter.rewrite!

      attachment.reload
      assert_equal attachment.attacher_id, @user.id
    end

    test "rewrites commit_comments" do
      commit_comment = create(:commit_comment, user: @mannequin, repository: @repo)

      @rewriter.rewrite!

      commit_comment.reload
      assert_equal commit_comment.user_id, @user.id
    end

    test "rewrites cross_references" do
      skip "Requires an index on cross_references.actor_id"

      cross_reference = create(:cross_reference, actor: @mannequin)

      @rewriter.rewrite!

      cross_reference.reload
      assert_equal cross_reference.actor_id, @user.id
    end

    test "rewrites assigned_issues" do
      skip "Requires an index on issues.assignee_id"

      @issue.update_attribute(:assignee_id, @mannequin.id)

      @rewriter.rewrite!

      @issue.reload
      assert_equal @issue.assignee_id, @user.id
    end

    test "rewrites issues" do
      issue = create(:issue, user: @mannequin)

      @rewriter.rewrite!

      issue.reload
      assert_equal issue.user_id, @user.id
    end

    test "rewrites issue_comments" do
      issue_comment = create(:issue_comment, issue: @issue, user: @mannequin)

      @rewriter.rewrite!

      issue_comment.reload
      assert_equal issue_comment.user_id, @user.id
    end

    test "rewrites issue_events" do
      issue_event = create(:issue_event, actor: @mannequin)

      @rewriter.rewrite!

      issue_event.reload
      assert_equal issue_event.actor_id, @user.id
    end

    test "rewrites subjected_issue_event_details" do
      skip "Requires an index on issue_event_details.subject_id"

      issue_event = build(:issue_event, actor: @mannequin, event: "assigned", subject: @mannequin)
      issue_event.save(validate: false)

      @rewriter.rewrite!

      issue_event.reload
      assert_equal issue_event.subject_id, @user.id
    end

    test "rewrites projects" do
      project = build(:project, owner: @mannequin)
      project.save(validate: false)

      @rewriter.rewrite!

      project.reload
      assert_equal @user.id, project.owner_id
    end

    test "rewrites created_projects" do
      skip "Requires an index on projects.creator_id"

      project = build(:project, creator: @mannequin)
      project.save(validate: false)

      @rewriter.rewrite!

      project.reload
      assert_equal project.creator_id, @user.id
    end

    test "rewrites project_cards" do
      project_card = create(:project_card, creator: @mannequin)

      @rewriter.rewrite!

      project_card.reload
      assert_equal project_card.creator_id, @user.id
    end

    test "rewrites pull_requests" do
      pull_request = build(:pull_request, repository: @repo, user: @mannequin)
      pull_request.save(validate: false)

      @rewriter.rewrite!

      pull_request.reload
      assert_equal pull_request.user_id, @user.id
    end

    test "rewrites pull_request_reviews" do
      pull_request = build(:pull_request, repository: @repo, user: @mannequin)
      pull_request.save(validate: false)
      pr_review = build(:pull_request_review, pull_request: pull_request, user: @mannequin, head_sha: GitHub::NULL_OID, repository_id: @repo.id)
      pr_review.save(validate: false)

      @rewriter.rewrite!

      pr_review.reload
      assert_equal pr_review.user_id, @user.id
    end

    test "rewrites pull_request_review_comments" do
      skip
    end

    test "rewrites review_requests" do
      pull_request = build(:pull_request, repository: @repo, user: @mannequin)
      pull_request.save(validate: false)
      review_request = build(:review_request, pull_request: pull_request, reviewer: @mannequin, repository_id: @repo.id)
      review_request.save(validate: false)

      @rewriter.rewrite!

      review_request.reload
      assert_equal review_request.reviewer_id, @user.id
    end

    test "rewrites releases" do
      release = build(:release, repository: @repo, author: @mannequin)
      release.save(validate: false)

      assert_changes -> { release.reload.author }, from: @mannequin, to: @user do
        @rewriter.rewrite!
      end
      assert_empty @mannequin.releases
    end

    test "rewrites release_mentions" do
      release = build(:release, repository: @repo, author: @mannequin)
      release.save(validate: false)
      release_mention = create(:release_mention, release: release, user: @mannequin)

      assert_changes -> { release_mention.reload.user }, from: @mannequin, to: @user do
        @rewriter.rewrite!
      end
      assert_empty @mannequin.release_mentions
    end

    test "doesn't fail with duplicate issue assignees and continues reattribution for org when flag enabled" do
      #enable FF
      enable_feature_flag(:mannequin_claiming_duplicate_assignees, @org)

      assignee_mannequin1 = create(:mannequin, email: @email, owner: @org)
      assignee_mannequin2 = create(:mannequin, email: @email, owner: @org)
      assignees = [assignee_mannequin1, assignee_mannequin2]
      issue = create(:issue, user: assignee_mannequin1, mannequin_assignees: assignees)
      another_issue = create(:issue, user: assignee_mannequin1, mannequin_assignees: [assignee_mannequin2])

      project_card = create(:project_card, creator: assignee_mannequin2)

      rewriter1 = MannequinAssociationRewriter.new(assignee_mannequin1, @user)
      rewriter1.rewrite!
      # assert assignee_mannequin1 associations were rewritten to user
      issue.reload
      assert_equal @user.id, issue.user_id
      assert_equal [@user.id, assignee_mannequin2.id], issue.assignee_ids

      GitHub.logger.expects(:error).with do |data, hash|
        assert_equal data, "Could not rewrite all associations of assignments"
        assert_equal hash[:"code.function"], "duplicate_assignment_association"
        assert_equal hash[:"gh.migration_tools.transferable.assignment.issue_id"], issue.id
        assert_equal hash[:"gh.migration_tools.transferable.assignment.target_id"], @user.id
        assert_equal hash[:"gh.migration_tools.transferable.assignment.source_id"], assignee_mannequin2.id
      end

      rewriter2 = MannequinAssociationRewriter.new(assignee_mannequin2, @user)
      rewriter2.rewrite!
      # assert assignee_mannequin2 associations were not rewritten to user since it is a dup
      issue.reload
      assert_equal @user.id, issue.user_id
      assert_equal [@user.id], issue.assignee_ids
      # assert assignee_mannequin2 associations were rewritten to user for issues after failed reassignment
      another_issue.reload
      assert_equal @user.id, another_issue.user_id
      assert_equal [@user.id], another_issue.assignee_ids

      # assert assignee_mannequin2 associations were rewritten to user for models after assignments
      project_card.reload
      assert_equal project_card.creator_id, @user.id
    end

    test "doesn't fail with duplicate issue assignees and continues reattribution for user with flag enabled" do
      #enable FF
      enable_feature_flag(:mannequin_claiming_duplicate_assignees, @user)

      assignee_mannequin1 = create(:mannequin, email: @email, owner: @org)
      assignee_mannequin2 = create(:mannequin, email: @email, owner: @org)
      assignees = [assignee_mannequin1, assignee_mannequin2]
      issue = create(:issue, user: assignee_mannequin1, mannequin_assignees: assignees)
      another_issue = create(:issue, user: assignee_mannequin1, mannequin_assignees: [assignee_mannequin2])

      project_card = create(:project_card, creator: assignee_mannequin2)

      rewriter1 = MannequinAssociationRewriter.new(assignee_mannequin1, @user)
      rewriter1.rewrite!
      # assert assignee_mannequin1 associations were rewritten to user
      issue.reload
      assert_equal @user.id, issue.user_id
      assert_equal [@user.id, assignee_mannequin2.id], issue.assignee_ids

      GitHub.logger.expects(:error).with do |data, hash|
        assert_equal data, "Could not rewrite all associations of assignments"
        assert_equal hash[:"code.function"], "duplicate_assignment_association"
        assert_equal hash[:"gh.migration_tools.transferable.assignment.issue_id"], issue.id
        assert_equal hash[:"gh.migration_tools.transferable.assignment.target_id"], @user.id
        assert_equal hash[:"gh.migration_tools.transferable.assignment.source_id"], assignee_mannequin2.id
      end

      rewriter2 = MannequinAssociationRewriter.new(assignee_mannequin2, @user)
      rewriter2.rewrite!
      # assert assignee_mannequin2 associations were not rewritten to user since it is a dup
      issue.reload
      assert_equal @user.id, issue.user_id
      assert_equal [@user.id], issue.assignee_ids
      # assert assignee_mannequin2 associations were rewritten to user for issues after failed reassignment
      another_issue.reload
      assert_equal @user.id, another_issue.user_id
      assert_equal [@user.id], another_issue.assignee_ids

      # assert assignee_mannequin2 associations were rewritten to user for models after assignments
      project_card.reload
      assert_equal project_card.creator_id, @user.id
    end
  end
end
