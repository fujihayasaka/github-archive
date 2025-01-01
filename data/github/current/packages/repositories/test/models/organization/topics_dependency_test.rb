# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationTopicsDependencyTest < GitHub::TestCase
  fixtures do
    @private_user = create(:user)
    @org = create :organization
    @org.add_member(@private_user) # Private by default
    @public_repo  = create :repository, owner: @org
  end

  context "#repositories_with_topic_manage_access" do
    test "includes repo viewer has both admin access to and contributions in" do
      @public_repo.add_member(@private_user, action: :admin)
      create(:issue, repository: @public_repo, user: @private_user)

      repos = @org.repositories_with_topic_manage_access(viewer: @private_user)

      assert_equal @public_repo, repos.first
    end

    test "omits repo user has admin access to but has not contributed to" do
      @public_repo.add_member(@private_user, action: :admin)

      repos = @org.repositories_with_topic_manage_access(viewer: @private_user)

      assert_empty repos
    end

    test "omits repo viewer has contributed to but lacks admin access to" do
      @public_repo.add_member(@private_user)
      create(:issue, repository: @public_repo, user: @private_user)

      repos = @org.repositories_with_topic_manage_access(viewer: @private_user)

      assert_empty repos
    end

    test "returns empty list when viewer is nil" do
      repos = @org.repositories_with_topic_manage_access(viewer: nil)

      assert_empty repos
    end

    test "only includes repos owned by the organization" do
      other_repo = create(:repository, owner: @private_user)
      create(:issue, repository: other_repo, user: @private_user)

      repos = @org.repositories_with_topic_manage_access(viewer: @private_user)

      assert_empty repos
    end
  end
end
