# typed: true
# frozen_string_literal: true

require "test_helper"

class PackageRegistryHelperTest < GitHub::TestCase
  setup do
    @user = create(:user)
  end

  if GitHub.enterprise?
    test "show packages can be disabled/enabled" do
      GitHub.stubs(:registry_enabled_for_enterprise?).returns(false)
      assert_equal(PackageRegistryHelper.show_packages?, false)
      assert_equal(PackageRegistryHelper.ghes_registry_enabled?, false)
      GitHub.stubs(:registry_enabled_for_enterprise?).returns(true)
      assert(PackageRegistryHelper.show_packages?)
      assert(PackageRegistryHelper.ghes_registry_enabled?)
      GitHub.stubs(:registry_v2_enabled_for_enterprise?).returns(false)
      assert_equal(PackageRegistryHelper.ghes_registry_v2_enabled?, false)
      GitHub.stubs(:registry_v2_enabled_for_enterprise?).returns(true)
      assert(PackageRegistryHelper.ghes_registry_v2_enabled?)
    end

    test "returns true when ghes setup is pending" do
      GitHub.stubs(:actions_packages_enterprise_setup_pending?).returns(true)
      assert_equal true, PackageRegistryHelper.show_packages?
    end
  else
    test "show packages is always true" do
      assert(PackageRegistryHelper.show_packages?)
    end

    test "return false when package registry is not enabled" do
      GitHub.stubs(:package_registry_enabled?).returns(false)

      refute_predicate PackageRegistryHelper, :show_packages?
    end
  end

  context "allow_access_to_actor" do
    test "Owners is a spammy user, other actor should not have access" do
      skip if !GitHub.spamminess_check_enabled?
      namespace = create(:user, spammy: true)
      actor = create(:user)
      assert_equal false, PackageRegistryHelper.allow_access_to_actor?(namespace, actor)
    end
    test "Owners is a spammy user, and should have access to its own content" do
      skip if !GitHub.spamminess_check_enabled?
      namespace = create(:user, spammy: true)
      assert_equal true, PackageRegistryHelper.allow_access_to_actor?(namespace, namespace)
    end
    test "Owners is a spammy org, admin should have access to its own content" do
      skip if !GitHub.spamminess_check_enabled?
      @org = create(:organization, spammy: true)
      @user = create(:user)
      @org.add_admin @user
      assert_equal true, PackageRegistryHelper.allow_access_to_actor?(@org, @user)
    end
    test "Owners is a spammy org, member should not have access to its own content" do
      skip if !GitHub.spamminess_check_enabled?
      @org = create(:organization, spammy: true)
      @user1 = create(:user)
      @org.add_member @user1
      assert_equal false, PackageRegistryHelper.allow_access_to_actor?(@org, @user1)
    end

  end

  context ".formatted_package_name" do
    test "strips out repository from package name" do
      assert_equal "package", PackageRegistryHelper.formatted_package_name("test_repo/package", "test_repo")
    end
    test "does strips out anything if not needed" do
      assert_equal "package", PackageRegistryHelper.formatted_package_name("package", "package")
    end
    test "leaves name alone if no repo" do
      assert_equal "test_repo/package", PackageRegistryHelper.formatted_package_name("test_repo/package", nil)
    end
  end
end
