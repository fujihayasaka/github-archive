# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::TokenScanningDelegatedClosuresTest < GitHub::IntegrationTestCase
  include SecretScanning::Features::FeatureFlagHelper
  include HydroTestHelpers
  include TurboghasHelpers

  fixtures do
    biz = create(:global_business)
    @user = create(:verified_user)
    @org = create(:organization, business: biz, admin: @user)
    # There is a setting that will cause token scanning to be enabled when advanced security is enabled,
    # so we should probably explicitly set that to false to be safe.
    SecretScanning::Features::Org::TokenScanning.new(@org).disable_secret_scanning_for_new_repos(actor: @user)

    @repo = create(:private_repository, owner: @org)
  end

  setup do
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

    @token_scanning_service = SecurityProduct::TokenScanning.new(@repo)
    @delegated_closures_service = SecurityProduct::TokenScanningDelegatedClosures.new(@repo)
    @service_manager = SecurityProduct::ServiceManager.new(@repo)
    @advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

    SecretScanning::Features::Repo::DelegatedClosures.any_instance.stubs(:feature_available?).returns(true)
    self.enable_token_scanning
  end

  test "disabled by default" do
    refute @delegated_closures_service.enabled?
  end

  test "if token scanning is enabled, then we can enable delegated closures" do
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_delegated_closures])
    refute err
    assert @delegated_closures_service.enabled?
  end

  test "disabling token scanning disables delegated closures" do
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_delegated_closures])
    refute err
    assert @delegated_closures_service.enabled?

    _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning])
    refute err
    refute @token_scanning_service.enabled?

    refute @delegated_closures_service.enabled?
  end

  test "disable delegated closures" do
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:token_scanning_delegated_closures])
    refute err
    assert @delegated_closures_service.enabled?

    _, err = @service_manager.toggle_services(@user, services_to_disable: [:token_scanning_delegated_closures])
    refute err
    refute @delegated_closures_service.enabled?
  end

  context "can_enable" do
    test "returns false when secret scanning isn't enabled" do
      SecurityProduct::TokenScanning.any_instance.stubs(:enabled?).returns(false)

      can_enable, error = @delegated_closures_service.can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :token_scanning_disabled
    end

    test "returns true if delegated closures can be enabled" do
      can_enable, error = @delegated_closures_service.can_enable?(actor: @user, options: {})

      assert can_enable
      assert_nil error
    end
  end

  context "can_disable" do
    test "returns true if delegated closures can be disabled" do
      can_disable, error = @delegated_closures_service.can_disable?(actor: @user, options: {})

      assert can_disable
      assert_nil error
    end
  end

  private

  def enable_token_scanning
    _, err = @service_manager.toggle_services(@user, services_to_enable: [:advanced_security, :token_scanning])
    refute err
    assert @token_scanning_service.enabled?
  end
end
