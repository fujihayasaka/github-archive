# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionDeleterTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @org = create(:organization)
    repo = create(:repository, owner: @org)
    category = create(:discussion_category, repository: repo)
    @discussion = create(:discussion, category: category, repository: repo)
  end

  setup do
    @deleter = DiscussionDeleter.new(@discussion)
  end

  context ".delete_all_in_org" do
    test "enqueues a DeleteOrganizationDiscussionsForUserJob" do
      admin = create(:user)
      DiscussionDeleter.delete_all_in_org(owner: @org, user: @user, actor: admin)
      assert_enqueued_with(job: DeleteOrgDiscussionsForUserJob, args: [{ organization_id: @org.id, user_id: @user.id, actor_id: admin.id }], queue: "delete_org_discussions_for_user")
    end

    test "does not enqueue if the repo is owned by a user" do
      admin = create(:user)
      assert_enqueued_jobs 0, only: DeleteOrgDiscussionsForUserJob do
        DiscussionDeleter.delete_all_in_org(owner: @user, user: @user, actor: admin)
      end
    end
  end

  context "#delete" do
    test "deletes the discussion" do
      assert_difference(-> { Discussion.count } => -1) do
        assert @deleter.delete(@user)
      end

      refute Discussion.exists?(@discussion.id)
    end

    test "creates a DeletedDiscussion record" do
      assert_difference(-> { DeletedDiscussion.count }) do
        assert @deleter.delete(@user)
      end

      deleted_discussion = DeletedDiscussion.for_repository(@discussion.repository_id).
        with_number(@discussion.number).first
      deleted_discussion = T.must(deleted_discussion)
      refute_nil deleted_discussion
      assert_equal @user, deleted_discussion.deleted_by
      assert_equal @discussion.id, deleted_discussion.old_discussion_id
    end

    test "rolls back when something fails" do
      Discussion.any_instance.stubs(:destroy).returns(false)

      assert_no_difference([-> { Discussion.count }, -> { DeletedDiscussion.count }]) do
        refute @deleter.delete(@user)
      end
    end

    context "deletes the associated discussion comments" do
      test "deletes the associated discussion comments" do
        discussion_comment = create(:discussion_comment, discussion: @discussion)
        assert_difference(-> { Discussion.count } => -1) do
          perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
            assert @deleter.delete(@user)
          end
        end

        refute Discussion.exists?(@discussion.id)
        refute DiscussionComment.exists?(discussion_comment.id)
      end

      test "deletes the associated discussion comments even if comment user is deleted" do
        user = create(:verified_user)
        discussion_comment = create(:discussion_comment, discussion: @discussion, user: user)
        user.destroy

        refute User.exists?(user.id)
        assert DiscussionComment.exists?(discussion_comment.id)

        assert_difference(-> { Discussion.count } => -1) do
          perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
            assert @deleter.delete(@user)
          end
        end

        hydro_payload = hydro_messages(schema: "github.discussions.v1.DiscussionCommentDelete").first
        assert_nil hydro_payload[:discussion_comment][:discussion]
        assert_nil hydro_payload[:discussion_comment][:user]
        assert_equal discussion_comment.id, hydro_payload[:discussion_comment][:id]

        refute Discussion.exists?(@discussion.id)
        refute DiscussionComment.exists?(discussion_comment.id)
      end

      test "deletes the associated discussion comments even if the repository is deleted" do
        repo = create(:repository, owner: @org)
        category = create(:discussion_category, repository: repo)
        discussion = create(:discussion, repository: repo, category: category)
        discussion_comment = create(:discussion_comment, discussion: discussion, repository: repo)
        deleter = DiscussionDeleter.new(discussion)

        assert_difference(-> { Discussion.count } => -1) do
          perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
            assert repo.destroy
          end
        end

        refute Repository.exists?(repo.id)
        refute Discussion.exists?(discussion.id)
        assert_nil DiscussionComment.find_by(id: discussion_comment.id)
        hydro_payload = hydro_messages(schema: "github.discussions.v1.DiscussionCommentDelete").first
        refute_nil hydro_payload
        assert_equal discussion_comment.id, hydro_payload[:discussion_comment][:id]
      end
    end
  end
end
