# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::TokenScanningPushProtectionTest < GitHub::IntegrationTestCase
  include SecretScanning::Features::FeatureFlagHelper
  include HydroTestHelpers
  include TurboghasHelpers

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
    biz = create(:global_business)
    @user = create(:verified_user)
    @free_user = create(:verified_user)
    @org = create(:organization, business: biz, admin: @user)
    # There is a setting that will cause token scanning to be enabled when advanced security is enabled,
    # so we should probably explicitly set that to false to be safe.
    SecretScanning::Features::Org::TokenScanning.new(@org).disable_secret_scanning_for_new_repos(actor: @user)

    @repo = create(:private_repository, owner: @org)
    @free_public_repo = create(:repository, owner: @free_user)
  end

  setup do
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

    @token_scanning_service = SecurityProduct::TokenScanning.new(@repo)
    @push_protection_service = SecurityProduct::TokenScanningPushProtection.new(@repo)
    @service_manager = SecurityProduct::ServiceManager.new(@repo)
    @advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

    @free_token_scanning_service = SecurityProduct::TokenScanning.new(@free_public_repo)
    @free_push_protection_service = SecurityProduct::TokenScanningPushProtection.new(@free_public_repo)
    @free_service_manager = SecurityProduct::ServiceManager.new(@free_public_repo)
    @free_advanced_security_service = SecurityProduct::AdvancedSecurity.new(@free_public_repo)

    SecretScanning::Features::Repo::PushProtection.any_instance.stubs(:feature_available?).returns(true)
    self.enable_token_scanning
  end

  test "by default it is disabled" do
    refute @push_protection_service.enabled?
  end

  test "if token scanning is enabled, then we can enable token scanning push protection", skip_enterprise: true do
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_push_protection])
    refute err
    assert @push_protection_service.enabled?
  end

  test "disabling token scanning will disable token scanning push protection" do
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_push_protection])
    refute err
    assert @push_protection_service.enabled?

    _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning])
    refute err
    refute @token_scanning_service.enabled?

    refute @push_protection_service.enabled?
  end

  test "disable push protection" do
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_push_protection])
    refute err
    assert @push_protection_service.enabled?

    _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning_push_protection])
    refute err
    refute @push_protection_service.enabled?
  end

  test "toggle push protection on free public repo" do
    SecurityProduct::TokenScanning.any_instance.stubs(:enabled?).returns(true)
    _, err = @free_service_manager.toggle_services(@free_user, services_to_enable: [:token_scanning_push_protection])
    refute err
    assert @free_push_protection_service.enabled?

    _, err = @free_service_manager.toggle_services(@free_user, services_to_disable: [:token_scanning_push_protection])
    refute err
    refute @free_push_protection_service.enabled?
  end

  context "#can_enable?" do
    test "returns false when repo is archived or soft deleted" do
      repo = create(:private_repository, owner: @org)
      repo.set_archived

      push_protection_service = SecurityProduct::TokenScanningPushProtection.new(repo)
      can_enable, error = push_protection_service.can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :feature_not_available_on_archived_or_deleted_repos

      another_repo = create(:repository, :soft_deleted, owner: @org)

      push_protection_service = SecurityProduct::TokenScanningPushProtection.new(another_repo)
      can_enable, error = push_protection_service.can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :feature_not_available_on_archived_or_deleted_repos
    end

    test "returns false when secret scanning isn't enabled" do
      SecurityProduct::TokenScanning.any_instance.stubs(:enabled?).returns(false)

      can_enable, error = @push_protection_service.can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :token_scanning_disabled
    end

    test "returns false when blocked by policy" do
      # Calling `feature_enabled?` caches the value on the instance.
      # In the test setup for this file, `self.enable_token_scanning` is called, which ultimately calls `feature_enabled?`
      # and sets the cache for our feature flag on the business to whatever the global value is for the flag (false by default, true in all features CI runs).
      # Calling `enable_feature` here will not clear the cached value on the object,
      # so we need to stub `feature_enabled?` instead to override the cache and "enable" the flag.
      SecurityProduct::Permissions::RepoAuthz.any_instance.stubs(:manage_repo_secret_scanning_settings_blocked_by_policy?).returns(true)

      can_enable, error = @push_protection_service.can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :token_scanning_restricted_by_enablement_policy
    end

    test "returns true if push protections can be enabled" do
      can_enable, error = @push_protection_service.can_enable?(actor: @user, options: {})

      assert can_enable
      assert_nil error
    end

    test "returns true if push protections can be enabled on free public repo" do
      SecurityProduct::TokenScanning.any_instance.stubs(:enabled?).returns(true)
      can_enable, error = @free_push_protection_service.can_enable?(actor: @free_user, options: {})

      assert can_enable
      assert_nil error
    end
  end

  context "#can_disable?" do
    test "returns false when blocked by policy" do
      # Calling `feature_enabled?` caches the value on the instance.
      # In the test setup for this file, `self.enable_token_scanning` is called, which ultimately calls `feature_enabled?`
      # and sets the cache for our feature flag on the business to whatever the global value is for the flag (false by default, true in all features CI runs).
      # Calling `enable_feature` here will not clear the cached value on the object,
      # so we need to stub `feature_enabled?` instead to override the cache and "disable" the flag.
      SecurityProduct::Permissions::RepoAuthz.any_instance.stubs(:manage_repo_secret_scanning_settings_blocked_by_policy?).returns(true)

      can_disable, error = @push_protection_service.can_disable?(actor: @user, options: {})

      refute can_disable
      assert_equal error, :token_scanning_restricted_by_enablement_policy
    end

    test "returns true if push protections can be disabled" do
      can_disable, error = @push_protection_service.can_disable?(actor: @user, options: {})

      assert can_disable
      assert_nil error
    end

    test "returns true if push protections can be disabled on free public repo" do
      SecurityProduct::TokenScanning.any_instance.stubs(:enabled?).returns(true)
      can_disable, error = @free_push_protection_service.can_disable?(actor: @free_user, options: {})

      assert can_disable
      assert_nil error
    end
  end

  context "SecretScanningPushProtectionFeatureToggled hydro events" do
    test "we emit an enablement change hydro event when secret scanning push protection is enabled" do
      _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_push_protection])

      assert @push_protection_service.enabled?
      assert_hydro_published({ repository_id: @repo.id, feature_enabled: true }, schema: "github.secret_scanning.v1.SecretScanningPushProtectionFeatureToggled")
    end

    test "we emit an enablement change hydro event when secret scanning push protection is disabled" do
      _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning_push_protection])

      refute @push_protection_service.enabled?
      assert_hydro_published({ repository_id: @repo.id, feature_enabled: false }, schema: "github.secret_scanning.v1.SecretScanningPushProtectionFeatureToggled")
    end
  end

  private

  def enable_token_scanning
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:advanced_security, :token_scanning])
    refute err
    assert @token_scanning_service.enabled?
  end
end
