# typed: true
# frozen_string_literal: true

require "test_helper"

class UserProfileReadmeDependencyTest < GitHub::TestCase
  setup do
    @user = create(:user)
  end

  context "#eligible_to_display_profile_readme?" do
    test "true when all conditions are met" do
      create(:public_repository, owner: @user, name: @user.config_repo_name)
      create(:profile, user: @user, readme_opt_in: true)

      assert_predicate @user, :eligible_to_display_profile_readme?, "Expected eligible_to_display_profile_readme? to be true"
    end

    if GitHub.spamminess_check_enabled?
      test "false when user is spammy" do
        spammy_user = create(:spammy_user)

        create(:public_repository, owner: spammy_user, name: spammy_user.config_repo_name)
        create(:profile, user: spammy_user, readme_opt_in: true)

        refute_predicate spammy_user, :eligible_to_display_profile_readme?, "Expected eligible_to_display_profile_readme? to be false for spammy user"
      end
    end

    test "false when profile_readme_opt_in is false" do
      create(:public_repository, owner: @user, name: @user.config_repo_name)
      create(:profile, user: @user, readme_opt_in: false)

      refute_predicate @user, :eligible_to_display_profile_readme?, "Expected eligible_to_display_profile_readme? to be false"
    end
  end

  context "#profile_readme_visible?" do
    test "false when repo is private" do
      @user.stubs(:eligible_to_display_profile_readme?).returns(true)
      repo = create(:private_repository, owner: @user, name: @user.config_repo_name, from_example: :profile_config)

      refute_predicate @user, :profile_readme_visible?, "Expected profile_readme_visible? to be false"
    end

    test "false when user#eligible_to_display_profile_readme is false" do
      @user.stubs(:eligible_to_display_profile_readme?).returns(false)
      repo = create(:public_repository, owner: @user, name: @user.config_repo_name, from_example: :profile_config)

      refute_predicate @user, :profile_readme_visible?, "expected profile_readme_visible? to be false"
    end

    test "false when the repo does not have a readme" do
      @user.stubs(:eligible_to_display_profile_readme?).returns(false)
      create(:public_repository, owner: @user, name: @user.config_repo_name)

      refute_predicate @user, :profile_readme_visible?, "expected profile_readme_visible? to be false"
    end

    test "true when the user is the right state and the repo is public" do
      @user.stubs(:async_eligible_to_display_profile_readme?).returns(Promise.resolve(true))
      repo = create(:public_repository, owner: @user, name: @user.config_repo_name, from_example: :profile_config)

      assert_predicate @user, :profile_readme_visible?, "Expected profile_readme_visible? to be true"
    end

    test "false when the repository is disabled" do
      @user.stubs(:eligible_to_display_profile_readme?).returns(true)
      repo = create(:public_repository, owner: @user, name: @user.config_repo_name, from_example: :profile_config)

      Repository.any_instance.stubs(:disabled?).returns(true)

      refute_predicate @user, :profile_readme_visible?, "Expected profile_readme_visible? to be false"
    end

    test "false when the repository access is disabled" do
      @user.stubs(:eligible_to_display_profile_readme?).returns(true)
      repo = create(:public_repository, owner: @user, name: @user.config_repo_name, from_example: :profile_config)

      GitRepositoryAccess.any_instance.stubs(:disabled?).returns(true)

      refute_predicate @user, :profile_readme_visible?, "Expected profile_readme_visible? to be true"
    end
  end

  context "#profile_readme_filename" do
    test "it returns the filename without the extension" do
      repo = create(:public_repository, owner: @user, name: @user.config_repo_name, from_example: :profile_config)

      assert_equal "README", @user.profile_readme_filename
    end
  end

  context "#profile_readme_file_extension" do
    test "it returns the file's extension without the name of the file" do
      repo = create(:public_repository, owner: @user, name: @user.config_repo_name, from_example: :profile_config)

      assert_equal "md", @user.profile_readme_file_extension
    end
  end
end
