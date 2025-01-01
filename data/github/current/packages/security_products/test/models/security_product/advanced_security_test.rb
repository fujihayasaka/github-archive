# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::AdvancedSecurityTest < GitHub::IntegrationTestCase
  include HydroTestHelpers
  include TurboghasHelpers

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
    @business = create(:global_business)

    @user = create(:verified_user)
    @org = create(:organization, business: @business, admin: @user)

    @repo = create(:private_repository, owner: @org)
    @services = SecurityProduct::ServiceManager.all_services
  end

  setup do
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
  end

  test "by default it is disabled for private repos" do
    refute SecurityProduct::AdvancedSecurity.new(@repo).enabled?
  end

  test "if we disable advanced security, this will turn off token scanning" do
    service_manager = SecurityProduct::ServiceManager.new(@repo)
    token_scanning_service = SecurityProduct::TokenScanning.new(@repo)
    advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

    _, err = service_manager.toggle_services(@user, services_to_enable: [:advanced_security])
    refute err
    assert SecurityProduct::AdvancedSecurity.new(@repo).enabled?

    _, err = service_manager.toggle_services(@user, services_to_enable: [[:token_scanning]])
    refute err
    assert token_scanning_service.enabled?

    # --

    _, err = service_manager.toggle_services(@user, services_to_disable: [:advanced_security])
    refute err

    refute token_scanning_service.enabled?
  end

  test "when enabled, we index the repository via Aleph if vulnerability alerting is enabled", skip_enterprise: true do
    Repository.any_instance.stubs(:default_oid).returns("abcdef")
    @repo.enable_vulnerability_alerts(actor: @user)
    GitHub::Aleph.expects(:request_index).at_least_once.with(repo: @repo, commit_oid: "abcdef", reason: GitHub::Aleph.vea_repo_with_alert_reason)

    service_manager = SecurityProduct::ServiceManager.new(@repo)
    advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

    _, err = service_manager.toggle_services(@user, services_to_enable: [:advanced_security])
    refute err
    assert advanced_security_service.enabled?
  end

  test "skip VEA scan via Aleph if repo has no valid commits", skip_enterprise: true do
    repo = create(:repository, owner: @org)
    repo.enable_vulnerability_alerts(actor: @user)

    GitHub::Aleph.expects(:request_index).never

    service_manager = SecurityProduct::ServiceManager.new(@repo)
    advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

    _, err = service_manager.toggle_services(@user, services_to_enable: [:advanced_security])
    refute err
    assert advanced_security_service.enabled?
  end

  test "when enabled, we do not index the repository via Aleph if vulnerability alerting is disabled", skip_enterprise: true do
    @repo.disable_vulnerability_alerts(actor: @user)
    GitHub::Aleph.expects(:index_repository).with(repo: @repo, ref: "").never

    service_manager = SecurityProduct::ServiceManager.new(@repo)
    advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

    _, err = service_manager.toggle_services(@user, services_to_enable: [:advanced_security])
    refute err
    assert advanced_security_service.enabled?
  end

  test "when enabled, we should enqueue a RefreshRuleStateOnGhasEnablementChangeJob if repo has custom rules enabled", skip_enterprise: true do
    @repo.enable_vulnerability_alerts(actor: @user)
    service_manager = SecurityProduct::ServiceManager.new(@repo)
    advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

    assert_enqueued_with(job: RefreshRuleStateOnGhasEnablementChangeJob, args: [{ repository: @repo, ghas_enabled: true }]) do
      _, err = service_manager.toggle_services(@user, services_to_enable: [:advanced_security])
      refute err
      assert advanced_security_service.enabled?
    end
  end

  test "when disabled, we should enqueue a RefreshRuleStateOnGhasEnablementChangeJob if repo has custom rules enabled", skip_enterprise: true do
    @repo.enable_vulnerability_alerts(actor: @user)

    service_manager = SecurityProduct::ServiceManager.new(@repo)
    advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

    _, err = service_manager.toggle_services(@user, services_to_enable: [:advanced_security])
    refute err
    assert SecurityProduct::AdvancedSecurity.new(@repo).enabled?

    assert_enqueued_with(job: RefreshRuleStateOnGhasEnablementChangeJob, args: [{ repository: @repo, ghas_enabled: false }]) do
      _, err = service_manager.toggle_services(@user, services_to_disable: [:advanced_security])
      refute err
      refute advanced_security_service.enabled?
    end
  end

  context "when repo is user-owned" do
    test "if we disable advanced security, this will turn off token scanning" do
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
      if GitHub.enterprise?
        business = @business
        user = @user
      else
        user = create(:emu)
        business = user.enterprise_managed_business
      end
      business.mark_advanced_security_as_purchased_for_entity(actor: user)

      feature = SecretScanning::Features::User::TokenScanning.new(user)
      feature.enable_secret_scanning_for_new_repos(actor: user)

      # Create repo and enable ghas + secret-scanning
      repo = create(:private_repository, owner: user, force_user_owned: true)
      service_manager = SecurityProduct::ServiceManager.new(repo)
      _, err = service_manager.toggle_services(user, services_to_enable: [:advanced_security])
      refute err

      assert SecurityProduct::AdvancedSecurity.new(repo).enabled?
      assert SecurityProduct::TokenScanning.new(repo).enabled?

      # Now disable it, and verify secret-scanning also got disabled
      service_manager = SecurityProduct::ServiceManager.new(repo)
      _, err = service_manager.toggle_services(user, services_to_disable: [:advanced_security])
      refute err

      refute SecurityProduct::AdvancedSecurity.new(repo).enabled?
      refute SecurityProduct::TokenScanning.new(repo).enabled?
    end



    test "if secret scanning opt-in is enabled for the business, enabling advanced security also enables secret scanning" do
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
      if GitHub.enterprise?
        business = @business
        user = @user
      else
        user = create(:emu)
        business = user.enterprise_managed_business
      end
      business.mark_advanced_security_as_purchased_for_entity(actor: user)

      # Unlike orgs, auto-enablement for user-owned repos can also be
      # set as a config value on the owning business, so we have to check
      # both features.
      feature = SecretScanning::Features::Business::TokenScanning.new(business)
      feature.enable_secret_scanning_for_new_repos(actor: user)
      assert feature.secret_scanning_enabled_for_new_repos?

      repo = create(:private_repository, owner: user, force_user_owned: true)
      service_manager = SecurityProduct::ServiceManager.new(repo)
      _, err = service_manager.toggle_services(user, services_to_enable: [:advanced_security])
      refute err

      token_scanning_service = SecurityProduct::TokenScanning.new(repo)
      advanced_security_service = SecurityProduct::AdvancedSecurity.new(repo)

      assert advanced_security_service.enabled?
      assert token_scanning_service.enabled?
    end

    test "if secret scanning opt-in is enabled for the user, enabling advanced security also enables secret scanning" do
      GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
      if GitHub.enterprise?
        business = @business
        user = @user
      else
        user = create(:emu)
        business = user.enterprise_managed_business
      end
      business.mark_advanced_security_as_purchased_for_entity(actor: user)

      feature = SecretScanning::Features::User::TokenScanning.new(user)
      feature.enable_secret_scanning_for_new_repos(actor: user)
      assert feature.secret_scanning_enabled_for_new_repos?

      repo = create(:private_repository, owner: user, force_user_owned: true)
      service_manager = SecurityProduct::ServiceManager.new(repo)
      _, err = service_manager.toggle_services(user, services_to_enable: [:advanced_security])
      refute err

      token_scanning_service = SecurityProduct::TokenScanning.new(repo)
      advanced_security_service = SecurityProduct::AdvancedSecurity.new(repo)

      assert advanced_security_service.enabled?
      assert token_scanning_service.enabled?
    end
  end

  context "#can_enable?" do
    test "returns false in enterprise if the repository owner is a user and the feature flag is disabled" do
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false)

      user_owned_repo = create(:repository, :user_owned_public)
      can_enable, error = SecurityProduct::AdvancedSecurity.new(user_owned_repo).can_enable?(actor: user_owned_repo.owner, options: {})

      if GitHub.enterprise?
        refute can_enable
        assert_equal error, :advanced_security_requires_an_org
      else
        # We don't care whether `can_enable` is true/false in dotcom.
        # Just that if we can't enable, using the same repo setup, the reason isn't the same as enterprise.
        refute_equal error, :advanced_security_requires_an_org
      end
    end

    test "returns false in dotcom if the repository is public" do
      public_repo = create(:public_repository, owner: @org)
      can_enable, error = SecurityProduct::AdvancedSecurity.new(public_repo).can_enable?(actor: @user, options: {})

      if GitHub.dotcom_request?
        refute can_enable
        assert_equal error, :advanced_security_enabled_on_public_repo
      else
        # We don't care whether `can_enable` is true/false in enterprise.
        # Just that if we can't enable, using the same repo setup, the reason isn't the same as dotcom.
        refute_equal error, :advanced_security_enabled_on_public_repo
      end
    end

    test "returns false if advanced security hasn't been purchased" do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)

      can_enable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :advanced_security_not_purchased
    end

    test "returns false if policy restricts enabling advanced security for the org blocks the action" do
      Repository.any_instance.stubs(:policy_allows_advanced_security_enablement?).returns(false)

      can_enable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :advanced_security_restricted_by_policy
    end

    test "returns false if policy restricting repo admins from enabling advanced security blocks the action" do
      SecurityProduct::Permissions::RepoAuthz.any_instance.stubs(:manage_repo_advanced_security_enablement_blocked_by_policy?).returns(true)

      # NOTE: The user here is an org owner and normally wouldn't be blocked by this policy.
      # But because we stubbed the policy check above, it doesn't matter what role they have.
      can_enable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :advanced_security_restricted_by_enablement_policy
    end

    test "returns false if enabling advanced security would exceed GHAS seat allowance" do
      Repository.any_instance.stubs(:enforce_advanced_security_committers_limits?).returns(true)
      Repository.any_instance.stubs(:enabling_advanced_security_would_exceed_seat_allowance?).returns(true)

      can_enable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_enable?(actor: @user, options: {})

      refute can_enable
      assert_equal error, :advanced_security_would_exceed_limit
    end

    test "doesn't error because enabling advanced security would exceed GHAS seat allowance if the allowance isn't enforced" do
      Repository.any_instance.stubs(:enforce_advanced_security_committers_limits?).returns(false)
      Repository.any_instance.stubs(:enabling_advanced_security_would_exceed_seat_allowance?).returns(true)

      can_enable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_enable?(actor: @user, options: {})

      # We don't care whether `can_enable` is true/false in dotcom. Because that depends on the order of other checks in the method under test.
      # We just care that if we can't enable, using the same repo setup, the reason isn't because of seat allowances.
      refute_equal error, :advanced_security_would_exceed_limit
    end

    test "doesn't error because GHAS seat allowance is enforced if enabling advanced security wouldn't exceed the allowance" do
      Repository.any_instance.stubs(:enforce_advanced_security_committers_limits?).returns(true)
      Repository.any_instance.stubs(:enabling_advanced_security_would_exceed_seat_allowance?).returns(false)

      can_enable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_enable?(actor: @user, options: {})

      assert can_enable
      refute_equal error, :advanced_security_would_exceed_limit
    end

    test "returns true if advanced security can be enabled" do
      can_enable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_enable?(actor: @user, options: {})

      assert can_enable
      assert_nil error
    end

    test "returns false if GHAS is metered and connect is not supported", enterprise_only: true do
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub::Enterprise.license.stubs(:metered_advanced_security?).returns(true)
      GitHub::Enterprise.license.stubs(:github_connect_support?).returns(false)
      GitHub.enable_dotcom_user_license_usage_upload(User.ghost)

      can_enable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_enable?(actor: @user, options: {})

      refute can_enable
    end

    test "returns false if GHAS is metered and connect is supported but not enabled", enterprise_only: true do
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub::Enterprise.license.stubs(:metered_advanced_security?).returns(true)
      GitHub::Enterprise.license.stubs(:github_connect_support?).returns(true)
      DotcomConnection.any_instance.stubs(:is_connected?).returns(false)
      GitHub.enable_dotcom_user_license_usage_upload(User.ghost)
      can_enable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_enable?(actor: @user, options: {})

      refute can_enable
    end

    # this case is for completeness and should never happen in any real scenario
    test "returns false if GHAS is metered and connect is enabled but not supported", enterprise_only: true do
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub::Enterprise.license.stubs(:metered_advanced_security?).returns(true)
      GitHub::Enterprise.license.stubs(:github_connect_support?).returns(false)
      DotcomConnection.any_instance.stubs(:is_connected?).returns(true)
      GitHub.enable_dotcom_user_license_usage_upload(User.ghost)
      can_enable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_enable?(actor: @user, options: {})

      refute can_enable
    end

    test "returns false if GHAS is metered and license sync is not enabled", enterprise_only: true do
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub::Enterprise.license.stubs(:metered_advanced_security?).returns(true)
      GitHub::Enterprise.license.stubs(:github_connect_support?).returns(true)
      DotcomConnection.any_instance.stubs(:is_connected?).returns(true)
      GitHub.disable_dotcom_user_license_usage_upload(User.ghost)
      can_enable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_enable?(actor: @user, options: {})

      refute can_enable

      @repo.config.enable(SecurityProduct::AdvancedSecurity::USER_ENABLED_KEY, User.ghost)
      # advanced security remains enabled despite overage state
      assert SecurityProduct::AdvancedSecurity.new(@repo).enabled?
    end

    test "returns true if GHAS is metered and connect is supported and enabled", enterprise_only: true do
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub::Enterprise.license.stubs(:metered_advanced_security?).returns(true)
      GitHub::Enterprise.license.stubs(:github_connect_support?).returns(true)
      DotcomConnection.any_instance.stubs(:is_connected?).returns(true)
      GitHub.enable_dotcom_user_license_usage_upload(User.ghost)
      can_enable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_enable?(actor: @user, options: {})

      assert can_enable
      assert_nil error
    end
  end

  context "#can_disable?" do
    test "returns false for enterprise if the repository owner is a user and the feature flag is disabled" do
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false) if GitHub.enterprise?

      user_owned_repo = create(:repository, :user_owned_public)
      can_disable, error = SecurityProduct::AdvancedSecurity.new(user_owned_repo).can_disable?(actor: user_owned_repo.owner, options: {})

      if GitHub.enterprise?
        refute can_disable
        assert_equal error, :advanced_security_requires_an_org
      else
        # We don't care whether `can_disable` is true/false in dotcom.
        # We just care that if we can't disable, using the same repo setup, the reason isn't the same as enterprise.
        refute_equal error, :advanced_security_requires_an_org
      end
    end

    test "returns false in dotcom if the repository is public", skip_enterprise: true do
      public_repo = create(:public_repository, owner: @org)
      can_disable, error = SecurityProduct::AdvancedSecurity.new(public_repo).can_disable?(actor: @user, options: {})

      if GitHub.dotcom_request?
        refute can_disable
        assert_equal error, :advanced_security_enabled_on_public_repo
      else
        # We don't care whether `can_disable` is true/false in enterprise.
        # We just care that if we can't disable, using the same repo setup, the reason isn't the same as dotcom.
        refute_equal error, :advanced_security_enabled_on_public_repo
      end
    end

    test "returns false if advanced security hasn't been purchased" do
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)

      can_disable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_disable?(actor: @user, options: {})

      refute can_disable
      assert_equal error, :advanced_security_not_purchased
    end

    test "returns false if policy restricting repo admins from disabling advanced security blocks the action" do
      SecurityProduct::Permissions::RepoAuthz.any_instance.stubs(:manage_repo_advanced_security_enablement_blocked_by_policy?).returns(true)

      # NOTE: The user here is an org owner and normally wouldn't be blocked by this policy.
      # But because we stubbed the policy check above, it doesn't matter what role they have.
      can_disable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_disable?(actor: @user, options: {})

      refute can_disable
      assert_equal error, :advanced_security_restricted_by_enablement_policy
    end

    test "returns false if secret scanning is enabled and cannot be disabled by the actor" do
      SecurityProduct::TokenScanning.any_instance.stubs(:enabled?).returns(true)
      SecurityProduct::TokenScanning.any_instance.stubs(:can_disable?).returns(SecurityProduct::Result.new(false, :test_error))

      can_disable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_disable?(actor: @user, options: {})

      refute can_disable
      assert_equal error, :advanced_security_restricted_by_secret_scanning_enablement_policy
    end

    test "doesn't error because secret scanning cannot be disabled if secret scanning isn't already enabled" do
      SecurityProduct::TokenScanning.any_instance.stubs(:enabled?).returns(false)
      SecurityProduct::TokenScanning.any_instance.stubs(:can_disable?).returns(SecurityProduct::Result.new(false, :test_error))

      can_disable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_disable?(actor: @user, options: {})

      # We don't care whether `can_disable` is true/false in dotcom. Because that depends on the order of other checks in the method under test.
      # We just care that if we can't disable, using the same repo setup, the reason isn't because of secret scanning restrictions.
      refute_equal error, :advanced_security_restricted_by_secret_scanning_enablement_policy
    end

    test "doesn't error when secret scanning is enabled if secret scanning can be disabled by the actor" do
      SecurityProduct::TokenScanning.any_instance.stubs(:enabled?).returns(true)
      SecurityProduct::TokenScanning.any_instance.stubs(:can_disable?).returns(SecurityProduct::Result.new(true))

      can_disable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_disable?(actor: @user, options: {})

      # We don't care whether `can_disable` is true/false in dotcom. Because that depends on the order of other checks in the method under test.
      # We just care that if we can't disable, using the same repo setup, the reason isn't because of secret scanning restrictions.
      refute_equal error, :advanced_security_restricted_by_secret_scanning_enablement_policy
    end

    test "returns true if advanced security can be disabled" do
      can_disable, error = SecurityProduct::AdvancedSecurity.new(@repo).can_disable?(actor: @user, options: {})

      assert can_disable
      assert_nil error
    end
  end

  context "#AdvancedSecurityToggled hydro events" do
    test "don't emit an enablement change hydro event when not in scope of security overview analytics" do
      service_manager = SecurityProduct::ServiceManager.new(@repo)
      advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

      _, err = service_manager.toggle_services(@user, services_to_enable: [:advanced_security])

      refute_hydro_messages(schema: "ggithub.security_center.v0.AdvancedSecurityToggled")
    end

    test "emits an enabled hydro event when advanced security is enabled" do
      service_manager = SecurityProduct::ServiceManager.new(@repo)
      advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

      _, err = service_manager.toggle_services(@user, services_to_enable: [:advanced_security])

      assert_hydro_published({
        repository_id: @repo.id,
        feature_enabled: true,
        customer_id: @org.business.customer_id
      }, schema: "github.security_center.v0.AdvancedSecurityToggled")
    end

    test "emits a disabled hydro event when advanced security is disabled" do
      service_manager = SecurityProduct::ServiceManager.new(@repo)
      advanced_security_service = SecurityProduct::AdvancedSecurity.new(@repo)

      _, err = service_manager.toggle_services(@user, services_to_enable: [:advanced_security])
      _, err = service_manager.toggle_services(@user, services_to_disable: [:advanced_security])

      assert_hydro_published({
        repository_id: @repo.id,
        feature_enabled: false,
        customer_id: @org.business.customer_id
      }, schema: "github.security_center.v0.AdvancedSecurityToggled")
    end
  end
end
