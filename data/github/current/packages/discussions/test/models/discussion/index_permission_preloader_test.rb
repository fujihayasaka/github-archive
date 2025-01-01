# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionIndexPermissionPreloaderTest < GitHub::TestCase
  fixtures do
    @repo_owner, @reader = create_pair(:verified_user)

    @repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @discussions = create_pair(:discussion, repository: @repo)

    org = create(:organization, admin: @repo_owner)
    @private_repo = create(:private_repository, owner: org, has_discussions: true)
    @private_discussions = create_pair(:discussion, repository: @private_repo)

    @private_repo.add_member(@reader, action: :read)
  end

  setup do
    @categories = @repo.discussion_categories
  end

  test "logged out user does not fetch permissions and always returns false" do
    Permissions::Enforcer.stubs(:authorize).never
    Platform::Loaders::Permissions::BatchAuthorize.stubs(:load).never

    permissions = Discussion::IndexPermissionPreloader.load_for(
      repository: @repo,
      discussions: @discussions,
      categories: @categories,
      viewer: nil,
      interaction_allowed: true,
    )

    refute permissions.can?(:create_discussion)
    refute permissions.can?(:manage_discussion_spotlights)
    refute permissions.can?(:create_discussion_category)
    refute permissions.can?(:can_toggle_discussions_setting)
  end

  test "always uses the provided interaction_allowed value" do
    User::InteractionAbility.stubs(:async_interaction_allowed?).never

    permissions = Discussion::IndexPermissionPreloader.load_for(
      repository: @repo,
      discussions: @discussions,
      categories: @categories,
      viewer: @reader,
      interaction_allowed: true,
    )
  end

  test "fetches permissions for a public repo" do
    permissions = Discussion::IndexPermissionPreloader.load_for(
      repository: @repo,
      discussions: @discussions,
      categories: @categories,
      viewer: @reader,
      interaction_allowed: true,
    )

    assert permissions.can?(:create_discussion)
    refute permissions.can?(:manage_discussion_spotlights)
    refute permissions.can?(:create_discussion_category)
    refute permissions.can?(:can_toggle_discussions_setting)
  end

  test "fetches permissions for a user with admin access to a public repo" do
    permissions = Discussion::IndexPermissionPreloader.load_for(
      repository: @repo,
      discussions: @discussions,
      categories: @categories,
      viewer: @repo_owner,
      interaction_allowed: true,
    )

    assert permissions.can?(:create_discussion)
    assert permissions.can?(:manage_discussion_spotlights)
    assert permissions.can?(:create_discussion_category)
    assert permissions.can?(:can_toggle_discussions_setting)
  end

  test "fetches permissions for a user with read access to a private repo" do
    permissions = Discussion::IndexPermissionPreloader.load_for(
      repository: @private_repo,
      discussions: @private_discussions,
      categories: @categories,
      viewer: @reader,
      interaction_allowed: true,
    )

    assert permissions.can?(:create_discussion)
    refute permissions.can?(:manage_discussion_spotlights)
    refute permissions.can?(:create_discussion_category)
    refute permissions.can?(:can_toggle_discussions_setting)
  end

  test "fetches permissions for a user with admin access to a private repo" do
    permissions = Discussion::IndexPermissionPreloader.load_for(
      repository: @private_repo,
      discussions: @private_discussions,
      categories: @categories,
      viewer: @repo_owner,
      interaction_allowed: true,
    )

    assert permissions.can?(:create_discussion)
    assert permissions.can?(:manage_discussion_spotlights)
    assert permissions.can?(:create_discussion_category)
    assert permissions.can?(:can_toggle_discussions_setting)
  end
end
