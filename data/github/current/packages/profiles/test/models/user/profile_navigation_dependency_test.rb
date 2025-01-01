# typed: true
# frozen_string_literal: true

require "test_helper"

class ProfileNavigationDependencyTest < GitHub::TestCase
  setup do
    @user = create(:user)
    @user.disable_feature(:hide_customizable_dashboard_sidebar)
    @user.enable_feature(:customizable_dashboard_sidebar)
  end

  context "#eligible_to_display_profile_navigation?" do
    test "true when all conditions are met" do
      GitHub.flipper[:hide_customizable_dashboard_sidebar].disable(@user)

      create(:public_repository, owner: @user, name: User::ProfileNavigationDependency::NAVIGATION_REPO_NAME)

      assert_predicate @user, :eligible_to_display_profile_navigation?, "Expected eligible_to_display_profile_navigation? to be true"
    end

    if GitHub.spamminess_check_enabled?
      test "false when user is spammy" do
        spammy_user = create(:spammy_user)

        GitHub.flipper[:hide_customizable_dashboard_sidebar].disable(spammy_user)

        create(:public_repository, owner: spammy_user, name: User::ProfileNavigationDependency::NAVIGATION_REPO_NAME)
        create(:profile, user: spammy_user, readme_opt_in: true)

        refute_predicate spammy_user, :eligible_to_display_profile_navigation?, "Expected eligible_to_display_profile_navigation? to be false for spammy user"
      end
    end

    test "false when hide_customizable_dashboard_sidebar is enabled" do
      GitHub.flipper[:hide_customizable_dashboard_sidebar].enable(@user)

      create(:public_repository, owner: @user, name: User::ProfileNavigationDependency::NAVIGATION_REPO_NAME)
      create(:profile, user: @user, readme_opt_in: true)

      refute_predicate @user, :eligible_to_display_profile_navigation?, "Expected eligible_to_display_profile_navigation? to be false"
    end
  end

  context "#profile_navigation_visible?" do
    test "can show contents of __dashboard.md" do
      @user.stubs(:async_eligible_to_display_profile_navigation?).returns(Promise.resolve(true))
      repo = create(:private_repository, owner: @user, name: User::ProfileNavigationDependency::NAVIGATION_REPO_NAME, from_example: :profile_navigation)

      refute_empty @user.profile_navigation.data
    end
  end

  context "#profile_navigation_visible?" do

    test "false if dashboard navigation repository does not exist" do
      random_user = create(:user)
      random_user.stubs(:eligible_to_display_profile_navigation?).returns(true)
      refute_predicate random_user, :profile_navigation_visible?, "Expected profile_navigation_visible? to be true"
    end

    test "false if feature flag is disabled" do
      @user.disable_feature(:customizable_dashboard_sidebar)
      @user.stubs(:eligible_to_display_profile_navigation?).returns(true)
      repo = create(:private_repository, owner: @user, name: User::ProfileNavigationDependency::NAVIGATION_REPO_NAME, from_example: :profile_navigation)
      refute_predicate @user, :profile_navigation_visible?, "Expected profile_navigation_visible? to be false"
      @user.enable_feature(:customizable_dashboard_sidebar)
    end

    test "true when repo is private" do
      @user.stubs(:async_eligible_to_display_profile_navigation?).returns(Promise.resolve(true))
      repo = create(:private_repository, owner: @user, name: User::ProfileNavigationDependency::NAVIGATION_REPO_NAME, from_example: :profile_navigation)

      assert_predicate @user, :profile_navigation_visible?, "Expected profile_navigation_visible? to be true"
    end

    test "false when user#eligible_to_display_profile_navigation is false" do
      @user.stubs(:async_eligible_to_display_profile_navigation?).returns(Promise.resolve(false))
      repo = create(:private_repository, owner: @user, name: User::ProfileNavigationDependency::NAVIGATION_REPO_NAME, from_example: :profile_navigation)

      refute_predicate @user, :profile_navigation_visible?, "expected profile_navigation_visible? to be false"
    end

    test "false when the repo does not have a readme" do
      @user.stubs(:async_eligible_to_display_profile_navigation?).returns(false)
      repo = create(:private_repository, owner: @user, name: User::ProfileNavigationDependency::NAVIGATION_REPO_NAME)

      refute_predicate @user, :profile_navigation_visible?, "expected profile_navigation_visible? to be false"
    end

    test "true when the user is the right state and the repo is public" do
      @user.stubs(:async_eligible_to_display_profile_navigation?).returns(Promise.resolve(true))
      repo = create(:private_repository, owner: @user, name: User::ProfileNavigationDependency::NAVIGATION_REPO_NAME, from_example: :profile_navigation)

      assert_predicate @user, :profile_navigation_visible?, "Expected profile_navigation_visible? to be true"
    end

    test "false when the repository is disabled" do
      @user.stubs(:async_eligible_to_display_profile_navigation?).returns(Promise.resolve(true))
      repo = create(:private_repository, owner: @user, name: User::ProfileNavigationDependency::NAVIGATION_REPO_NAME, from_example: :profile_navigation)

      Repository.any_instance.stubs(:disabled?).returns(true)

      refute_predicate @user, :profile_navigation_visible?, "Expected profile_navigation_visible? to be false"
    end

    test "false when the repository access is disabled" do
      @user.stubs(:async_eligible_to_display_profile_navigation?).returns(Promise.resolve(true))
      repo = create(:private_repository, owner: @user, name: User::ProfileNavigationDependency::NAVIGATION_REPO_NAME, from_example: :profile_navigation)

      GitRepositoryAccess.any_instance.stubs(:disabled?).returns(true)

      refute_predicate @user, :profile_navigation_visible?, "Expected profile_navigation_visible? to be true"
    end
  end
end
