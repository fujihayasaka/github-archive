# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class DeleteOrgDiscussionsForUserJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @user = create(:user)
    @org = create(:organization)
    repo = create(:repository, owner: @org)
    category = create(:discussion_category, repository: repo)
    @discussion = create(:discussion, category: category, repository: repo)
    @author = @discussion.user
  end

  context "#perform" do
    test "deletes the given discussion" do
      assert_difference(-> { Discussion.count } => -1) do
        DeleteOrgDiscussionsForUserJob.perform_now(organization_id: @org.id, user_id: @author.id, actor_id: @user.id)
      end

      refute Discussion.exists?(@discussion.id)
    end

    test "deletes another discussion by the author in the same repo" do
      other_discussion = create(:discussion, repository: @discussion.repository, user: @discussion.user)

      assert_difference(-> { Discussion.count } => -2) do
        DeleteOrgDiscussionsForUserJob.perform_now(organization_id: @org.id, user_id: @author.id, actor_id: @user.id)
      end

      refute Discussion.exists?(other_discussion.id)
    end

    test "does not delete a discussion by a different user than the author" do
      other_discussion = create(:discussion, repository: @discussion.repository)

      assert_difference(-> { Discussion.count } => -1) do
        DeleteOrgDiscussionsForUserJob.perform_now(organization_id: @org.id, user_id: @author.id, actor_id: @user.id)
      end

      assert Discussion.exists?(other_discussion.id)
    end

    test "deletes another discussion by the author in a different repo owned by the same org" do
      other_repo = create(:repository, has_discussions: true, owner: @discussion.repository.organization)
      other_discussion = create(:discussion, repository: other_repo, user: @discussion.user)

      assert_difference(-> { Discussion.count } => -2) do
        DeleteOrgDiscussionsForUserJob.perform_now(organization_id: @org.id, user_id: @author.id, actor_id: @user.id)
      end

      refute Discussion.exists?(other_discussion.id)
    end

    test "does not delete a discussion by the author in a different org" do

      other_discussion = create(:discussion, user: @discussion.user)

      assert_difference(-> { Discussion.count } => -1) do
        DeleteOrgDiscussionsForUserJob.perform_now(organization_id: @org.id, user_id: @author.id, actor_id: @user.id)
      end

      assert Discussion.exists?(other_discussion.id)
    end
  end
end
