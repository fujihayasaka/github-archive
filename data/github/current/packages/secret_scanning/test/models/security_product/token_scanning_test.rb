# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::TokenScanningTest < GitHub::IntegrationTestCase
  include HydroTestHelpers
  include SecretScanning::Features::FeatureFlagHelper
  include TurboghasHelpers

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
    @business = create(:global_business)
    @user = create(:verified_user)
    @org = create(:organization, admin: @user, business: @business)
    # There is a setting that will cause token scanning to be enabled when advanced security is enabled,
    # so we should probably explicitly set that to false to be safe.
    SecretScanning::Features::Org::TokenScanning.new(@org).disable_secret_scanning_for_new_repos(actor: @user)
    @repo = create(:private_repository, owner: @org)
    @public_repo = create(:public_repository, owner: @org)
    @public_non_org_repo = create(:public_repository)
    @services = SecurityProduct::ServiceManager.all_services
  end

  setup do
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)

    GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
  end

  test "by default it is disabled for private repos" do
    refute SecurityProduct::TokenScanning.new(@repo).enabled?
  end

  test "by default it is disabled for public org repos" do
    refute SecurityProduct::TokenScanning.new(@public_repo).enabled?
  end

  test "by default it is disabled for public non-org repos" do
    refute SecurityProduct::TokenScanning.new(@public_non_org_repo).enabled?
  end

  test "if we enable advanced security, then we can enable token scanning", skip_enterprise: true do
    service_manager = SecurityProduct::ServiceManager.new(@repo)
    token_scanning_service = SecurityProduct::TokenScanning.new(@repo)
    advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

    _, err = service_manager.toggle_services(@user, services_to_enable: [:advanced_security])
    refute err
    assert advanced_security_service.enabled?

    # does not automatically enable token scanning
    refute token_scanning_service.enabled?

    _, err = service_manager.toggle_services(@user, services_to_enable: [[:token_scanning]])
    refute err
    assert token_scanning_service.enabled?
  end

  test "we can enable token scanning on a public repo when the feature is available", skip_enterprise: true do
    service_manager = SecurityProduct::ServiceManager.new(@public_repo)
    token_scanning_service = SecurityProduct::TokenScanning.new(@public_repo)

    # does not automatically enable token scanning
    refute token_scanning_service.enabled?

    _, err = service_manager.toggle_services(@user, services_to_enable: [[:token_scanning]])
    refute err
    assert token_scanning_service.enabled?
  end

  test "we emit a backfill request when enabling token scanning and skip_backfill_request is false" do
    SecretScanning::Features::AdvancedSecurityHelper.stubs(:advanced_security_configurable?).returns(true)
    Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)

    service_manager = SecurityProduct::ServiceManager.new(@public_repo)
    token_scanning_service = SecurityProduct::TokenScanning.new(@public_repo)

    # does not automatically enable token scanning
    refute token_scanning_service.enabled?

    _, err = service_manager.toggle_services(@user, services_to_enable: [[:token_scanning, { skip_backfill_request: false }]])
    refute err
    assert token_scanning_service.enabled?

    assert_hydro_messages(count: 1, schema: "token_scanning_service.v0.BackfillRequest")
  end

  test "we emit a backfill request when enabling token scanning and skip_backfill_request is not set" do
    SecretScanning::Features::AdvancedSecurityHelper.stubs(:advanced_security_configurable?).returns(true)
    Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)

    service_manager = SecurityProduct::ServiceManager.new(@public_repo)
    token_scanning_service = SecurityProduct::TokenScanning.new(@public_repo)

    # does not automatically enable token scanning
    refute token_scanning_service.enabled?

    _, err = service_manager.toggle_services(@user, services_to_enable: [[:token_scanning]])
    refute err
    assert token_scanning_service.enabled?

    assert_hydro_messages(count: 1, schema: "token_scanning_service.v0.BackfillRequest")
  end

  test "we skip emitting a backfill request when enabling token scanning and skip_backfill_request is true" do
    SecretScanning::Features::AdvancedSecurityHelper.stubs(:advanced_security_configurable?).returns(true)
    Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)

    service_manager = SecurityProduct::ServiceManager.new(@public_repo)
    token_scanning_service = SecurityProduct::TokenScanning.new(@public_repo)

    # does not automatically enable token scanning
    refute token_scanning_service.enabled?

    _, err = service_manager.toggle_services(@user, services_to_enable: [[:token_scanning, { skip_backfill_request: true }]])
    refute err
    assert token_scanning_service.enabled?

    refute_hydro_messages(schema: "token_scanning_service.v0.BackfillRequest")
  end

  test "we emit an enablement change hydro event when secret scanning is enabled" do
    SecretScanning::Features::AdvancedSecurityHelper.stubs(:advanced_security_configurable?).returns(true)
    Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)

    service_manager = SecurityProduct::ServiceManager.new(@public_repo)
    token_scanning_service = SecurityProduct::TokenScanning.new(@public_repo)

    refute token_scanning_service.enabled?

    _, err = service_manager.toggle_services(@user, services_to_enable: [[:token_scanning, { force?: true }]])
    refute err
    assert token_scanning_service.enabled?

    assert_hydro_messages(count: 1, schema: "token_scanning_service.v0.EnablementChange")
  end

  test "we emit an enablement change hydro event when secret scanning is disabled" do
    SecretScanning::Features::AdvancedSecurityHelper.stubs(:advanced_security_configurable?).returns(true)
    Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)

    service_manager = SecurityProduct::ServiceManager.new(@public_repo)
    token_scanning_service = SecurityProduct::TokenScanning.new(@public_repo)

    _, err = service_manager.toggle_services(@user, services_to_disable: [[:token_scanning, { force?: true }]])
    refute err
    refute token_scanning_service.enabled?

    assert_hydro_messages(count: 1, schema: "token_scanning_service.v0.EnablementChange")
  end

  test "we emit an enablement change hydro event when lower confidence patterns is enabled" do
    SecretScanning::Features::AdvancedSecurityHelper.stubs(:advanced_security_configurable?).returns(true)
    Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)

    service_manager = SecurityProduct::ServiceManager.new(@public_repo)
    token_scanning = SecretScanning::Features::Repo::TokenScanning.new(@public_repo)
    token_scanning.enable(actor: @user)
    assert token_scanning.enabled?
    lcp = SecretScanning::Features::Repo::LowerConfidencePatterns.new(@public_repo)
    refute lcp.enabled?

    _, err = service_manager.toggle_services(@user, services_to_enable: [[:token_scanning_lower_confidence_patterns, { force?: true }]])
    refute err

    assert_hydro_messages(count: 1, schema: "token_scanning_service.v0.EnablementChange")
    assert_hydro_published_partial({
        repository_id: @public_repo.id,
        lower_confidence_patterns: true,
      }, schema: "token_scanning_service.v0.EnablementChange")

    assert lcp.enabled?
  end

  test "we emit an enablement change hydro event when lower confidence patterns is disabled" do
    SecretScanning::Features::AdvancedSecurityHelper.stubs(:advanced_security_configurable?).returns(true)
    Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)

    service_manager = SecurityProduct::ServiceManager.new(@public_repo)
    token_scanning = SecretScanning::Features::Repo::TokenScanning.new(@public_repo)
    token_scanning.enable(actor: @user)
    assert token_scanning.enabled?
    lcp = SecretScanning::Features::Repo::LowerConfidencePatterns.new(@public_repo)
    lcp.enable(actor: @user)
    assert lcp.enabled?

    _, err = service_manager.toggle_services(@user, services_to_disable: [[:token_scanning_lower_confidence_patterns, { force?: true }]])
    refute err

    assert_hydro_messages(count: 1, schema: "token_scanning_service.v0.EnablementChange")
    assert_hydro_published_partial({
        repository_id: @public_repo.id,
        lower_confidence_patterns: false,
      }, schema: "token_scanning_service.v0.EnablementChange")

    refute lcp.enabled?
  end

  test "if we try to enable token scanning, but it is not available in our environment, we will get an error" do
    GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

    service_manager = SecurityProduct::ServiceManager.new(@repo)
    advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

    _, err = service_manager.toggle_services(@user, services_to_enable: [:advanced_security])
    refute err
    assert advanced_security_service.enabled?

    res, err = service_manager.toggle_services(@user, services_to_enable: [[:token_scanning]])

    assert res.empty?
    assert_equal err, :token_scanning_unavailable
  end

  context "when repo is user owned" do
    test "if push protection is set to auto-enable at the business level, enabling secret scanning also enables push protection" do
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
      if GitHub.enterprise?
        business = @business
        user = @user
      else
        user = create(:emu)
        business = user.enterprise_managed_business
      end
      business.mark_advanced_security_as_purchased_for_entity(actor: user)

      # Auto-enable secret scanning and push protection
      # Unlike orgs, auto-enablement for user-owned repos can also be
      # set as a config value on the owning business, so we have to check
      # both features.
      SecretScanning::Features::Business::TokenScanning.new(business).enable_secret_scanning_for_new_repos(actor: user)
      SecretScanning::Features::Business::PushProtection.new(business).enable_for_new_repos(actor: user)

      # Create repo and enable ghas + secret-scanning
      repo = create(:private_repository, owner: user, force_user_owned: true)
      service_manager = SecurityProduct::ServiceManager.new(repo)
      _, err = service_manager.toggle_services(user, services_to_enable: [:advanced_security])
      refute err

      assert SecurityProduct::AdvancedSecurity.new(repo).enabled?
      assert SecurityProduct::TokenScanning.new(repo).enabled?
      assert SecurityProduct::TokenScanningPushProtection.new(repo).enabled?
    end

    test "if push protection is set to auto-enable at the user level, enabling secret scanning also enables push protection" do
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
      if GitHub.enterprise?
        business = @business
        user = @user
      else
        user = create(:emu)
        business = user.enterprise_managed_business
      end
      business.mark_advanced_security_as_purchased_for_entity(actor: user)

      # Auto-enable secret scanning and push protection
      SecretScanning::Features::User::TokenScanning.new(user).enable_secret_scanning_for_new_repos(actor: user)
      SecretScanning::Features::User::PushProtection.new(user).enable_for_new_repos(actor: user)

      # Create repo and enable ghas + secret-scanning
      repo = create(:private_repository, owner: user, force_user_owned: true)
      service_manager = SecurityProduct::ServiceManager.new(repo)
      _, err = service_manager.toggle_services(user, services_to_enable: [:advanced_security])
      refute err

      assert SecurityProduct::AdvancedSecurity.new(repo).enabled?
      assert SecurityProduct::TokenScanning.new(repo).enabled?
      assert SecurityProduct::TokenScanningPushProtection.new(repo).enabled?
    end
  end

  test "token scanning not staff disabled by default" do
    SecretScanning::Features::Org::PushProtection.any_instance.stubs(:enabled_for_new_repos?).returns(true)

    service_manager = SecurityProduct::ServiceManager.new(@repo)
    token_scanning_service = SecurityProduct::TokenScanning.new(@repo)
    push_protection_service = SecurityProduct::TokenScanningPushProtection.new(@repo)

    refute token_scanning_service.staff_disabled?
  end

  test "if token scanning is staff disabled on a public non-org repo, then token scanning should be disabled" do
    service_manager = SecurityProduct::ServiceManager.new(@public_non_org_repo)
    token_scanning_service = SecurityProduct::TokenScanning.new(@public_non_org_repo)

    _, err = service_manager.toggle_services(@user, services_to_disable: [[:token_scanning, { force?: true, use_staff_key: true }]])
    refute err
    assert token_scanning_service.manually_disabled?
  end

  test "if token scanning is network staff disabled, then token scanning should be staff disabled" do
    service_manager = SecurityProduct::ServiceManager.new(@public_non_org_repo)
    token_scanning_service = SecurityProduct::TokenScanning.new(@public_non_org_repo)

    _, err = service_manager.toggle_services(@user, services_to_disable: [[:token_scanning, { force?: true, use_staff_key: true, network: true }]])
    refute err
    assert token_scanning_service.manually_disabled?
  end

  test "if token scanning is already network staff disabled, then trying to staff disable should still work" do
    service_manager = SecurityProduct::ServiceManager.new(@public_non_org_repo)
    token_scanning_service = SecurityProduct::TokenScanning.new(@public_non_org_repo)

    _, err1 = service_manager.toggle_services(@user, services_to_disable: [[:token_scanning, { force?: true, use_staff_key: true }]])
    refute err1

    _, err2 = service_manager.toggle_services(@user, services_to_disable: [[:token_scanning, { force?: true, use_staff_key: true }]])
    refute err2
  end

  context "#can_enable?" do
    test "returns false when advanced security is disabled" do
      @repo.disable_advanced_security!(actor: @user)
      refute @repo.advanced_security_enabled?

      ts = SecurityProduct::TokenScanning.new(@repo)
      can_enable, error = ts.can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :advanced_security_disabled
    end

    test "returns false when secret scanning is not available for the repo" do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
      @repo.enable_advanced_security!(actor: @user)
      assert @repo.advanced_security_enabled?

      ts = SecurityProduct::TokenScanning.new(@repo)
      can_enable, error = ts.can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :token_scanning_unavailable
    end

    test "returns a different reason for why a free public repo could not enable secret scanning", skip_enterprise: true do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
      ts = SecurityProduct::TokenScanning.new(@public_non_org_repo)

      _, error = ts.can_enable?(actor: @user, options: {})
      assert_equal error, :token_scanning_always_enabled_on_public_repo
    end

    test "returns false when blocked by policy" do
      SecurityProduct::Permissions::RepoAuthz.any_instance.stubs(:manage_repo_secret_scanning_settings_blocked_by_policy?).returns(true)
      @repo.enable_advanced_security!(actor: @user)
      assert @repo.advanced_security_enabled?

      ts = SecurityProduct::TokenScanning.new(@repo)

      can_enable, error = ts.can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :token_scanning_restricted_by_enablement_policy
    end

    test "happy path when advanced security is configurable" do
      @repo.enable_advanced_security!(actor: @user)
      assert @repo.advanced_security_enabled?

      ts = SecurityProduct::TokenScanning.new(@repo)
      can_enable, error = ts.can_enable?(actor: @user, options: {})

      assert can_enable
      assert_nil error
    end

    test "happy path when advanced security is not configurable" do
      SecretScanning::Features::AdvancedSecurityHelper.stubs(:advanced_security_configurable?).returns(false)

      ts = SecurityProduct::TokenScanning.new(@repo)
      can_enable, error = ts.can_enable?(actor: @user, options: {})

      assert can_enable
      assert_nil error
    end
  end

  context "#can_disable?" do
    test "returns false when secret scanning is not available for the repo" do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(false)
      ts = SecurityProduct::TokenScanning.new(@repo)

      can_disable, error = ts.can_disable?(actor: @user, options: {})

      refute can_disable
      assert_equal error, :token_scanning_unavailable
    end

    test "returns false when blocked by policy" do
      SecurityProduct::Permissions::RepoAuthz.any_instance.stubs(:manage_repo_secret_scanning_settings_blocked_by_policy?).returns(true)
      ts = SecurityProduct::TokenScanning.new(@repo)

      can_disable, error = ts.can_disable?(actor: @user, options: {})

      refute can_disable
      assert_equal error, :token_scanning_restricted_by_enablement_policy
    end

    test "returns true if secret scanning can be disabled" do
      ts = SecurityProduct::TokenScanning.new(@repo)

      can_disable, error = ts.can_disable?(actor: @user, options: {})

      assert can_disable
      assert_nil error
    end
  end

  context "SecretScanningFeatureToggled hydro events" do
    test "emit hydro event when secret scanning is enabled" do
      SecretScanning::Features::AdvancedSecurityHelper.stubs(:advanced_security_configurable?).returns(true)
      Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)

      service_manager = SecurityProduct::ServiceManager.new(@repo)
      token_scanning_service = SecurityProduct::TokenScanning.new(@repo)

      refute token_scanning_service.enabled?

      _, err = service_manager.toggle_services(@user, services_to_enable: [[:token_scanning, { force?: true }]])
      refute err
      assert token_scanning_service.enabled?

      assert_hydro_published({ repository_id: @repo.id, feature_enabled: true }, schema: "github.secret_scanning.v1.SecretScanningFeatureToggled")
    end

    test "emit hydro event when secret scanning is disabled" do
      SecretScanning::Features::AdvancedSecurityHelper.stubs(:advanced_security_configurable?).returns(true)
      Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)

      service_manager = SecurityProduct::ServiceManager.new(@repo)
      token_scanning_service = SecurityProduct::TokenScanning.new(@repo)

      _, err = service_manager.toggle_services(@user, services_to_disable: [[:token_scanning, { force?: true }]])
      refute err
      refute token_scanning_service.enabled?

      assert_hydro_published({ repository_id: @repo.id, feature_enabled: false }, schema: "github.secret_scanning.v1.SecretScanningFeatureToggled")
    end

    test "only emit hydro event when the renotify_only option is set to true" do
      SecretScanning::Features::AdvancedSecurityHelper.stubs(:advanced_security_configurable?).returns(true)
      Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)

      service_manager = SecurityProduct::ServiceManager.new(@repo)
      token_scanning = SecretScanning::Features::Repo::TokenScanning.new(@repo)
      token_scanning.enable(actor: @user)
      assert token_scanning.enabled?

      _, err = service_manager.toggle_services(@user, services_to_enable: [[:token_scanning, { renotify_only: true }]])
      refute err

      refute_hydro_messages(schema: "token_scanning_service.v0.EnablementChange")
      assert_hydro_published({ repository_id: @repo.id, feature_enabled: true }, schema: "github.secret_scanning.v1.SecretScanningFeatureToggled")
    end
  end
end
