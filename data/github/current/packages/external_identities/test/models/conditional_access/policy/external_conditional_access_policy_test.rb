# typed: true
# frozen_string_literal: true

require "test_helper"
require "digest/sha2"

class TestExternalConditionalAccessPolicy
  include ConditionalAccess::Policy::ExternalConditionalAccessPolicy

  attr_reader :actor, :business
  attr_accessor :actor_ip, :client_ip

  def initialize(actor: nil, business: nil)
    @actor = actor
    @business = business
    @actor_ip = "192.168.0.1"
    @client_ip = "192.168.0.1"
  end

  def location
    :test
  end

  def callback_name
    self.class.name
  end
end

class ExternalConditionalAccessPolicyTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @emu = create :emu, provider_type: :oidc
    @business = @emu.enterprise_managed_business
    @owner = @business.find_first_emu_owner
    @org = create(:organization, business: @business, admin: @owner)
    @org_repo = create(:repository, owner: @org)
    @user_repo = create(:repository, owner: @emu)
    @user_repo_two = create(:repository, owner: @emu)

    @ei = @emu.external_identities.first
    ExternalIdentityRefreshToken.create!(external_identity: @ei, encrypted_refresh_token: "foobar")

    @staff_owned_emu = create :emu, provider_type: :oidc
    @staff_owned_business = @staff_owned_emu.enterprise_managed_business
    @staff_owned_business.update(staff_owned: true)
    @staff_owned_ei = @staff_owned_emu.external_identities.first
    @staff_owned_user_repo = create(:repository, owner: @staff_owned_emu)
    @staff_owned_user_repo_two = create(:repository, owner: @staff_owned_emu)
  end

  setup do
    @target_provider = ConditionalAccess::TargetProvider.new(location: :test, callback_name: "Object")
    GitHub.flipper[:disable_oidc_cap_cache].disable
    @business.update_ip_allowlist_configuration(actor: @owner, config_value: "idp")
  end

  context "applicable" do
    test "no for resource without a TFCA" do
      policy = TestExternalConditionalAccessPolicy.new
      assert_equal :no, policy.external_conditional_access_policy_applicable(resource: :no_resource_for_conditional_access, target_provider: @target_provider)
      assert_equal :no, policy.external_conditional_access_policy_applicable(resource: :no_target_for_conditional_access, target_provider: @target_provider)
    end

    test "no for resource without a business" do
      org = create(:organization)
      policy = TestExternalConditionalAccessPolicy.new
      assert_equal :no, policy.external_conditional_access_policy_applicable(resource: org, target_provider: @target_provider)
    end

    test "no when resource's business doesn't have an OIDC provider" do
      biz_without_provider = create(:business, :enterprise_managed)
      owner = biz_without_provider.find_first_emu_owner
      org = create(:organization, business: biz_without_provider, admin: owner)
      repo = create(:repository, owner: org)

      policy = TestExternalConditionalAccessPolicy.new
      assert_equal :no, policy.external_conditional_access_policy_applicable(resource: repo, target_provider: @target_provider)
    end

    test "no if actor is nil" do
      policy = TestExternalConditionalAccessPolicy.new

      assert_equal :no, policy.external_conditional_access_policy_applicable(resource: @user_repo, target_provider: @target_provider)
      assert_equal :no, policy.external_conditional_access_policy_applicable(resource: @org_repo, target_provider: @target_provider)
    end

    test "no if actor is bot" do
      installation = make_integration_installation(target: @business, permissions: { "enterprise_administration" => :write })
      policy = TestExternalConditionalAccessPolicy.new(actor: installation)

      assert_equal :no, policy.external_conditional_access_policy_applicable(resource: @user_repo, target_provider: @target_provider)
      assert_equal :no, policy.external_conditional_access_policy_applicable(resource: @org_repo, target_provider: @target_provider)
    end

    test "no for first enterprise owner of EMU business" do
      policy = TestExternalConditionalAccessPolicy.new(actor: @owner)

      assert_equal :no, policy.external_conditional_access_policy_applicable(resource: @user_repo, target_provider: @target_provider)
      assert_equal :no, policy.external_conditional_access_policy_applicable(resource: @org_repo, target_provider: @target_provider)
    end

    test "yes for a resource with a OIDC configured business when logged in through an OAuth app and business.ip_allowlist_app_access_disabled?" do
      configure_user_as_oauth_app @emu, ["repo"]
      policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

      assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: @user_repo, target_provider: @target_provider)
      assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: @org_repo, target_provider: @target_provider)
    end

    test "yes for a resource with a OIDC configured business" do
      policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

      assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: @user_repo, target_provider: @target_provider)
      assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: @org_repo, target_provider: @target_provider)
    end

    context "exempt_internal_github_resource?" do
      test "no for GitHub internal IP" do
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
        @business.disable_skip_idp_ip_allowlist_app_access(actor: @owner)

        app = create_internal_app_with_capabilities(options: { owner: @business, visibility: "internal_visibility" })
        refute Apps::Internal.capable?(:ip_allowlist_exempt, app: app), "expected #{app} to not be IP allow list exempt"

        @emu.oauth_access = app.grant(@emu)
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)
        policy.actor_ip = "10.56.131.48" # 10.* are github internal IPs
        policy.client_ip = "10.56.131.48" # 10.* are github internal IPs

        exempt_log = {
          "Body" => "Resource exemption status from external conditional access policy applicability",
          "code.function" => "exempt_internal_github_resource?",
          "gh.app.class" => app.class,
          "gh.app.id" => app.id,
          "gh.external_identities.cap_exemption" => "exempted",
          "gh.external_identities.internal_app_exempted" => false,
          "gh.external_identities.internal_ip_exempted" => true,
          "gh.external_identities.client_ip" => "10.56.131.48",
        }

        assert_logged **exempt_log do
          assert_equal :no, policy.external_conditional_access_policy_applicable(resource: app, target_provider: @target_provider)
        end
      end

      test "no for internal app with IP exempt" do
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
        @business.disable_skip_idp_ip_allowlist_app_access(actor: @owner)

        app = create_internal_app_with_capabilities(capabilities: { ip_allowlist_exempt: true }, options: { owner: @business, visibility: "internal_visibility" })
        assert Apps::Internal.capable?(:ip_allowlist_exempt, app: app), "expected #{app} to be IP allow list exempt"

        @emu.oauth_access = app.grant(@emu)
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)

        exempt_log = {
          "Body" => "Resource exemption status from external conditional access policy applicability",
          "code.function" => "exempt_internal_github_resource?",
          "gh.app.class" => app.class,
          "gh.app.id" => app.id,
          "gh.external_identities.cap_exemption" => "exempted",
          "gh.external_identities.internal_app_exempted" => true,
          "gh.external_identities.internal_ip_exempted" => false,
          "gh.external_identities.client_ip" => policy.actor_ip,
        }

        assert_logged **exempt_log do
          assert_equal :no, policy.external_conditional_access_policy_applicable(resource: app, target_provider: @target_provider)
        end
      end

      test "yes for internal app without IP exempt" do
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
        @business.disable_skip_idp_ip_allowlist_app_access(actor: @owner)

        app = create_internal_app_with_capabilities(options: { owner: @business, visibility: "internal_visibility" })
        refute Apps::Internal.capable?(:ip_allowlist_exempt, app: app), "expected #{app} to not be IP allow list exempt"

        @emu.oauth_access = app.grant(@emu)
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)

        exempt_log = {
          "Body" => "Resource exemption status from external conditional access policy applicability",
          "code.function" => "exempt_internal_github_resource?",
          "gh.app.class" => app.class,
          "gh.app.id" => app.id,
          "gh.external_identities.cap_exemption" => "not exempted",
          "gh.external_identities.internal_app_exempted" => false,
          "gh.external_identities.internal_ip_exempted" => false,
          "gh.external_identities.client_ip" => policy.actor_ip,
        }

        assert_logged **exempt_log do
          assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: app, target_provider: @target_provider)
        end
      end

      test "yes for empty IP address with feature flag enabled" do
        GitHub.flipper[:rescue_exempt_check_cap].enable(@business)
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
        @business.disable_skip_idp_ip_allowlist_app_access(actor: @owner)

        app = create_internal_app_with_capabilities(options: { owner: @business, visibility: "internal_visibility" })
        refute Apps::Internal.capable?(:ip_allowlist_exempt, app: app), "expected #{app} to not be IP allow list exempt"

        @emu.oauth_access = app.grant(@emu)
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)
        policy.actor_ip = "" # 10.* are github internal IPs
        policy.client_ip = "" # 10.* are github internal IPs

        exempt_log = {
          "Body" => "Resource exemption status from external conditional access policy applicability",
          "code.function" => "exempt_internal_github_resource?",
          "gh.app.class" => app.class,
          "gh.app.id" => app.id,
          "gh.external_identities.cap_exemption" => "not exempted",
          "gh.external_identities.internal_app_exempted" => false,
          "gh.external_identities.internal_ip_exempted" => false,
          "gh.external_identities.client_ip" => policy.actor_ip,
        }

        assert_logged **exempt_log do
          assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: app, target_provider: @target_provider)
        end
      end

      test "throws an error for empty IP address with feature flag disabled" do
        GitHub.flipper[:rescue_exempt_check_cap].disable
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
        @business.disable_skip_idp_ip_allowlist_app_access(actor: @owner)

        app = create_internal_app_with_capabilities(options: { owner: @business, visibility: "internal_visibility" })
        refute Apps::Internal.capable?(:ip_allowlist_exempt, app: app), "expected #{app} to not be IP allow list exempt"

        @emu.oauth_access = app.grant(@emu)
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)
        policy.actor_ip = "" # 10.* are github internal IPs
        policy.client_ip = "" # 10.* are github internal IPs

        assert_raises IPAddr::InvalidAddressError do
          assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: app, target_provider: @target_provider)
        end
      end
    end

    context "skip_idp_ip_allowlist_app_access" do
      test "no for oauth app if skip_idp_ip_allowlist_app_access is enabled" do
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
        @business.enable_skip_idp_ip_allowlist_app_access(actor: @owner)

        configure_user_as_oauth_app @emu, ["repo"]
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_equal :no, policy.external_conditional_access_policy_applicable(resource: @user_repo, target_provider: @target_provider)
        assert_equal :no, policy.external_conditional_access_policy_applicable(resource: @org_repo, target_provider: @target_provider)
      end

      test "yes for oauth app if skip_idp_ip_allowlist_app_access is disabled" do
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)

        configure_user_as_oauth_app @emu, ["repo"]
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: @user_repo, target_provider: @target_provider)
        assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: @org_repo, target_provider: @target_provider)
      end

      test "yes for PATs if skip_idp_ip_allowlist_app_access is disabled" do
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)

        @emu.oauth_access = make_personal_access_token(@emu, "repo")
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: @user_repo, target_provider: @target_provider)
        assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: @org_repo, target_provider: @target_provider)
      end

      test "yes for PATs if skip_idp_ip_allowlist_app_access is enabled" do
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
        @business.enable_skip_idp_ip_allowlist_app_access(actor: @owner)

        @emu.oauth_access = make_personal_access_token(@emu, "repo")
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: @user_repo, target_provider: @target_provider)
        assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: @org_repo, target_provider: @target_provider)
      end
    end

    context "ip allow list configuration with idp settings enabled" do
      test "no if business is github_based_ip_allowlist_configuration?" do
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::GITHUB)
        assert_predicate @business, :github_based_ip_allowlist_configuration?
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_equal :no, policy.external_conditional_access_policy_applicable(resource: @user_repo, target_provider: @target_provider)
        assert_equal :no, policy.external_conditional_access_policy_applicable(resource: @org_repo, target_provider: @target_provider)
      end

      test "no if business disabled_ip_allowlist_configuration?" do
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::DISABLED)
        assert_predicate @business, :disabled_ip_allowlist_configuration?
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_equal :no, policy.external_conditional_access_policy_applicable(resource: @user_repo, target_provider: @target_provider)
        assert_equal :no, policy.external_conditional_access_policy_applicable(resource: @org_repo, target_provider: @target_provider)
      end

      test "yes if business is idp_based_ip_allowlist_configuration?" do
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
        assert_predicate @business, :idp_based_ip_allowlist_configuration?
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: @user_repo, target_provider: @target_provider)
        assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: @org_repo, target_provider: @target_provider)
      end

      test "no for oauth app if skip_idp_ip_allowlist_app_access is enabled" do
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)

        configure_user_as_oauth_app @emu, ["repo"]
        @business.enable_skip_idp_ip_allowlist_app_access(actor: @owner)
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_equal :no, policy.external_conditional_access_policy_applicable(resource: @user_repo, target_provider: @target_provider)
        assert_equal :no, policy.external_conditional_access_policy_applicable(resource: @org_repo, target_provider: @target_provider)
      end

      test "yes for oauth app if skip_idp_ip_allowlist_app_access is disabled" do
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)

        configure_user_as_oauth_app @emu, ["repo"]
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: @user_repo, target_provider: @target_provider)
        assert_equal :yes, policy.external_conditional_access_policy_applicable(resource: @org_repo, target_provider: @target_provider)
      end
    end
  end

  context "multiple applicable" do
    test "none when flag off" do
      GitHub.flipper[:idp_cap_for_web].disable

      configure_user_as_oauth_app @emu, ["repo"]
      policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

      assert_same_elements [], policy.multiple_external_conditional_access_policy_applicable([@user_repo], @target_provider)
    end

    test "none for resource without a TFCA" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)

      policy = TestExternalConditionalAccessPolicy.new
      assert_same_elements [], policy.multiple_external_conditional_access_policy_applicable([:no_resource_for_conditional_access, :no_target_for_conditional_access], @target_provider)
    end

    test "none for resource without a business" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)

      org = create(:organization)
      policy = TestExternalConditionalAccessPolicy.new
      assert_same_elements [], policy.multiple_external_conditional_access_policy_applicable([org], @target_provider)
    end

    test "none when resource's business doesn't have an OIDC provider" do
      biz_without_provider = create(:business, :enterprise_managed)
      owner = biz_without_provider.find_first_emu_owner
      org = create(:organization, business: biz_without_provider, admin: owner)
      repo = create(:repository, owner: org)

      GitHub.flipper[:idp_cap_for_web].enable(biz_without_provider)

      policy = TestExternalConditionalAccessPolicy.new
      assert_same_elements [], policy.multiple_external_conditional_access_policy_applicable([repo], @target_provider)
    end

    test "none if actor is nil" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)

      policy = TestExternalConditionalAccessPolicy.new

      assert_same_elements [], policy.multiple_external_conditional_access_policy_applicable([@user_repo, @org_repo], @target_provider)
    end

    test "none if actor is bot" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)

      installation = make_integration_installation(target: @business, permissions: { "enterprise_administration" => :write })
      policy = TestExternalConditionalAccessPolicy.new(actor: installation)

      assert_same_elements [], policy.multiple_external_conditional_access_policy_applicable([@user_repo, @org_repo], @target_provider)
    end

    test "none for first enterprise owner of EMU business" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)

      policy = TestExternalConditionalAccessPolicy.new(actor: @owner)

      assert_same_elements [], policy.multiple_external_conditional_access_policy_applicable([@user_repo, @org_repo], @target_provider)
    end

    test "applicable to resources for a resource with a OIDC configured business when logged in through an OAuth app?" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)

      configure_user_as_oauth_app @emu, ["repo"]
      policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

      assert_same_elements [@user_repo, @org_repo], policy.multiple_external_conditional_access_policy_applicable([@user_repo, @org_repo], @target_provider)
    end

    test "applicable to resources for a resource with a OIDC configured business" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)

      policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

      assert_same_elements [@user_repo, @org_repo], policy.multiple_external_conditional_access_policy_applicable([@user_repo, @org_repo], @target_provider)
    end

    context "exempt_internal_github_resource?" do
      test "none for GitHub internal IP" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)

        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
        @business.disable_skip_idp_ip_allowlist_app_access(actor: @owner)

        app = create_internal_app_with_capabilities(options: { owner: @business, visibility: "internal_visibility" })
        refute Apps::Internal.capable?(:ip_allowlist_exempt, app: app), "expected #{app} to not be IP allow list exempt"

        @emu.oauth_access = app.grant(@emu)
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)
        policy.actor_ip = "10.56.131.48" # 10.* are github internal IPs
        policy.client_ip = "10.56.131.48" # 10.* are github internal IPs

        exempt_log = {
          "Body" => "Resource exemption status from external conditional access policy applicability",
          "code.function" => "exempt_internal_github_resource?",
          "gh.app.class" => app.class,
          "gh.app.id" => app.id,
          "gh.external_identities.cap_exemption" => "exempted",
          "gh.external_identities.internal_app_exempted" => false,
          "gh.external_identities.internal_ip_exempted" => true,
          "gh.external_identities.client_ip" => "10.56.131.48",
        }

        assert_logged **exempt_log do
          assert_same_elements [], policy.multiple_external_conditional_access_policy_applicable([app], @target_provider)
        end
      end

      test "none for internal app with IP exempt" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)

        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
        @business.disable_skip_idp_ip_allowlist_app_access(actor: @owner)

        app = create_internal_app_with_capabilities(capabilities: { ip_allowlist_exempt: true }, options: { owner: @business, visibility: "internal_visibility" })
        assert Apps::Internal.capable?(:ip_allowlist_exempt, app: app), "expected #{app} to be IP allow list exempt"

        @emu.oauth_access = app.grant(@emu)
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)

        exempt_log = {
          "Body" => "Resource exemption status from external conditional access policy applicability",
          "code.function" => "exempt_internal_github_resource?",
          "gh.app.class" => app.class,
          "gh.app.id" => app.id,
          "gh.external_identities.cap_exemption" => "exempted",
          "gh.external_identities.internal_app_exempted" => true,
          "gh.external_identities.internal_ip_exempted" => false,
          "gh.external_identities.client_ip" => policy.actor_ip,
        }

        assert_logged **exempt_log do
          assert_same_elements [], policy.multiple_external_conditional_access_policy_applicable([app], @target_provider)
        end
      end

      test "applicable to resources for internal app without IP exempt" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)

        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
        @business.disable_skip_idp_ip_allowlist_app_access(actor: @owner)

        app = create_internal_app_with_capabilities(options: { owner: @business, visibility: "internal_visibility" })
        refute Apps::Internal.capable?(:ip_allowlist_exempt, app: app), "expected #{app} to not be IP allow list exempt"

        @emu.oauth_access = app.grant(@emu)
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)

        exempt_log = {
          "Body" => "Resource exemption status from external conditional access policy applicability",
          "code.function" => "exempt_internal_github_resource?",
          "gh.app.class" => app.class,
          "gh.app.id" => app.id,
          "gh.external_identities.cap_exemption" => "not exempted",
          "gh.external_identities.internal_app_exempted" => false,
          "gh.external_identities.internal_ip_exempted" => false,
          "gh.external_identities.client_ip" => policy.actor_ip,
        }

        assert_logged **exempt_log do
          assert_same_elements [app], policy.multiple_external_conditional_access_policy_applicable([app], @target_provider)
        end
      end
    end

    context "skip_idp_ip_allowlist_app_access" do
      test "none for oauth app if skip_idp_ip_allowlist_app_access is enabled" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)

        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
        @business.enable_skip_idp_ip_allowlist_app_access(actor: @owner)

        configure_user_as_oauth_app @emu, ["repo"]
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_same_elements [], policy.multiple_external_conditional_access_policy_applicable([@user_repo, @org_repo], @target_provider)
      end

      test "applicable to resources for oauth app if skip_idp_ip_allowlist_app_access is disabled" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)

        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)

        configure_user_as_oauth_app @emu, ["repo"]
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_same_elements [@user_repo, @org_repo], policy.multiple_external_conditional_access_policy_applicable([@user_repo, @org_repo], @target_provider)
      end

      test "applicable to resources for PATs if skip_idp_ip_allowlist_app_access is disabled" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)

        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)

        @emu.oauth_access = make_personal_access_token(@emu, "repo")
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_same_elements [@user_repo, @org_repo], policy.multiple_external_conditional_access_policy_applicable([@user_repo, @org_repo], @target_provider)
      end

      test "applicable to resources for PATs if skip_idp_ip_allowlist_app_access is enabled" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)

        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
        @business.enable_skip_idp_ip_allowlist_app_access(actor: @owner)

        @emu.oauth_access = make_personal_access_token(@emu, "repo")
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_same_elements [@user_repo, @org_repo], policy.multiple_external_conditional_access_policy_applicable([@user_repo, @org_repo], @target_provider)
      end
    end

    context "ip allow list configuration with idp settings enabled" do
      test "none if business is github_based_ip_allowlist_configuration?" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)

        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::GITHUB)
        assert_predicate @business, :github_based_ip_allowlist_configuration?
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_same_elements [], policy.multiple_external_conditional_access_policy_applicable([@user_repo, @org_repo], @target_provider)
      end

      test "none if business disabled_ip_allowlist_configuration?" do
        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::DISABLED)
        assert_predicate @business, :disabled_ip_allowlist_configuration?
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_same_elements [], policy.multiple_external_conditional_access_policy_applicable([@user_repo, @org_repo], @target_provider)
      end

      test "applicable to resources if business is idp_based_ip_allowlist_configuration?" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)

        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
        assert_predicate @business, :idp_based_ip_allowlist_configuration?
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_same_elements [@user_repo, @org_repo], policy.multiple_external_conditional_access_policy_applicable([@user_repo, @org_repo], @target_provider)
      end

      test "none for oauth app if skip_idp_ip_allowlist_app_access is enabled" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)

        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)

        configure_user_as_oauth_app @emu, ["repo"]
        @business.enable_skip_idp_ip_allowlist_app_access(actor: @owner)
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_same_elements [], policy.multiple_external_conditional_access_policy_applicable([@user_repo, @org_repo], @target_provider)
      end

      test "applicable to resources for oauth app if skip_idp_ip_allowlist_app_access is disabled" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)

        @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)

        configure_user_as_oauth_app @emu, ["repo"]
        policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

        assert_same_elements [@user_repo, @org_repo], policy.multiple_external_conditional_access_policy_applicable([@user_repo, @org_repo], @target_provider)
      end
    end
  end

  context "satisfied" do
    test "no for actor without a refresh token" do
      ExternalIdentityRefreshToken.destroy_all
      policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

      assert_equal :no, policy.external_conditional_access_policy_satisfied(resource: @user_repo, target_provider: @target_provider)
    end

    test "no when cache is empty Azure doesn't return an HTTP 200" do
      OIDC::CapValidator.stubs(:refresh_token_access_token_request).returns(Faraday::Response.new(status: 500))

      expected_log_data = {
        "code.function" => "external_cap.unsatisfied",
        "http.status_code" => 500,
        "gh.business.name" => @business.slug,
        "enduser.id" => @emu,
        "gh.external_identities.oid" => @emu.external_identities.first.external_id
      }

      policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)

      assert_logged **expected_log_data do
        assert_equal :no, policy.external_conditional_access_policy_satisfied(resource: @user_repo, target_provider: @target_provider)
      end
    end

    test "yes when cache is empty and Azure returns an HTTP 200" do
      OIDC::CapValidator.stubs(:refresh_token_access_token_request).returns(Faraday::Response.new(status: 200, body: '{"token_type":"Bearer","scope":"profile openid email User.Read","expires_in":3741,"ext_expires_in":3741,"access_token":"eyJ0eXAiOiJKV1QiLCJub25jZSI6Ik5QQ3pJdndyUGpWakdlSlJQMTBMU2NaWGViOFRkNUdyMmsxMWlpM1Buc00iLCJhbGciOiJSUzI1NiIsIng1dCI6Imwzc1EtNTBjQ0g0eEJWWkxIVEd3blNSNzY4MCIsImtpZCI6Imwzc1EtNTBjQ0g0eEJWWkxIVEd3blNSNzY4MCJ9.eyJhdWQiOiIwMDAwMDAwMy0wMDAwLTAwMDAtYzAwMC0wMDAwMDAwMDAwMDAiLCJpc3MiOiJodHRwczovL3N0cy53aW5kb3dzLm5ldC84MDM5ZTQ3ZC04ZjllLTRmNzQtYjBlOC05MjAxYWE3YTQ4OTUvIiwiaWF0IjoxNjM4OTE2MTU1LCJuYmYiOjE2Mzg5MTYxNTUsImV4cCI6MTYzODkyMDE5NywiYWNjdCI6MCwiYWNyIjoiMSIsImFpbyI6IkUyWmdZTEI4dFdPdjN4dnhGT0cwNEdkZVpoSXhWbmxiOXpGdXViL2pTN2lsazhudmdyc0EiLCJhbXIiOlsicHdkIl0sImFwcF9kaXNwbGF5bmFtZSI6IkdpdEh1YiBPcGVuSUQgQ29ubmVjdCIsImFwcGlkIjoiMWVlOTk1MDgtZmViMS00NDE1LWIxYTUtNTdkNDFmMDllNmU5IiwiYXBwaWRhY3IiOiIyIiwiZmFtaWx5X25hbWUiOiJQcmVtYW5hdGgiLCJnaXZlbl9uYW1lIjoiSW5kcmFqaXRoIiwiaWR0eXAiOiJ1c2VyIiwiaXBhZGRyIjoiMjQuMTguMjU0LjEzNiIsIm5hbWUiOiJJbmRyYWppdGggUHJlbWFuYXRoIiwib2lkIjoiZmJmYzJjMWUtZmZhOS00MjdkLThiNzgtNGE1YTU3OWQ5YmEyIiwicGxhdGYiOiI1IiwicHVpZCI6IjEwMDMyMDAwRUYxRjE1QTEiLCJyaCI6IjAuQVhVQWZlUTVnSjZQZEUtdzZKSUJxbnBJbFFpVjZSNnhfaFZFc2FWWDFCOEo1dWwxQUVBLiIsInNjcCI6IlVzZXIuUmVhZCBwcm9maWxlIG9wZW5pZCBlbWFpbCIsInN1YiI6IjU3Y2VSaWpUbGZfNkhacHdIMTIwanFLRW5VM1JsN0Jsa1NoUkRzX190MW8iLCJ0ZW5hbnRfcmVnaW9uX3Njb3BlIjoiTkEiLCJ0aWQiOiI4MDM5ZTQ3ZC04ZjllLTRmNzQtYjBlOC05MjAxYWE3YTQ4OTUiLCJ1bmlxdWVfbmFtZSI6ImlucHJlbWFuQGdoZW11Lm9ubWljcm9zb2Z0LmNvbSIsInVwbiI6ImlucHJlbWFuQGdoZW11Lm9ubWljcm9zb2Z0LmNvbSIsInV0aSI6ImVKeFZQTjVOOFUyUWNZWWdpM0VEQUEiLCJ2ZXIiOiIxLjAiLCJ3aWRzIjpbIjYyZTkwMzk0LTY5ZjUtNDIzNy05MTkwLTAxMjE3NzE0NWUxMCIsImI3OWZiZjRkLTNlZjktNDY4OS04MTQzLTc2YjE5NGU4NTUwOSJdLCJ4bXNfc3QiOnsic3ViIjoiUFVqNTRTY2YtTXNzVEFYS2VIRTdXSmpLMVUtWTdqck5OUzNlLXB6ZnI0USJ9LCJ4bXNfdGNkdCI6MTYwMjgyMDkwN30.B7gI8Ivb6ewGzTdtyNcsy_Px4iGRbGZbWWLbLekXOeM-qxVKt9ym8Xlo52Bk0T-ePZsWwYPXWcueIgvct1oadBGIT4zjtTsKMwLkHobNKX4eZWqtxln5SKv6n6qiEh2iCmsmcCeDW6iMZqdFTqmuaxOBjRRbJ_sLo_2c_po8u8KGtqKGhgpOIrbI7T74MYf-9vqDMY-KCvPKuDQAuGO45SzMfNvwrZWqyvz2zLSf99nIiukby_w6bOq5g20h0lUgmNjcwj0q2ptLGKyfERMBf79ebC6nXzjy3mT-GYhOEZs6qIqKvJ9czYLuZ11L2sgZqawt5nS-5zG-FTN5li1uhA","refresh_token":"0.AXUAfeQ5gJ6PdE-w6JIBqnpIlQiV6R6x_hVEsaVX1B8J5ul1AEA.AgABAAAAAAD--DLA3VO7QrddgJg7WevrAgDs_wQA9P-Y4ZtUtziF22eTjRBynztBiiWLO15ff3aMwiPWyhsjC2ZRpbZKbIECJxlK8AVIef6keyHj8xT02Q14U4CkZogcqQuTAoJinkJrPq3wV4am8rTHo-TgTLNI16GhTwJbdOCHJ_8TK3sNpuVDCUUH2Aa1zzoMdQhezSt7w1DfJvjnyuYrYLG5vRP3vhYlnZr5wDOuyG-k1baxMvTVwwLoT9YF24_xgyNMj4cFGZyTBcqYxf9alNWRXbe7xYba9gviyDUVjeMul07edcvrpeI7GeSXNqh0qp1uYnKACLvLiAtkFaqF7FPF-oiwZ_Li9AFZ_Afpv5DuIwXvkit1BqYME0EEJ5PH0m13YZlzLCep0uuXMLBU0utRibl__FD8NCcSHLnELRDo1MfESTO4njurQXt5TRV9mFqFu0lRlSgRCcmrtfbJBd8XRs53sRWy-TtSqHYsKTktoU7bYtQe-i18cIiicQmr1qegWZpUwT7DHQDhQxsvnrYuIwEwssUCMz2Gdz2-JoJHi2GsR9dAHK3JziSe18fCOBP2IRgnIECRV7QYYck0hO-3ut84UpUur9DRNhTuoTJnqgKoDELDKcotn1pM6LG-5e30DZ0M-eIoP0xBM9t36ChNR7WULFmMeNaDDYOLDJ3a-boqtsqlltjw8fEM1ISoP_LCYnkmRkmPZTMc0YPVxUtFkPbmzcZHH-w38QaKL5cmQtrcYFwCs-vOuD9Gk--6NPyanr79K18ZC2MpSH8kiL0JO71MS-tz3H19WSF6_86fycWQtXsUPlU1BEXVaUeJgO8fZh7DOYkQuM7vqPLZPQE5EzQPsXIlYMGX4AzEE3YaW_Vk-vktbk9a9ZITxGOvolhK2rSPatx5poOIelvGl-cr-u2O-myY3oW25W55NH0cNwuHqqIimlXUjJ1sc7V7dm-0T0MF3AgyqiTITHDZ3JP37UgYlNBIId06c8aBwXrt3LwIMp937xkHE_66cqYYr9Hn83FfvrOZWYyN5g","id_token":"eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6Imwzc1EtNTBjQ0g0eEJWWkxIVEd3blNSNzY4MCJ9.eyJhdWQiOiIxZWU5OTUwOC1mZWIxLTQ0MTUtYjFhNS01N2Q0MWYwOWU2ZTkiLCJpc3MiOiJodHRwczovL2xvZ2luLm1pY3Jvc29mdG9ubGluZS5jb20vODAzOWU0N2QtOGY5ZS00Zjc0LWIwZTgtOTIwMWFhN2E0ODk1L3YyLjAiLCJpYXQiOjE2Mzg5MTYxNTUsIm5iZiI6MTYzODkxNjE1NSwiZXhwIjoxNjM4OTIwMDU1LCJlbWFpbCI6ImlucHJlbWFuQGdoZW11Lm9ubWljcm9zb2Z0LmNvbSIsIm5hbWUiOiJJbmRyYWppdGggUHJlbWFuYXRoIiwibm9uY2UiOiJscEt3cmJhbVd3MnlaSzNrTFpMNEJMVnhWRGlld2VVZHhSSkxFMFRiNUJKVzdtLTFHVjRoVVEiLCJvaWQiOiJmYmZjMmMxZS1mZmE5LTQyN2QtOGI3OC00YTVhNTc5ZDliYTIiLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJpbnByZW1hbkBnaGVtdS5vbm1pY3Jvc29mdC5jb20iLCJyaCI6IjAuQVhVQWZlUTVnSjZQZEUtdzZKSUJxbnBJbFFpVjZSNnhfaFZFc2FWWDFCOEo1dWwxQUVBLiIsInN1YiI6IlBVajU0U2NmLU1zc1RBWEtlSEU3V0pqSzFVLVk3anJOTlMzZS1wemZyNFEiLCJ0aWQiOiI4MDM5ZTQ3ZC04ZjllLTRmNzQtYjBlOC05MjAxYWE3YTQ4OTUiLCJ1dGkiOiJlSnhWUE41TjhVMlFjWVlnaTNFREFBIiwidmVyIjoiMi4wIn0.Cq83HF3zFE-35N5LQw3B3Bckw875hBn4oSd1_lLpgesIJG9mTAwZzlcIaQrfwq8vGr2fwW-8_R0cbATqerBk_IEufqWakodKSTmq0YnHL6D1l_hN8loqc9Xog8tWPJXZO7nc6tuz1uW2tTXanqRfRmuTNEGoXtQCl9O0Xf0nstn3nujl0azMyzV58Vx4yjkpw8aGXX40JkLji-m7Z50fn8JCCeOsk8lmZ-a2BgmjTzhSif5jQ1oKnlLfOFYZiwi_PO5DSd7j0NyTlERG-rHLXdZbqOSIFucUV7nfGh-G-CjqNhmCRLyoODOeLe71XaBs3B3ofF_WiJu1PhBUDDy1bQ"}'))

      policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)
      assert_equal :yes, policy.external_conditional_access_policy_satisfied(resource: @user_repo, target_provider: @target_provider)
      key = OIDC::CapValidator.cache_key(@ei, policy.actor_ip)
      assert_equal "true", GitHub.kv.get(key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    test "yes when cache is full" do
      # This stub is here to demonstrate that if the cache is full, we are not making a request to the IDP
      OIDC::CapValidator.stubs(:refresh_token_access_token_request).returns(Faraday::Response.new(status: 500))

      policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)
      # Filling the cache manually
      key = OIDC::CapValidator.cache_key(@ei, policy.actor_ip)
      GitHub.kv.set(key, "true", expires: 1.hour.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
      Timecop::freeze(58.minutes.from_now) do
        assert_equal :yes, policy.external_conditional_access_policy_satisfied(resource: @user_repo, target_provider: @target_provider)
        assert_equal "true", GitHub.kv.get(key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_in_delta 2.minutes.from_now.utc, GitHub.kv.ttl(key).value { nil }.utc, 5
        # rubocop:enable GitHub/DoNotUseGlobalKv
      end
    end

    test "yes when cache is full with logging" do
      # This stub is here to demonstrate that if the cache is full, we are not making a request to the IDP
      OIDC::CapValidator.stubs(:refresh_token_access_token_request).returns(Faraday::Response.new(status: 500))

      policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)

      expected_log_data = {
        "code.function" => "external_cap.satisfied_cache",
        "gh.business.name" => @business.slug,
        "enduser.id" => @ei.user.login,
        "gh.external_identities.oid" => @ei.external_id,
        "gh.external_identities.client_ip" => policy.actor_ip
      }

      # Filling the cache manually
      key = OIDC::CapValidator.cache_key(@ei, policy.actor_ip)
      GitHub.kv.set(key, "true", expires: 1.hour.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
      Timecop::freeze(58.minutes.from_now) do
        assert_logged **expected_log_data do
          assert_equal :yes, policy.external_conditional_access_policy_satisfied(resource: @user_repo, target_provider: @target_provider)
        end

        assert_equal "true", GitHub.kv.get(key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_in_delta 2.minutes.from_now.utc, GitHub.kv.ttl(key).value { nil }.utc, 5
        # rubocop:enable GitHub/DoNotUseGlobalKv
      end
    end

    test "no when cache is yes but skipped and the request fails for staff owned enterprise" do
      OIDC::CapValidator.stubs(:refresh_token_access_token_request).returns(Faraday::Response.new(status: 500))

      policy = TestExternalConditionalAccessPolicy.new(actor: @staff_owned_emu, business: @staff_owned_business)
      # Filling the cache manually
      key = OIDC::CapValidator.cache_key(@staff_owned_ei, policy.actor_ip)
      GitHub.kv.set(key, "true", expires: 1.hour.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
      Timecop::freeze(58.minutes.from_now) do
        assert_equal :no, policy.external_conditional_access_policy_satisfied(resource: @staff_owned_user_repo, target_provider: @target_provider)
      end
    end

    test "no when cache is yes but skipped and the request fails for enterprise managed business with ff enabled" do
      GitHub.flipper[:disable_oidc_cap_cache].enable(@business)
      # This stub is here to demonstrate that if the cache is full, we are not making a request to the IDP
      OIDC::CapValidator.stubs(:refresh_token_access_token_request).returns(Faraday::Response.new(status: 500))

      policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)
      # Filling the cache manually
      key = OIDC::CapValidator.cache_key(@ei, policy.actor_ip)
      GitHub.kv.set(key, "true", expires: 1.hour.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
      Timecop::freeze(58.minutes.from_now) do
        assert_equal :no, policy.external_conditional_access_policy_satisfied(resource: @user_repo, target_provider: @target_provider)
      end
    end

    test "yes when cache is unavailable and Azure returns an HTTP 200" do
      OIDC::CapValidator.stubs(:refresh_token_access_token_request).returns(Faraday::Response.new(status: 200, body: '{"token_type":"Bearer","scope":"profile openid email User.Read","expires_in":3741,"ext_expires_in":3741,"access_token":"eyJ0eXAiOiJKV1QiLCJub25jZSI6Ik5QQ3pJdndyUGpWakdlSlJQMTBMU2NaWGViOFRkNUdyMmsxMWlpM1Buc00iLCJhbGciOiJSUzI1NiIsIng1dCI6Imwzc1EtNTBjQ0g0eEJWWkxIVEd3blNSNzY4MCIsImtpZCI6Imwzc1EtNTBjQ0g0eEJWWkxIVEd3blNSNzY4MCJ9.eyJhdWQiOiIwMDAwMDAwMy0wMDAwLTAwMDAtYzAwMC0wMDAwMDAwMDAwMDAiLCJpc3MiOiJodHRwczovL3N0cy53aW5kb3dzLm5ldC84MDM5ZTQ3ZC04ZjllLTRmNzQtYjBlOC05MjAxYWE3YTQ4OTUvIiwiaWF0IjoxNjM4OTE2MTU1LCJuYmYiOjE2Mzg5MTYxNTUsImV4cCI6MTYzODkyMDE5NywiYWNjdCI6MCwiYWNyIjoiMSIsImFpbyI6IkUyWmdZTEI4dFdPdjN4dnhGT0cwNEdkZVpoSXhWbmxiOXpGdXViL2pTN2lsazhudmdyc0EiLCJhbXIiOlsicHdkIl0sImFwcF9kaXNwbGF5bmFtZSI6IkdpdEh1YiBPcGVuSUQgQ29ubmVjdCIsImFwcGlkIjoiMWVlOTk1MDgtZmViMS00NDE1LWIxYTUtNTdkNDFmMDllNmU5IiwiYXBwaWRhY3IiOiIyIiwiZmFtaWx5X25hbWUiOiJQcmVtYW5hdGgiLCJnaXZlbl9uYW1lIjoiSW5kcmFqaXRoIiwiaWR0eXAiOiJ1c2VyIiwiaXBhZGRyIjoiMjQuMTguMjU0LjEzNiIsIm5hbWUiOiJJbmRyYWppdGggUHJlbWFuYXRoIiwib2lkIjoiZmJmYzJjMWUtZmZhOS00MjdkLThiNzgtNGE1YTU3OWQ5YmEyIiwicGxhdGYiOiI1IiwicHVpZCI6IjEwMDMyMDAwRUYxRjE1QTEiLCJyaCI6IjAuQVhVQWZlUTVnSjZQZEUtdzZKSUJxbnBJbFFpVjZSNnhfaFZFc2FWWDFCOEo1dWwxQUVBLiIsInNjcCI6IlVzZXIuUmVhZCBwcm9maWxlIG9wZW5pZCBlbWFpbCIsInN1YiI6IjU3Y2VSaWpUbGZfNkhacHdIMTIwanFLRW5VM1JsN0Jsa1NoUkRzX190MW8iLCJ0ZW5hbnRfcmVnaW9uX3Njb3BlIjoiTkEiLCJ0aWQiOiI4MDM5ZTQ3ZC04ZjllLTRmNzQtYjBlOC05MjAxYWE3YTQ4OTUiLCJ1bmlxdWVfbmFtZSI6ImlucHJlbWFuQGdoZW11Lm9ubWljcm9zb2Z0LmNvbSIsInVwbiI6ImlucHJlbWFuQGdoZW11Lm9ubWljcm9zb2Z0LmNvbSIsInV0aSI6ImVKeFZQTjVOOFUyUWNZWWdpM0VEQUEiLCJ2ZXIiOiIxLjAiLCJ3aWRzIjpbIjYyZTkwMzk0LTY5ZjUtNDIzNy05MTkwLTAxMjE3NzE0NWUxMCIsImI3OWZiZjRkLTNlZjktNDY4OS04MTQzLTc2YjE5NGU4NTUwOSJdLCJ4bXNfc3QiOnsic3ViIjoiUFVqNTRTY2YtTXNzVEFYS2VIRTdXSmpLMVUtWTdqck5OUzNlLXB6ZnI0USJ9LCJ4bXNfdGNkdCI6MTYwMjgyMDkwN30.B7gI8Ivb6ewGzTdtyNcsy_Px4iGRbGZbWWLbLekXOeM-qxVKt9ym8Xlo52Bk0T-ePZsWwYPXWcueIgvct1oadBGIT4zjtTsKMwLkHobNKX4eZWqtxln5SKv6n6qiEh2iCmsmcCeDW6iMZqdFTqmuaxOBjRRbJ_sLo_2c_po8u8KGtqKGhgpOIrbI7T74MYf-9vqDMY-KCvPKuDQAuGO45SzMfNvwrZWqyvz2zLSf99nIiukby_w6bOq5g20h0lUgmNjcwj0q2ptLGKyfERMBf79ebC6nXzjy3mT-GYhOEZs6qIqKvJ9czYLuZ11L2sgZqawt5nS-5zG-FTN5li1uhA","refresh_token":"0.AXUAfeQ5gJ6PdE-w6JIBqnpIlQiV6R6x_hVEsaVX1B8J5ul1AEA.AgABAAAAAAD--DLA3VO7QrddgJg7WevrAgDs_wQA9P-Y4ZtUtziF22eTjRBynztBiiWLO15ff3aMwiPWyhsjC2ZRpbZKbIECJxlK8AVIef6keyHj8xT02Q14U4CkZogcqQuTAoJinkJrPq3wV4am8rTHo-TgTLNI16GhTwJbdOCHJ_8TK3sNpuVDCUUH2Aa1zzoMdQhezSt7w1DfJvjnyuYrYLG5vRP3vhYlnZr5wDOuyG-k1baxMvTVwwLoT9YF24_xgyNMj4cFGZyTBcqYxf9alNWRXbe7xYba9gviyDUVjeMul07edcvrpeI7GeSXNqh0qp1uYnKACLvLiAtkFaqF7FPF-oiwZ_Li9AFZ_Afpv5DuIwXvkit1BqYME0EEJ5PH0m13YZlzLCep0uuXMLBU0utRibl__FD8NCcSHLnELRDo1MfESTO4njurQXt5TRV9mFqFu0lRlSgRCcmrtfbJBd8XRs53sRWy-TtSqHYsKTktoU7bYtQe-i18cIiicQmr1qegWZpUwT7DHQDhQxsvnrYuIwEwssUCMz2Gdz2-JoJHi2GsR9dAHK3JziSe18fCOBP2IRgnIECRV7QYYck0hO-3ut84UpUur9DRNhTuoTJnqgKoDELDKcotn1pM6LG-5e30DZ0M-eIoP0xBM9t36ChNR7WULFmMeNaDDYOLDJ3a-boqtsqlltjw8fEM1ISoP_LCYnkmRkmPZTMc0YPVxUtFkPbmzcZHH-w38QaKL5cmQtrcYFwCs-vOuD9Gk--6NPyanr79K18ZC2MpSH8kiL0JO71MS-tz3H19WSF6_86fycWQtXsUPlU1BEXVaUeJgO8fZh7DOYkQuM7vqPLZPQE5EzQPsXIlYMGX4AzEE3YaW_Vk-vktbk9a9ZITxGOvolhK2rSPatx5poOIelvGl-cr-u2O-myY3oW25W55NH0cNwuHqqIimlXUjJ1sc7V7dm-0T0MF3AgyqiTITHDZ3JP37UgYlNBIId06c8aBwXrt3LwIMp937xkHE_66cqYYr9Hn83FfvrOZWYyN5g","id_token":"eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6Imwzc1EtNTBjQ0g0eEJWWkxIVEd3blNSNzY4MCJ9.eyJhdWQiOiIxZWU5OTUwOC1mZWIxLTQ0MTUtYjFhNS01N2Q0MWYwOWU2ZTkiLCJpc3MiOiJodHRwczovL2xvZ2luLm1pY3Jvc29mdG9ubGluZS5jb20vODAzOWU0N2QtOGY5ZS00Zjc0LWIwZTgtOTIwMWFhN2E0ODk1L3YyLjAiLCJpYXQiOjE2Mzg5MTYxNTUsIm5iZiI6MTYzODkxNjE1NSwiZXhwIjoxNjM4OTIwMDU1LCJlbWFpbCI6ImlucHJlbWFuQGdoZW11Lm9ubWljcm9zb2Z0LmNvbSIsIm5hbWUiOiJJbmRyYWppdGggUHJlbWFuYXRoIiwibm9uY2UiOiJscEt3cmJhbVd3MnlaSzNrTFpMNEJMVnhWRGlld2VVZHhSSkxFMFRiNUJKVzdtLTFHVjRoVVEiLCJvaWQiOiJmYmZjMmMxZS1mZmE5LTQyN2QtOGI3OC00YTVhNTc5ZDliYTIiLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJpbnByZW1hbkBnaGVtdS5vbm1pY3Jvc29mdC5jb20iLCJyaCI6IjAuQVhVQWZlUTVnSjZQZEUtdzZKSUJxbnBJbFFpVjZSNnhfaFZFc2FWWDFCOEo1dWwxQUVBLiIsInN1YiI6IlBVajU0U2NmLU1zc1RBWEtlSEU3V0pqSzFVLVk3anJOTlMzZS1wemZyNFEiLCJ0aWQiOiI4MDM5ZTQ3ZC04ZjllLTRmNzQtYjBlOC05MjAxYWE3YTQ4OTUiLCJ1dGkiOiJlSnhWUE41TjhVMlFjWVlnaTNFREFBIiwidmVyIjoiMi4wIn0.Cq83HF3zFE-35N5LQw3B3Bckw875hBn4oSd1_lLpgesIJG9mTAwZzlcIaQrfwq8vGr2fwW-8_R0cbATqerBk_IEufqWakodKSTmq0YnHL6D1l_hN8loqc9Xog8tWPJXZO7nc6tuz1uW2tTXanqRfRmuTNEGoXtQCl9O0Xf0nstn3nujl0azMyzV58Vx4yjkpw8aGXX40JkLji-m7Z50fn8JCCeOsk8lmZ-a2BgmjTzhSif5jQ1oKnlLfOFYZiwi_PO5DSd7j0NyTlERG-rHLXdZbqOSIFucUV7nfGh-G-CjqNhmCRLyoODOeLe71XaBs3B3ofF_WiJu1PhBUDDy1bQ"}'))
      GitHub.kv.stubs(:set).raises(GitHub::KV::UnavailableError) # rubocop:todo GitHub/DoNotUseGlobalKv

      policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)
      assert_equal :yes, policy.external_conditional_access_policy_satisfied(resource: @user_repo, target_provider: @target_provider)
    end
  end

  context "multiple satisfied" do
    test "none when flag off" do
      GitHub.flipper[:idp_cap_for_web].disable

      policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)
      assert_same_elements [], policy.multiple_external_conditional_access_policy_satisfied([@user_repo, @user_repo_two], @target_provider)
    end

    test "none for actor without a refresh token" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)

      ExternalIdentityRefreshToken.destroy_all
      policy = TestExternalConditionalAccessPolicy.new(actor: @emu)

      assert_same_elements [], policy.multiple_external_conditional_access_policy_satisfied([@user_repo, @user_repo_two], @target_provider)
    end

    test "none when cache is empty Azure doesn't return an HTTP 200" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)

      OIDC::CapValidator.stubs(:refresh_token_access_token_request).returns(Faraday::Response.new(status: 500))

      expected_log_data = {
        "code.function" => "external_cap.unsatisfied",
        "http.status_code" => 500,
        "gh.business.name" => @business.slug,
        "enduser.id" => @emu,
        "gh.external_identities.oid" => @emu.external_identities.first.external_id
      }

      policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)

      assert_logged **expected_log_data do
        assert_same_elements [], policy.multiple_external_conditional_access_policy_satisfied([@user_repo, @user_repo_two], @target_provider)
      end
    end

    test "returns resources when cache is empty and Azure returns an HTTP 200" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)

      OIDC::CapValidator.stubs(:refresh_token_access_token_request).returns(Faraday::Response.new(status: 200, body: '{"token_type":"Bearer","scope":"profile openid email User.Read","expires_in":3741,"ext_expires_in":3741,"access_token":"eyJ0eXAiOiJKV1QiLCJub25jZSI6Ik5QQ3pJdndyUGpWakdlSlJQMTBMU2NaWGViOFRkNUdyMmsxMWlpM1Buc00iLCJhbGciOiJSUzI1NiIsIng1dCI6Imwzc1EtNTBjQ0g0eEJWWkxIVEd3blNSNzY4MCIsImtpZCI6Imwzc1EtNTBjQ0g0eEJWWkxIVEd3blNSNzY4MCJ9.eyJhdWQiOiIwMDAwMDAwMy0wMDAwLTAwMDAtYzAwMC0wMDAwMDAwMDAwMDAiLCJpc3MiOiJodHRwczovL3N0cy53aW5kb3dzLm5ldC84MDM5ZTQ3ZC04ZjllLTRmNzQtYjBlOC05MjAxYWE3YTQ4OTUvIiwiaWF0IjoxNjM4OTE2MTU1LCJuYmYiOjE2Mzg5MTYxNTUsImV4cCI6MTYzODkyMDE5NywiYWNjdCI6MCwiYWNyIjoiMSIsImFpbyI6IkUyWmdZTEI4dFdPdjN4dnhGT0cwNEdkZVpoSXhWbmxiOXpGdXViL2pTN2lsazhudmdyc0EiLCJhbXIiOlsicHdkIl0sImFwcF9kaXNwbGF5bmFtZSI6IkdpdEh1YiBPcGVuSUQgQ29ubmVjdCIsImFwcGlkIjoiMWVlOTk1MDgtZmViMS00NDE1LWIxYTUtNTdkNDFmMDllNmU5IiwiYXBwaWRhY3IiOiIyIiwiZmFtaWx5X25hbWUiOiJQcmVtYW5hdGgiLCJnaXZlbl9uYW1lIjoiSW5kcmFqaXRoIiwiaWR0eXAiOiJ1c2VyIiwiaXBhZGRyIjoiMjQuMTguMjU0LjEzNiIsIm5hbWUiOiJJbmRyYWppdGggUHJlbWFuYXRoIiwib2lkIjoiZmJmYzJjMWUtZmZhOS00MjdkLThiNzgtNGE1YTU3OWQ5YmEyIiwicGxhdGYiOiI1IiwicHVpZCI6IjEwMDMyMDAwRUYxRjE1QTEiLCJyaCI6IjAuQVhVQWZlUTVnSjZQZEUtdzZKSUJxbnBJbFFpVjZSNnhfaFZFc2FWWDFCOEo1dWwxQUVBLiIsInNjcCI6IlVzZXIuUmVhZCBwcm9maWxlIG9wZW5pZCBlbWFpbCIsInN1YiI6IjU3Y2VSaWpUbGZfNkhacHdIMTIwanFLRW5VM1JsN0Jsa1NoUkRzX190MW8iLCJ0ZW5hbnRfcmVnaW9uX3Njb3BlIjoiTkEiLCJ0aWQiOiI4MDM5ZTQ3ZC04ZjllLTRmNzQtYjBlOC05MjAxYWE3YTQ4OTUiLCJ1bmlxdWVfbmFtZSI6ImlucHJlbWFuQGdoZW11Lm9ubWljcm9zb2Z0LmNvbSIsInVwbiI6ImlucHJlbWFuQGdoZW11Lm9ubWljcm9zb2Z0LmNvbSIsInV0aSI6ImVKeFZQTjVOOFUyUWNZWWdpM0VEQUEiLCJ2ZXIiOiIxLjAiLCJ3aWRzIjpbIjYyZTkwMzk0LTY5ZjUtNDIzNy05MTkwLTAxMjE3NzE0NWUxMCIsImI3OWZiZjRkLTNlZjktNDY4OS04MTQzLTc2YjE5NGU4NTUwOSJdLCJ4bXNfc3QiOnsic3ViIjoiUFVqNTRTY2YtTXNzVEFYS2VIRTdXSmpLMVUtWTdqck5OUzNlLXB6ZnI0USJ9LCJ4bXNfdGNkdCI6MTYwMjgyMDkwN30.B7gI8Ivb6ewGzTdtyNcsy_Px4iGRbGZbWWLbLekXOeM-qxVKt9ym8Xlo52Bk0T-ePZsWwYPXWcueIgvct1oadBGIT4zjtTsKMwLkHobNKX4eZWqtxln5SKv6n6qiEh2iCmsmcCeDW6iMZqdFTqmuaxOBjRRbJ_sLo_2c_po8u8KGtqKGhgpOIrbI7T74MYf-9vqDMY-KCvPKuDQAuGO45SzMfNvwrZWqyvz2zLSf99nIiukby_w6bOq5g20h0lUgmNjcwj0q2ptLGKyfERMBf79ebC6nXzjy3mT-GYhOEZs6qIqKvJ9czYLuZ11L2sgZqawt5nS-5zG-FTN5li1uhA","refresh_token":"0.AXUAfeQ5gJ6PdE-w6JIBqnpIlQiV6R6x_hVEsaVX1B8J5ul1AEA.AgABAAAAAAD--DLA3VO7QrddgJg7WevrAgDs_wQA9P-Y4ZtUtziF22eTjRBynztBiiWLO15ff3aMwiPWyhsjC2ZRpbZKbIECJxlK8AVIef6keyHj8xT02Q14U4CkZogcqQuTAoJinkJrPq3wV4am8rTHo-TgTLNI16GhTwJbdOCHJ_8TK3sNpuVDCUUH2Aa1zzoMdQhezSt7w1DfJvjnyuYrYLG5vRP3vhYlnZr5wDOuyG-k1baxMvTVwwLoT9YF24_xgyNMj4cFGZyTBcqYxf9alNWRXbe7xYba9gviyDUVjeMul07edcvrpeI7GeSXNqh0qp1uYnKACLvLiAtkFaqF7FPF-oiwZ_Li9AFZ_Afpv5DuIwXvkit1BqYME0EEJ5PH0m13YZlzLCep0uuXMLBU0utRibl__FD8NCcSHLnELRDo1MfESTO4njurQXt5TRV9mFqFu0lRlSgRCcmrtfbJBd8XRs53sRWy-TtSqHYsKTktoU7bYtQe-i18cIiicQmr1qegWZpUwT7DHQDhQxsvnrYuIwEwssUCMz2Gdz2-JoJHi2GsR9dAHK3JziSe18fCOBP2IRgnIECRV7QYYck0hO-3ut84UpUur9DRNhTuoTJnqgKoDELDKcotn1pM6LG-5e30DZ0M-eIoP0xBM9t36ChNR7WULFmMeNaDDYOLDJ3a-boqtsqlltjw8fEM1ISoP_LCYnkmRkmPZTMc0YPVxUtFkPbmzcZHH-w38QaKL5cmQtrcYFwCs-vOuD9Gk--6NPyanr79K18ZC2MpSH8kiL0JO71MS-tz3H19WSF6_86fycWQtXsUPlU1BEXVaUeJgO8fZh7DOYkQuM7vqPLZPQE5EzQPsXIlYMGX4AzEE3YaW_Vk-vktbk9a9ZITxGOvolhK2rSPatx5poOIelvGl-cr-u2O-myY3oW25W55NH0cNwuHqqIimlXUjJ1sc7V7dm-0T0MF3AgyqiTITHDZ3JP37UgYlNBIId06c8aBwXrt3LwIMp937xkHE_66cqYYr9Hn83FfvrOZWYyN5g","id_token":"eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6Imwzc1EtNTBjQ0g0eEJWWkxIVEd3blNSNzY4MCJ9.eyJhdWQiOiIxZWU5OTUwOC1mZWIxLTQ0MTUtYjFhNS01N2Q0MWYwOWU2ZTkiLCJpc3MiOiJodHRwczovL2xvZ2luLm1pY3Jvc29mdG9ubGluZS5jb20vODAzOWU0N2QtOGY5ZS00Zjc0LWIwZTgtOTIwMWFhN2E0ODk1L3YyLjAiLCJpYXQiOjE2Mzg5MTYxNTUsIm5iZiI6MTYzODkxNjE1NSwiZXhwIjoxNjM4OTIwMDU1LCJlbWFpbCI6ImlucHJlbWFuQGdoZW11Lm9ubWljcm9zb2Z0LmNvbSIsIm5hbWUiOiJJbmRyYWppdGggUHJlbWFuYXRoIiwibm9uY2UiOiJscEt3cmJhbVd3MnlaSzNrTFpMNEJMVnhWRGlld2VVZHhSSkxFMFRiNUJKVzdtLTFHVjRoVVEiLCJvaWQiOiJmYmZjMmMxZS1mZmE5LTQyN2QtOGI3OC00YTVhNTc5ZDliYTIiLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJpbnByZW1hbkBnaGVtdS5vbm1pY3Jvc29mdC5jb20iLCJyaCI6IjAuQVhVQWZlUTVnSjZQZEUtdzZKSUJxbnBJbFFpVjZSNnhfaFZFc2FWWDFCOEo1dWwxQUVBLiIsInN1YiI6IlBVajU0U2NmLU1zc1RBWEtlSEU3V0pqSzFVLVk3anJOTlMzZS1wemZyNFEiLCJ0aWQiOiI4MDM5ZTQ3ZC04ZjllLTRmNzQtYjBlOC05MjAxYWE3YTQ4OTUiLCJ1dGkiOiJlSnhWUE41TjhVMlFjWVlnaTNFREFBIiwidmVyIjoiMi4wIn0.Cq83HF3zFE-35N5LQw3B3Bckw875hBn4oSd1_lLpgesIJG9mTAwZzlcIaQrfwq8vGr2fwW-8_R0cbATqerBk_IEufqWakodKSTmq0YnHL6D1l_hN8loqc9Xog8tWPJXZO7nc6tuz1uW2tTXanqRfRmuTNEGoXtQCl9O0Xf0nstn3nujl0azMyzV58Vx4yjkpw8aGXX40JkLji-m7Z50fn8JCCeOsk8lmZ-a2BgmjTzhSif5jQ1oKnlLfOFYZiwi_PO5DSd7j0NyTlERG-rHLXdZbqOSIFucUV7nfGh-G-CjqNhmCRLyoODOeLe71XaBs3B3ofF_WiJu1PhBUDDy1bQ"}'))

      policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)
      assert_same_elements [@user_repo, @user_repo_two], policy.multiple_external_conditional_access_policy_satisfied([@user_repo, @user_repo_two], @target_provider)
      key = OIDC::CapValidator.cache_key(@ei, policy.actor_ip)
      assert_equal "true", GitHub.kv.get(key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    test "returns resources when cache is full" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)

      # This stub is here to demonstrate that if the cache is full, we are not making a request to the IDP
      OIDC::CapValidator.stubs(:refresh_token_access_token_request).returns(Faraday::Response.new(status: 500))

      policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)
      # Filling the cache manually
      key = OIDC::CapValidator.cache_key(@ei, policy.actor_ip)
      GitHub.kv.set(key, "true", expires: 1.hour.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
      Timecop::freeze(58.minutes.from_now) do
        assert_same_elements [@user_repo, @user_repo_two], policy.multiple_external_conditional_access_policy_satisfied([@user_repo, @user_repo_two], @target_provider)
        assert_equal "true", GitHub.kv.get(key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_in_delta 2.minutes.from_now.utc, GitHub.kv.ttl(key).value { nil }.utc, 5
        # rubocop:enable GitHub/DoNotUseGlobalKv
      end
    end

    test "yes when cache is full with logging" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)

      # This stub is here to demonstrate that if the cache is full, we are not making a request to the IDP
      OIDC::CapValidator.stubs(:refresh_token_access_token_request).returns(Faraday::Response.new(status: 500))

      policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)

      expected_log_data = {
        "code.function" => "external_cap.satisfied_cache",
        "gh.business.name" => @business.slug,
        "enduser.id" => @ei.user.login,
        "gh.external_identities.oid" => @ei.external_id,
        "gh.external_identities.client_ip" => policy.actor_ip
      }

      # Filling the cache manually
      key = OIDC::CapValidator.cache_key(@ei, policy.actor_ip)
      GitHub.kv.set(key, "true", expires: 1.hour.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
      Timecop::freeze(58.minutes.from_now) do
        assert_logged **expected_log_data do
          assert_same_elements [@user_repo, @user_repo_two], policy.multiple_external_conditional_access_policy_satisfied([@user_repo, @user_repo_two], @target_provider)
        end

        assert_equal "true", GitHub.kv.get(key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_in_delta 2.minutes.from_now.utc, GitHub.kv.ttl(key).value { nil }.utc, 5
        # rubocop:enable GitHub/DoNotUseGlobalKv
      end
    end

    test "no when cache is yes but skipped and the request fails for staff owned enterprise" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)

      OIDC::CapValidator.stubs(:refresh_token_access_token_request).returns(Faraday::Response.new(status: 500))

      policy = TestExternalConditionalAccessPolicy.new(actor: @staff_owned_emu, business: @staff_owned_business)
      # Filling the cache manually
      key = OIDC::CapValidator.cache_key(@staff_owned_ei, policy.actor_ip)
      GitHub.kv.set(key, "true", expires: 1.hour.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
      Timecop::freeze(58.minutes.from_now) do
        assert_same_elements [], policy.multiple_external_conditional_access_policy_satisfied([@staff_owned_user_repo_two], @target_provider)
      end
    end

    test "no when cache is yes but skipped and the request fails for enterprise managed business with ff enabled" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)
      GitHub.flipper[:disable_oidc_cap_cache].enable(@business)

      OIDC::CapValidator.stubs(:refresh_token_access_token_request).returns(Faraday::Response.new(status: 500))

      policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)
      # Filling the cache manually
      key = OIDC::CapValidator.cache_key(@ei, policy.actor_ip)
      GitHub.kv.set(key, "true", expires: 1.hour.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
      Timecop::freeze(58.minutes.from_now) do
        assert_same_elements [], policy.multiple_external_conditional_access_policy_satisfied([@user_repo, @user_repo_two], @target_provider)
      end
    end

    test "yes when cache is unavailable and Azure returns an HTTP 200" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)

      OIDC::CapValidator.stubs(:refresh_token_access_token_request).returns(Faraday::Response.new(status: 200, body: '{"token_type":"Bearer","scope":"profile openid email User.Read","expires_in":3741,"ext_expires_in":3741,"access_token":"eyJ0eXAiOiJKV1QiLCJub25jZSI6Ik5QQ3pJdndyUGpWakdlSlJQMTBMU2NaWGViOFRkNUdyMmsxMWlpM1Buc00iLCJhbGciOiJSUzI1NiIsIng1dCI6Imwzc1EtNTBjQ0g0eEJWWkxIVEd3blNSNzY4MCIsImtpZCI6Imwzc1EtNTBjQ0g0eEJWWkxIVEd3blNSNzY4MCJ9.eyJhdWQiOiIwMDAwMDAwMy0wMDAwLTAwMDAtYzAwMC0wMDAwMDAwMDAwMDAiLCJpc3MiOiJodHRwczovL3N0cy53aW5kb3dzLm5ldC84MDM5ZTQ3ZC04ZjllLTRmNzQtYjBlOC05MjAxYWE3YTQ4OTUvIiwiaWF0IjoxNjM4OTE2MTU1LCJuYmYiOjE2Mzg5MTYxNTUsImV4cCI6MTYzODkyMDE5NywiYWNjdCI6MCwiYWNyIjoiMSIsImFpbyI6IkUyWmdZTEI4dFdPdjN4dnhGT0cwNEdkZVpoSXhWbmxiOXpGdXViL2pTN2lsazhudmdyc0EiLCJhbXIiOlsicHdkIl0sImFwcF9kaXNwbGF5bmFtZSI6IkdpdEh1YiBPcGVuSUQgQ29ubmVjdCIsImFwcGlkIjoiMWVlOTk1MDgtZmViMS00NDE1LWIxYTUtNTdkNDFmMDllNmU5IiwiYXBwaWRhY3IiOiIyIiwiZmFtaWx5X25hbWUiOiJQcmVtYW5hdGgiLCJnaXZlbl9uYW1lIjoiSW5kcmFqaXRoIiwiaWR0eXAiOiJ1c2VyIiwiaXBhZGRyIjoiMjQuMTguMjU0LjEzNiIsIm5hbWUiOiJJbmRyYWppdGggUHJlbWFuYXRoIiwib2lkIjoiZmJmYzJjMWUtZmZhOS00MjdkLThiNzgtNGE1YTU3OWQ5YmEyIiwicGxhdGYiOiI1IiwicHVpZCI6IjEwMDMyMDAwRUYxRjE1QTEiLCJyaCI6IjAuQVhVQWZlUTVnSjZQZEUtdzZKSUJxbnBJbFFpVjZSNnhfaFZFc2FWWDFCOEo1dWwxQUVBLiIsInNjcCI6IlVzZXIuUmVhZCBwcm9maWxlIG9wZW5pZCBlbWFpbCIsInN1YiI6IjU3Y2VSaWpUbGZfNkhacHdIMTIwanFLRW5VM1JsN0Jsa1NoUkRzX190MW8iLCJ0ZW5hbnRfcmVnaW9uX3Njb3BlIjoiTkEiLCJ0aWQiOiI4MDM5ZTQ3ZC04ZjllLTRmNzQtYjBlOC05MjAxYWE3YTQ4OTUiLCJ1bmlxdWVfbmFtZSI6ImlucHJlbWFuQGdoZW11Lm9ubWljcm9zb2Z0LmNvbSIsInVwbiI6ImlucHJlbWFuQGdoZW11Lm9ubWljcm9zb2Z0LmNvbSIsInV0aSI6ImVKeFZQTjVOOFUyUWNZWWdpM0VEQUEiLCJ2ZXIiOiIxLjAiLCJ3aWRzIjpbIjYyZTkwMzk0LTY5ZjUtNDIzNy05MTkwLTAxMjE3NzE0NWUxMCIsImI3OWZiZjRkLTNlZjktNDY4OS04MTQzLTc2YjE5NGU4NTUwOSJdLCJ4bXNfc3QiOnsic3ViIjoiUFVqNTRTY2YtTXNzVEFYS2VIRTdXSmpLMVUtWTdqck5OUzNlLXB6ZnI0USJ9LCJ4bXNfdGNkdCI6MTYwMjgyMDkwN30.B7gI8Ivb6ewGzTdtyNcsy_Px4iGRbGZbWWLbLekXOeM-qxVKt9ym8Xlo52Bk0T-ePZsWwYPXWcueIgvct1oadBGIT4zjtTsKMwLkHobNKX4eZWqtxln5SKv6n6qiEh2iCmsmcCeDW6iMZqdFTqmuaxOBjRRbJ_sLo_2c_po8u8KGtqKGhgpOIrbI7T74MYf-9vqDMY-KCvPKuDQAuGO45SzMfNvwrZWqyvz2zLSf99nIiukby_w6bOq5g20h0lUgmNjcwj0q2ptLGKyfERMBf79ebC6nXzjy3mT-GYhOEZs6qIqKvJ9czYLuZ11L2sgZqawt5nS-5zG-FTN5li1uhA","refresh_token":"0.AXUAfeQ5gJ6PdE-w6JIBqnpIlQiV6R6x_hVEsaVX1B8J5ul1AEA.AgABAAAAAAD--DLA3VO7QrddgJg7WevrAgDs_wQA9P-Y4ZtUtziF22eTjRBynztBiiWLO15ff3aMwiPWyhsjC2ZRpbZKbIECJxlK8AVIef6keyHj8xT02Q14U4CkZogcqQuTAoJinkJrPq3wV4am8rTHo-TgTLNI16GhTwJbdOCHJ_8TK3sNpuVDCUUH2Aa1zzoMdQhezSt7w1DfJvjnyuYrYLG5vRP3vhYlnZr5wDOuyG-k1baxMvTVwwLoT9YF24_xgyNMj4cFGZyTBcqYxf9alNWRXbe7xYba9gviyDUVjeMul07edcvrpeI7GeSXNqh0qp1uYnKACLvLiAtkFaqF7FPF-oiwZ_Li9AFZ_Afpv5DuIwXvkit1BqYME0EEJ5PH0m13YZlzLCep0uuXMLBU0utRibl__FD8NCcSHLnELRDo1MfESTO4njurQXt5TRV9mFqFu0lRlSgRCcmrtfbJBd8XRs53sRWy-TtSqHYsKTktoU7bYtQe-i18cIiicQmr1qegWZpUwT7DHQDhQxsvnrYuIwEwssUCMz2Gdz2-JoJHi2GsR9dAHK3JziSe18fCOBP2IRgnIECRV7QYYck0hO-3ut84UpUur9DRNhTuoTJnqgKoDELDKcotn1pM6LG-5e30DZ0M-eIoP0xBM9t36ChNR7WULFmMeNaDDYOLDJ3a-boqtsqlltjw8fEM1ISoP_LCYnkmRkmPZTMc0YPVxUtFkPbmzcZHH-w38QaKL5cmQtrcYFwCs-vOuD9Gk--6NPyanr79K18ZC2MpSH8kiL0JO71MS-tz3H19WSF6_86fycWQtXsUPlU1BEXVaUeJgO8fZh7DOYkQuM7vqPLZPQE5EzQPsXIlYMGX4AzEE3YaW_Vk-vktbk9a9ZITxGOvolhK2rSPatx5poOIelvGl-cr-u2O-myY3oW25W55NH0cNwuHqqIimlXUjJ1sc7V7dm-0T0MF3AgyqiTITHDZ3JP37UgYlNBIId06c8aBwXrt3LwIMp937xkHE_66cqYYr9Hn83FfvrOZWYyN5g","id_token":"eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6Imwzc1EtNTBjQ0g0eEJWWkxIVEd3blNSNzY4MCJ9.eyJhdWQiOiIxZWU5OTUwOC1mZWIxLTQ0MTUtYjFhNS01N2Q0MWYwOWU2ZTkiLCJpc3MiOiJodHRwczovL2xvZ2luLm1pY3Jvc29mdG9ubGluZS5jb20vODAzOWU0N2QtOGY5ZS00Zjc0LWIwZTgtOTIwMWFhN2E0ODk1L3YyLjAiLCJpYXQiOjE2Mzg5MTYxNTUsIm5iZiI6MTYzODkxNjE1NSwiZXhwIjoxNjM4OTIwMDU1LCJlbWFpbCI6ImlucHJlbWFuQGdoZW11Lm9ubWljcm9zb2Z0LmNvbSIsIm5hbWUiOiJJbmRyYWppdGggUHJlbWFuYXRoIiwibm9uY2UiOiJscEt3cmJhbVd3MnlaSzNrTFpMNEJMVnhWRGlld2VVZHhSSkxFMFRiNUJKVzdtLTFHVjRoVVEiLCJvaWQiOiJmYmZjMmMxZS1mZmE5LTQyN2QtOGI3OC00YTVhNTc5ZDliYTIiLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJpbnByZW1hbkBnaGVtdS5vbm1pY3Jvc29mdC5jb20iLCJyaCI6IjAuQVhVQWZlUTVnSjZQZEUtdzZKSUJxbnBJbFFpVjZSNnhfaFZFc2FWWDFCOEo1dWwxQUVBLiIsInN1YiI6IlBVajU0U2NmLU1zc1RBWEtlSEU3V0pqSzFVLVk3anJOTlMzZS1wemZyNFEiLCJ0aWQiOiI4MDM5ZTQ3ZC04ZjllLTRmNzQtYjBlOC05MjAxYWE3YTQ4OTUiLCJ1dGkiOiJlSnhWUE41TjhVMlFjWVlnaTNFREFBIiwidmVyIjoiMi4wIn0.Cq83HF3zFE-35N5LQw3B3Bckw875hBn4oSd1_lLpgesIJG9mTAwZzlcIaQrfwq8vGr2fwW-8_R0cbATqerBk_IEufqWakodKSTmq0YnHL6D1l_hN8loqc9Xog8tWPJXZO7nc6tuz1uW2tTXanqRfRmuTNEGoXtQCl9O0Xf0nstn3nujl0azMyzV58Vx4yjkpw8aGXX40JkLji-m7Z50fn8JCCeOsk8lmZ-a2BgmjTzhSif5jQ1oKnlLfOFYZiwi_PO5DSd7j0NyTlERG-rHLXdZbqOSIFucUV7nfGh-G-CjqNhmCRLyoODOeLe71XaBs3B3ofF_WiJu1PhBUDDy1bQ"}'))
      GitHub.kv.stubs(:set).raises(GitHub::KV::UnavailableError) # rubocop:todo GitHub/DoNotUseGlobalKv

      policy = TestExternalConditionalAccessPolicy.new(actor: @emu, business: @business)
      assert_same_elements [@user_repo, @user_repo_two], policy.multiple_external_conditional_access_policy_satisfied([@user_repo, @user_repo_two], @target_provider)
    end
  end
end unless GitHub.single_business_environment?
