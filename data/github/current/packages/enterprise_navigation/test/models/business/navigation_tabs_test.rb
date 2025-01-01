# typed: true
# frozen_string_literal: true

require "test_helper"

class Business::NavigationTabsTest < GitHub::TestCase
  include GitHub::Memoizer
  include GitHub::ComponentTestHelpers
  include SecretScanning::Features::FeatureFlagHelper
  include FineGrainedPermissionsTestHelper

  fixtures do
    @owner = create :user, login: "owner"
    @billing_manager = create :user
    @member = create :user
    @org_admin = create :user
    @org = create :organization, admin: @org_admin
    @org.add_member @member
    @business = create :business, owners: [@owner], organizations: [@org]
    @business.billing.add_manager(@billing_manager, actor: @owner)
    @unaffiliated = create :user
    create :business_user_account, business: @business, user: @unaffiliated, business_roles_bitfield: 0

    @repo = create :repository, name: "testrepo", owner: @owner, organization: @org, from_example: :repository_test_simple
    @release = create :release, repository: @repo, author: @owner, tag_name: "1.1.1", state: :published
    @public_package = @repo.packages.build(name: "public-package-1", package_type: Registry::Package.symbolize_package_type(:docker))
    @package_version = @public_package.package_versions.build(version: "1.1.1", release: @release, author: @owner, sha256: "DEADBEEFAS", platform: "docker")
    @package_version.files.build(size: 10, state: 1, filename: "public-package-1.gem")
    assert @public_package.save!
    @business_plus_org = create(:business_plus_organization, admin: @owner, billing_type: "invoice")

    enterprise_security_manager_team = create :enterprise_security_manager_team, business: @business
    @enterprise_security_manager = create :user
    @org.add_member @enterprise_security_manager # Because the factory doesn't set up the org teams sync
    enterprise_security_manager_team.bulk_add_members(users: [@enterprise_security_manager])
  end

  setup do
    enable_feature_flag(:batch_business_org_abilities)
    disable_feature_flag(:codespaces_vnet_settings)
    disable_feature_flag(:enterprise_app_installation_management)
    Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
    disable_feature_flag(:sponsors_self_serve_enterprise)
    disable_feature_flag(:codespaces_salus_beta_customers)
    disable_feature_flag(:codespaces_vnet_injection_beta)
    enable_feature_flag(:custom_enterprise_role_feature, @business)
    enable_feature_flag(:enterprise_custom_organization_roles, @business)
    disable_feature_flag(:actions_usage_metrics_enterprise)
    Copilot::Business.new(@business).ensure_configuration!
    if TestEnv.test_all_features?
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      EnterpriseTeam.stubs(:enabled_for_organization_security_manager?).returns(true)
    end
  end

  if GitHub.single_business_environment?
    context "Insights" do
      test "hide insights tab on single tenant enterprise" do
        enable_feature_flag(:actions_usage_metrics)
        enable_feature_flag(:actions_usage_metrics_enterprise)
        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)

        tab = tabs_builder.tabs.find { |tab| tab.text == "Insights" }

        assert_nil tab
      end

      test "hides insights tab for basic enterprises", skip_enterprise: true do
        enable_feature_flag(:actions_usage_metrics)
        enable_feature_flag(:actions_usage_metrics_enterprise)
        @business.update!(seats_plan_type: :basic)

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
        tab = tabs_builder.tabs.find { |tab| tab.text == "Insights" }

        assert_nil tab
      end
    end

    context "when current_user is an owner" do
      test "renders menu items appropriately on GHES" do
        GitHub.stubs(:dotcom_connection_enabled?).returns(false)

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
        actual_tabs = tabs_builder.tabs.map(&:text)

        assert_equal %w[Overview Organizations People Policies Security Settings], actual_tabs
      end

      test "do not render Packages in menu items when registry v2 is disabled for GHES" do
        GitHub.stubs(:subdomain_isolation?).returns(true)
        GitHub.stubs(:registry_v2_enabled_for_enterprise?).returns(false)
        Registry::Package.any_instance.stubs(:any_package_exists).returns(1)

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 3,
        )
        assert_test_selector("settings-sidebar")
        refute_selector("a", text: "Packages")
      end

      test "do not render Packages in menu items when subdomain isolation is disabled for GHES" do
        GitHub.stubs(:subdomain_isolation?).returns(false)
        GitHub.stubs(:registry_v2_enabled_for_enterprise?).returns(true)
        Registry::Package.any_instance.stubs(:any_package_exists).returns(1)

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 3,
        )
        assert_test_selector("settings-sidebar")
        refute_selector("a", text: "Packages")
      end

      test "do not render Packages in menu items when there are no docker package with subdomain isolation on and registry v2 enabled GHES" do
        GitHub.stubs(:subdomain_isolation?).returns(true)
        GitHub.stubs(:registry_v2_enabled_for_enterprise?).returns(true)
        Registry::Package.stubs(:any_package_exists).returns([])
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 3,
        )
        assert_test_selector("settings-sidebar")
        refute_selector("a", text: "Packages")
      end

      test "render Packages in menu items when registry v2 is enabled for GHES" do
        GitHub.stubs(:subdomain_isolation?).returns(true)
        GitHub.stubs(:registry_v2_enabled_for_enterprise?).returns(true)
        Registry::Package.any_instance.stubs(:any_package_exists).returns(1)

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 3,
        )
        assert_test_selector("settings-sidebar")
        assert_selector("a", text: "Packages")
      end

      test "renders navbar with Connect menu item when it's enabled on GHES" do
        GitHub.stubs(:dotcom_connection_enabled?).returns(true)

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
        tab = tabs_builder.tabs.find { |tab| tab.text == "GitHub Connect" }
        assert_equal urls.admin_settings_dotcom_connection_enterprise_path(@business), tab.href
      end

      context "renders sub-menu items appropriately on GHES as owner" do
        test "people" do
          GitHub.stubs(:dotcom_connection_enabled?).returns(true)

          # Disabled on GHES
          disable_feature_flag(:custom_enterprise_role_feature, @business)
          disable_feature_flag(:enterprise_custom_organization_roles, @business)

          # For the sub-menu items under "Code security"
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @owner,
              business: @business,
              sidebar_section: :people,
            ),
            allowed_queries: 3,
          )
          assert_test_selector("people-sidebar")
          assert_selector("a", text: "Members")
          assert_selector("a", text: "Administrators")
          assert_selector("a", text: "Outside collaborators")
        end

        test "policies" do
          GitHub.stubs(:dotcom_connection_enabled?).returns(true)

          # Disabled on GHES
          disable_feature_flag(:custom_enterprise_role_feature, @business)
          disable_feature_flag(:enterprise_custom_organization_roles, @business)

          # For the sub-menu items under "Code security"
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @owner,
              business: @business,
              sidebar_section: :policies,
            ),
            allowed_queries: 3,
          )

          assert_test_selector("policies-sidebar")
          assert_selector("a", text: "Member privileges")
          assert_selector("a", text: "Projects")
          assert_selector("a", text: "Options")
          assert_selector("a", text: "Advanced Security")
          assert_selector("a", text: "Personal access tokens")
        end

        test "code security" do
          GitHub.stubs(:dotcom_connection_enabled?).returns(true)

          # Disabled on GHES
          disable_feature_flag(:custom_enterprise_role_feature, @business)
          disable_feature_flag(:enterprise_custom_organization_roles, @business)

          # For the sub-menu items under "Code security"
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @owner,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 3,
          )

          assert_test_selector("security-sidebar")
          assert_selector("a", text: "Overview")
          assert_selector("a", text: "Risk")
          assert_selector("a", text: "Coverage")
          assert_selector("a", text: "Enablement trends")
          assert_selector("a", text: "CodeQL pull request alerts")
          assert_selector("a", text: "Secret scanning metrics")
          assert_selector("a", text: "Dependabot alerts")
          assert_selector("a", text: "Code scanning alerts")
          assert_selector("a", text: "Secret scanning alerts")
        end

        test "settings" do
          GitHub.stubs(:dotcom_connection_enabled?).returns(true)

          # Disabled on GHES
          disable_feature_flag(:custom_enterprise_role_feature, @business)
          disable_feature_flag(:enterprise_custom_organization_roles, @business)

          # For the sub-menu items under "Code security"
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @owner,
              business: @business,
              sidebar_section: :settings,
            ),
            allowed_queries: 3,
          )

          assert_test_selector("settings-sidebar")
          assert_selector("a", text: "Profile")
          assert_selector("a", text: "License")
          assert_selector("a", text: "Authentication security")
          assert_selector("a", text: "Advanced Security")
          assert_selector("a", text: "Verified & approved domains")
          assert_selector("a", text: "Audit log")
          assert_selector("a", text: "Hooks")
          assert_selector("a", text: "Messages")
          assert_selector("a", text: "Site admin")
        end
      end

      context "renders 'Code security' menu and sub-menu items appropriately on GHES as GHAS features are enabled/disabled on the instance" do
        test "with all security features enabled" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
          tab = tabs_builder.tabs.find { |tab| tab.text == "Security" }
          assert tab

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @owner,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 3,
          )

          assert_test_selector("security-sidebar")
          assert_selector("a", text: "Overview")
          assert_selector("a", text: "Enablement trends")
          assert_selector("a", text: "CodeQL pull request alerts")
          assert_selector("a", text: "Secret scanning metrics")
          assert_selector("a", text: "Risk")
          assert_selector("a", text: "Coverage")
          assert_selector("a", text: "Secret scanning alerts")
          assert_selector("a", text: "Code scanning alerts")
          assert_selector("a", text: "Dependabot alerts")
        end
      end

      test "with code scanning alerts disabled" do
        SecurityCenter::SecurityFeatures.stubs(
          code_scanning_enabled_for_instance?: false,
          secret_scanning_enabled_for_instance?: true,
          dependabot_alerts_enabled_for_instance?: true,
        )

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
        tab = tabs_builder.tabs.find { |tab| tab.text == "Security" }
        assert tab

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :code_security,
          ),
          allowed_queries: 3,
        )

        assert_test_selector("security-sidebar")
        assert_selector("a", text: "Overview")
        assert_selector("a", text: "Enablement trends")
        assert_selector("a", text: "Secret scanning metrics")
        assert_selector("a", text: "Risk")
        assert_selector("a", text: "Coverage")
        assert_selector("a", text: "Secret scanning alerts")
        assert_selector("a", text: "Dependabot alerts")

        refute_selector("a", text: "Code scanning alerts")
      end

      test "with secret scanning alerts disabled" do
        SecurityCenter::SecurityFeatures.stubs(
          code_scanning_enabled_for_instance?: true,
          dependabot_alerts_enabled_for_instance?: true,
        )
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :code_security,
          ),
          allowed_queries: 3,
        )

        assert_test_selector("security-sidebar")
        assert_selector("a", text: "Overview")
        assert_selector("a", text: "Enablement trends")
        assert_selector("a", text: "CodeQL pull request alerts")
        assert_selector("a", text: "Risk")
        assert_selector("a", text: "Coverage")
        assert_selector("a", text: "Code scanning alerts")
        assert_selector("a", text: "Dependabot alerts")

        refute_selector("a", text: "Secret scanning alerts")
      end

      test "with dependabot alerts disabled" do
        SecurityCenter::SecurityFeatures.stubs(
          code_scanning_enabled_for_instance?: true,
          dependabot_alerts_enabled_for_instance?: false,
        )
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :code_security,
          ),
          allowed_queries: 3,
        )
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
        assert_test_selector("security-sidebar")
        assert_selector("a", text: "Overview")
        assert_selector("a", text: "Enablement trends")
        assert_selector("a", text: "CodeQL pull request alerts")
        assert_selector("a", text: "Secret scanning metrics")
        assert_selector("a", text: "Risk")
        assert_selector("a", text: "Coverage")
        assert_selector("a", text: "Secret scanning alerts")
        assert_selector("a", text: "Code scanning alerts")

        refute_selector("a", text: "Dependabot alerts")
      end

      test "with all security features disabled" do
        SecurityCenter::SecurityFeatures.stubs(
          code_scanning_enabled_for_instance?: false,
          dependabot_alerts_enabled_for_instance?: false,
        )
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :code_security,
          ),
          allowed_queries: 3,
        )
        assert_test_selector("security-sidebar")
        assert_selector("a", text: "Overview")
        assert_selector("a", text: "Enablement trends")
        assert_selector("a", text: "Risk")
        assert_selector("a", text: "Coverage")

        refute_selector("a", text: "Secret scanning metrics")
        refute_selector("a", text: "Code scanning alerts")
        refute_selector("a", text: "Dependabot alerts")
      end
    end

    context "when current_user is a member" do
      test "renders menu items appropriately on GHES" do
        GitHub.stubs(:dotcom_connection_enabled?).returns(true)

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @member)
        actual_tabs = tabs_builder.tabs.map(&:text)

        assert_equal %w[Overview Organizations Security], actual_tabs
      end

      context "renders 'Code security' menu and sub-menu items appropriately on GHES as GHAS features are enabled/disabled on the instance" do
        test "with all security features enabled" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          tabs_builder = Business::NavigationTabs.new(@business, current_user: @member)
          tab = tabs_builder.tabs.find { |tab| tab.text == "Security" }
          assert tab

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @member,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 3,
          )

          assert_test_selector("security-sidebar")
          assert_selector("a", text: "Overview")
          assert_selector("a", text: "Enablement trends")
          assert_selector("a", text: "CodeQL pull request alerts")
          assert_selector("a", text: "Secret scanning metrics")
          assert_selector("a", text: "Risk")
          assert_selector("a", text: "Coverage")
          assert_selector("a", text: "Secret scanning alerts")
          assert_selector("a", text: "Code scanning alerts")
          assert_selector("a", text: "Dependabot alerts")
        end

        test "with code scanning alerts disabled" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: false,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          tabs_builder = Business::NavigationTabs.new(@business, current_user: @member)
          tab = tabs_builder.tabs.find { |tab| tab.text == "Security" }
          assert tab

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @member,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 3,
          )

          assert_test_selector("security-sidebar")
          assert_selector("a", text: "Overview")
          assert_selector("a", text: "Enablement trends")
          assert_selector("a", text: "Secret scanning metrics")
          assert_selector("a", text: "Risk")
          assert_selector("a", text: "Coverage")
          assert_selector("a", text: "Secret scanning alerts")
          assert_selector("a", text: "Dependabot alerts")

          refute_selector("a", text: "Code scanning alerts")
        end

        test "with secret scanning alerts disabled" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )
          GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @member,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 3,
          )

          assert_test_selector("security-sidebar")
          assert_selector("a", text: "Overview")
          assert_selector("a", text: "Enablement trends")
          assert_selector("a", text: "CodeQL pull request alerts")
          assert_selector("a", text: "Risk")
          assert_selector("a", text: "Coverage")
          assert_selector("a", text: "Code scanning alerts")
          assert_selector("a", text: "Dependabot alerts")

          refute_selector("a", text: "Secret scanning alerts")
        end

        test "with dependabot alerts disabled" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: false,
          )
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @member,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 3,
          )
          GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
          assert_test_selector("security-sidebar")
          assert_selector("a", text: "Overview")
          assert_selector("a", text: "Enablement trends")
          assert_selector("a", text: "CodeQL pull request alerts")
          assert_selector("a", text: "Secret scanning metrics")
          assert_selector("a", text: "Risk")
          assert_selector("a", text: "Coverage")
          assert_selector("a", text: "Secret scanning alerts")
          assert_selector("a", text: "Code scanning alerts")

          refute_selector("a", text: "Dependabot alerts")
        end

        test "with all security features disabled" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: false,
            dependabot_alerts_enabled_for_instance?: false,
          )
          GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @member,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 3,
          )
          assert_test_selector("security-sidebar")
          assert_selector("a", text: "Overview")
          assert_selector("a", text: "Enablement trends")
          assert_selector("a", text: "Risk")
          assert_selector("a", text: "Coverage")

          refute_selector("a", text: "Secret scanning metrics")
          refute_selector("a", text: "Code scanning alerts")
          refute_selector("a", text: "Dependabot alerts")
        end
      end
    end

    context "when current_user is an enterprise security manager" do
      context "renders menu and sub menu items appropriately on GHES" do
        test "renders menu items appropriately on GHES" do
          # For the sub-menu items under "Code security"
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          tabs_builder = Business::NavigationTabs.new(@business, current_user: @enterprise_security_manager)
          actual_tabs = tabs_builder.tabs.map(&:text)

          assert_equal %w[Overview Organizations Policies Security Settings], actual_tabs
        end

        test "policies" do
          # For the sub-menu items under "Code security"
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :policies,
            ),
            allowed_queries: 3,
          )
          assert_test_selector("policies-sidebar")
          assert_selector("a", text: "Advanced Security")
        end

        test "code security" do
          # For the sub-menu items under "Code security"
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 3,
          )
          assert_test_selector "security-sidebar"
          assert_selector "a", text: "Overview"
          assert_selector "a", text: "Risk"
          assert_selector "a", text: "Coverage"
          assert_selector "a", text: "Enablement trends"
          assert_selector "a", text: "CodeQL pull request alerts"
          assert_selector "a", text: "Secret scanning metrics"
          assert_selector "a", text: "Dependabot alerts"
          assert_selector "a", text: "Code scanning alerts"
          assert_selector "a", text: "Secret scanning alerts"
        end

        test "settings" do
          # For the sub-menu items under "Code security"
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :settings,
            ),
            allowed_queries: 3,
          )
          assert_test_selector "settings-sidebar"
          assert_selector "a", text: "Advanced Security"
        end
      end

      context "renders 'Code security' menu and sub-menu items appropriately on GHES as GHAS features are enabled/disabled on the instance" do
        test "with all security features enabled" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          tabs_builder = Business::NavigationTabs.new(@business, current_user: @enterprise_security_manager)
          tab = tabs_builder.tabs.find { |tab| tab.text == "Security" }
          assert tab

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 3,
          )

          assert_test_selector("security-sidebar")
          assert_selector("a", text: "Overview")
          assert_selector("a", text: "Enablement trends")
          assert_selector("a", text: "CodeQL pull request alerts")
          assert_selector("a", text: "Secret scanning metrics")
          assert_selector("a", text: "Risk")
          assert_selector("a", text: "Coverage")
          assert_selector("a", text: "Secret scanning alerts")
          assert_selector("a", text: "Code scanning alerts")
          assert_selector("a", text: "Dependabot alerts")
        end

        test "with code scanning alerts disabled" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: false,
            secret_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )

          tabs_builder = Business::NavigationTabs.new(@business, current_user: @member)
          tab = tabs_builder.tabs.find { |tab| tab.text == "Security" }
          assert tab

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 3,
          )

          assert_test_selector("security-sidebar")
          assert_selector("a", text: "Overview")
          assert_selector("a", text: "Enablement trends")
          assert_selector("a", text: "Secret scanning metrics")
          assert_selector("a", text: "Risk")
          assert_selector("a", text: "Coverage")
          assert_selector("a", text: "Secret scanning alerts")
          assert_selector("a", text: "Dependabot alerts")

          refute_selector("a", text: "Code scanning alerts")
        end

        test "with secret scanning alerts disabled" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: true,
          )
          GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 3,
          )

          assert_test_selector("security-sidebar")
          assert_selector("a", text: "Overview")
          assert_selector("a", text: "Enablement trends")
          assert_selector("a", text: "CodeQL pull request alerts")
          assert_selector("a", text: "Risk")
          assert_selector("a", text: "Coverage")
          assert_selector("a", text: "Code scanning alerts")
          assert_selector("a", text: "Dependabot alerts")

          refute_selector("a", text: "Secret scanning alerts")
        end

        test "with dependabot alerts disabled" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: true,
            dependabot_alerts_enabled_for_instance?: false,
          )
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 3,
          )
          GitHub.stubs(:configuration_secret_scanning_enabled?).returns(true)
          assert_test_selector("security-sidebar")
          assert_selector("a", text: "Overview")
          assert_selector("a", text: "Enablement trends")
          assert_selector("a", text: "CodeQL pull request alerts")
          assert_selector("a", text: "Secret scanning metrics")
          assert_selector("a", text: "Risk")
          assert_selector("a", text: "Coverage")
          assert_selector("a", text: "Secret scanning alerts")
          assert_selector("a", text: "Code scanning alerts")

          refute_selector("a", text: "Dependabot alerts")
        end

        test "with all security features disabled" do
          SecurityCenter::SecurityFeatures.stubs(
            code_scanning_enabled_for_instance?: false,
            dependabot_alerts_enabled_for_instance?: false,
          )
          GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 3,
          )
          assert_test_selector("security-sidebar")
          assert_selector("a", text: "Overview")
          assert_selector("a", text: "Enablement trends")
          assert_selector("a", text: "Risk")
          assert_selector("a", text: "Coverage")

          refute_selector("a", text: "Secret scanning metrics")
          refute_selector("a", text: "Code scanning alerts")
          refute_selector("a", text: "Dependabot alerts")
        end
      end
    end
  else
    # Not GHES
    context "Insights" do
      test "show insights tab when feature is on and user an owner" do
        enable_feature_flag(:actions_usage_metrics)
        enable_feature_flag(:actions_usage_metrics_enterprise)
        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)

        tab = tabs_builder.tabs.find { |tab| tab.text == "Insights" }

        assert tab
      end

      test "hide insights tab when feature is off" do
        enable_feature_flag(:new_ea_creation_from_coupon)
        disable_feature_flag(:actions_usage_metrics_enterprise)
        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)

        tab = tabs_builder.tabs.find { |tab| tab.text == "Insights" }

        assert_nil tab
      end

      test "hide insights tab when not an owner" do
        enable_feature_flag(:new_ea_creation_from_coupon)
        enable_feature_flag(:actions_usage_metrics_enterprise)
        tabs_builder = Business::NavigationTabs.new(@business, current_user: @member)

        tab = tabs_builder.tabs.find { |tab| tab.text == "Insights" }

        assert_nil tab
      end
    end

    context "People with FGP" do
      test "shows people tab for member with read_enterprise_admins_and_members" do
        enable_feature_flag(:custom_enterprise_role_feature, @business)
        enable_feature_flag(:support_enterprise_admins_and_members, @business)
        grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_admins_and_members])

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @member)
        tab = tabs_builder.tabs.find { |tab| tab.text == "People" }
        assert_equal urls.people_enterprise_path(@business), tab.href
      end
    end

    context "when current_user is an owner" do
      test "renders menu items appropriately on dotcom when business is basic plan" do
        @business.update_attribute(:seats_plan_type, :basic)

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
        actual_tabs = tabs_builder.tabs.map(&:text)

        if TestEnv.test_with_all_emus?
          assert_equal ["Overview", "Getting started", "People", "Identity provider", "Policies", "Settings", "Compliance"], actual_tabs
        else
          assert_equal ["Overview", "Getting started", "People", "Policies", "Settings", "Compliance"], actual_tabs
        end

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :policies,
          ),
          allowed_queries: 2,
        )
        assert_test_selector("policies-sidebar")
        assert_selector("a", text: /Copilot/)
      end

      test "does not render repository collaborators for basic" do
        @business.update_attribute(:seats_plan_type, :basic)

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :people,
          ),
          allowed_queries: 1,
        )
        assert_test_selector("people-sidebar")
        refute_selector("a", text: (@business.emu_repository_collaborators_enabled? ? "repository collaborators" : GitHub.outside_collaborators_flavor).capitalize)
      end

      test "renders menu items appropriately on dotcom when business is invoiced" do
        @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_INVOICE)

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
        actual_tabs = tabs_builder.tabs.map(&:text)

        if TestEnv.test_with_all_emus?
          assert_equal ["Overview", "Organizations", "People", "Identity provider", "Policies", "GitHub Connect", "Security", "Settings", "Compliance"], actual_tabs
        else
          assert_equal ["Overview", "Organizations", "People", "Policies", "GitHub Connect", "Security", "Settings", "Compliance"], actual_tabs
        end
      end

      test "renders menu items appropriately for business on proxima" do
        @business.customer.update_attribute(:billing_type, nil)

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
        actual_tabs = tabs_builder.tabs.map(&:text)

        assert_equal ["Overview", "Organizations", "People", "Identity provider", "Policies", "GitHub Connect", "Security", "Settings", "Compliance"], actual_tabs
      end if TestEnv.test_in_multitenancy_mode?

      test "renders menu items appropriately on dotcom when business is not invoiced" do
        @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
        actual_tabs = tabs_builder.tabs.map(&:text)

        if TestEnv.test_with_all_emus?
          assert_equal ["Overview", "Organizations", "People", "Identity provider", "Policies", "Security", "Settings", "Compliance"], actual_tabs
        else
          assert_equal %w[Overview Organizations People Policies Security Settings Compliance], actual_tabs
        end
      end

      test "renders menu items appropriately on dotcom when the business hasn't purchased GHAS" do
        Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
        actual_tabs = tabs_builder.tabs.map(&:text)

        if TestEnv.test_with_all_emus?
          assert_equal ["Overview", "Organizations", "People", "Identity provider", "Policies", "GitHub Connect", "Security", "Settings", "Compliance"], actual_tabs
        else
          assert_equal ["Overview", "Organizations", "People", "Policies", "GitHub Connect", "Security", "Settings", "Compliance"], actual_tabs
        end
      end

      test "renders menu items appropriately on dotcom when business downgraded to free plan" do
        @business.downgrade_to_free_plan
        @business.reload
        assert_predicate @business, :downgraded_to_free_plan?

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
        actual_tabs = tabs_builder.tabs.map(&:text)

        assert_equal %w[Overview Organizations People Settings], actual_tabs
      end

      test "renders menu items appropriately for business created from upgrade of ghec org, and business is downgraded to free plan" do
        direct_upgraded_business = create :business, \
          :with_self_serve_payment,
          owners: @business_plus_org.admins,
          name: "Upgraded from a business plus org",
          upgraded_at: 2.days.ago,
          upgraded_from: @business_plus_org,
          upgraded_from_plan: @business_plus_org.plan.name
        direct_upgraded_business.organization_direct_upgraded!
        direct_upgraded_business.set_org_upgrade_onboarding_notice(
          initiating_owner: @owner, organization: @business_plus_org
        )

        direct_upgraded_business.downgrade_to_free_plan
        assert_predicate direct_upgraded_business.reload, :organization_direct_upgraded?
        assert_predicate direct_upgraded_business, :upgraded_from_organization?
        refute @owner.dismissed_business_notice?("org_upgrade_onboarding", business_id: direct_upgraded_business.id)
        assert_predicate direct_upgraded_business, :downgraded_to_free_plan?

        tabs_builder = Business::NavigationTabs.new(direct_upgraded_business, current_user: @owner)
        actual_tabs = tabs_builder.tabs.map(&:text)

        assert_equal %w[Overview Organizations People Settings], actual_tabs
      end

      test "renders menu items appropriately on dotcom when enterprise is in trial" do
        @business.update_attribute :trial_expires_at, 5.days.from_now
        @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)
        @business.reload
        assert_predicate @business, :trial?
        refute_predicate @business, :downgraded_to_free_plan?
        refute_predicate @business, :trial_expired?

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
        actual_tabs = tabs_builder.tabs.map(&:text)

        if TestEnv.test_with_all_emus?
          assert_equal ["Overview", "Getting started", "Organizations", "People", "Identity provider", "Policies", "Security", "Settings", "Compliance"], actual_tabs
        else
          assert_equal ["Overview", "Getting started", "Organizations", "People", "Policies", "Security", "Settings", "Compliance"], actual_tabs
        end
      end

      test "renders menu items appropriately on dotcom when enterprise trial has expired" do
        @business.update_attribute :trial_expires_at, 1.day.ago
        @business.downgrade_to_free_plan
        @business.reload
        assert_predicate @business, :downgraded_to_free_plan?
        assert_predicate @business, :trial_expired?

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
        actual_tabs = tabs_builder.tabs.map(&:text)

        assert_equal ["Overview", "Upgrade to GitHub Enterprise", "Organizations", "People", "Settings"], actual_tabs
      end

      test "renders menu items appropriately on dotcom for trial metered plan business" do
        @business.update_attribute :trial_expires_at, 5.days.from_now
        @business.customer.update metered_ghe: true
        assert_predicate @business.reload, :metered_plan?
        refute @business.metered_ghes_eligible?

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
        actual_tabs = tabs_builder.tabs.map(&:text)

        if TestEnv.test_with_all_emus?
          assert_equal ["Overview", "Getting started", "Organizations", "People", "Identity provider", "Policies", "Security", "Settings", "Compliance"], actual_tabs
        else
          assert_equal ["Overview", "Getting started", "Organizations", "People", "Policies", "Security", "Settings", "Compliance"], actual_tabs
        end
      end

      test "doesn't render getting started menu if kv is not available" do
        BusinessesHelper.stubs(:show_onboarding_experience?).raises(ActiveRecord::ActiveRecordError.new)

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
        actual_tabs = tabs_builder.tabs.map(&:text)

        if TestEnv.test_with_all_emus?
          assert_equal ["Overview", "Organizations", "People", "Identity provider", "Policies", "GitHub Connect", "Security", "Settings", "Compliance"], actual_tabs
        else
          assert_equal ["Overview", "Organizations", "People", "Policies", "GitHub Connect", "Security", "Settings", "Compliance"], actual_tabs
        end
      end

      context "renders sub-menu items appropriately on dotcom" do
        test "people" do
          EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true) if TestEnv.test_all_features?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @owner,
              business: @business,
              sidebar_section: :people,
            ),
            allowed_queries: 1,
          )
          assert_test_selector("people-sidebar")
          assert_selector("a", text: "Members")
          assert_selector("a", text: "Administrators")
          assert_selector("a", text: "Role assignments")
          assert_selector("a", text: "Role management")
          assert_selector("a", text: "Organization roles")

          unless TestEnv.test_with_all_emus?
            assert_selector("a", text: (@business.emu_repository_collaborators_enabled? ? "repository collaborators" : GitHub.outside_collaborators_flavor).capitalize)
            assert_selector("a", text: "Invitations")
            assert_selector("a", text: "Failed invitations")
          end

          if @business.feature_enabled?(:enterprise_teams_enabled_for_organizations)
            EnterpriseTeam.stubs(:enabled_for_organization_security_manager?).returns(true)
            assert_selector("a", text: "Enterprise teams")
            assert_selector("a", text: "Security managers")
          end

          if TestEnv.test_with_all_emus?
            assert_selector("a", text: "Suspended")
          end
        end

        test "policies" do
          EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true) if TestEnv.test_all_features?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @owner,
              business: @business,
              sidebar_section: :policies,
            ),
            allowed_queries: 3,
          )
          assert_test_selector("policies-sidebar")
          assert_selector("a", text: "Member privileges")
          assert_selector("a", text: "Codespaces")
          assert_selector("a", text: "Actions")
          assert_selector("a", text: "Projects")
          assert_selector("a", text: "Advanced Security")
          assert_selector("a", text: "Copilot")
          assert_selector("a", text: "Personal access tokens")
          assert_selector("a", text: "Hosted compute networking")

          if @owner.feature_enabled?(:sponsors_self_serve_enterprise)
            assert_selector("a", text: "Sponsors")
          end

          if CustomProperties::Public.enterprise_properties_enabled?(@business)
            assert_selector("a", text: "Custom properties")
          end

          if @business.enterprise_rulesets_enabled?
            assert_selector("a", text: "Repository")
            assert_selector("a", text: "Code")
            assert_selector("a", text: "Code insights")
            assert_selector("a", text: "Code ruleset bypasses")
          end
        end

        test "code security" do
          EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true) if TestEnv.test_all_features?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @owner,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 1,
          )
          assert_test_selector("security-sidebar")
          assert_selector("a", text: "Overview")
          assert_selector("a", text: "Risk")
          assert_selector("a", text: "Coverage")
          assert_selector("a", text: "Enablement trends")
          assert_selector("a", text: "CodeQL pull request alerts")
          assert_selector("a", text: "Secret scanning metrics")
          assert_selector("a", text: "Dependabot alerts")
          assert_selector("a", text: "Code scanning alerts")
          assert_selector("a", text: "Secret scanning alerts")
        end

        test "settings" do
          EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true) if TestEnv.test_all_features?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @owner,
              business: @business,
              sidebar_section: :settings,
            ),
            allowed_queries: 3,
          )
          assert_test_selector("settings-sidebar")

          assert_selector("a", text: "Profile")
          assert_selector("a", text: "Billing")
          assert_selector("a", text: "Enterprise licensing")
          assert_selector("a", text: "Authentication security")
          assert_selector("a", text: "Advanced Security")
          assert_selector("a", text: "Verified & approved domains")
          assert_selector("a", text: "Audit log")
          assert_selector("a", text: "Hooks")
          assert_selector("a", text: "Hosted compute networking")
          assert_selector("a", text: "Support")
          assert_selector("a", text: "Announcement")
          assert_selector("a", text: "GitHub Apps")

        end
      end unless TestEnv.test_in_multitenancy_mode?

      context "renders sub-menu items appropriately on dotcom when Limited Security Center is available" do
        test "code security" do
          EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true) if TestEnv.test_all_features?
          GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @owner,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 1,
          )
          assert_test_selector("security-sidebar")
          assert_selector("a", text: "Overview")
          assert_selector("a", text: "Risk")
          assert_selector("a", text: "Coverage")
          assert_selector("a", text: "Enablement trends")
          assert_selector("a", text: "CodeQL pull request alerts")
          assert_selector("a", text: "Dependabot alerts")
          assert_selector("a", text: "Code scanning alerts")
        end
      end unless TestEnv.test_in_multitenancy_mode?

      context "renders sub-menu items appropriately on dotcom when business downgraded to free plan" do
        test "people" do
          EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true) if TestEnv.test_all_features?
          @business.downgrade_to_free_plan
          @business.reload
          assert_predicate @business, :downgraded_to_free_plan?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @owner,
              business: @business,
              sidebar_section: :people,
            ),
            allowed_queries: 1,
          )
          assert_test_selector("people-sidebar")
          assert_selector("a", text: "Members")
          assert_selector("a", text: "Administrators")

          unless TestEnv.test_with_all_emus?
            assert_selector("a", text: (@business.emu_repository_collaborators_enabled? ? "repository collaborators" : GitHub.outside_collaborators_flavor).capitalize)
            assert_selector("a", text: "Invitations")
            assert_selector("a", text: "Failed invitations")
          end

          if @business.feature_enabled?(:enterprise_teams_enabled_for_organizations)
            EnterpriseTeam.stubs(:enabled_for_organization_security_manager?).returns(true)
            assert_selector("a", text: "Enterprise teams")
            assert_selector("a", text: "Security managers")
          end

          if TestEnv.test_with_all_emus?
            assert_selector("a", text: "Suspended")
          end
        end

        test "settings" do
          EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true) if TestEnv.test_all_features?
          @business.downgrade_to_free_plan
          @business.reload
          assert_predicate @business, :downgraded_to_free_plan?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @owner,
              business: @business,
              sidebar_section: :settings,
            ),
            allowed_queries: 3,
          )
          assert_test_selector("settings-sidebar")

          assert_selector("a", text: "Profile")
          assert_selector("a", text: "Billing")
          assert_selector("a", text: "Enterprise licensing")
          assert_selector("a", text: "Authentication security")
          assert_selector("a", text: "Advanced Security")
          assert_selector("a", text: "Verified & approved domains")
          assert_selector("a", text: "Audit log")
          assert_selector("a", text: "Hooks")
          assert_selector("a", text: "Support")
          assert_selector("a", text: "Announcement")
          assert_selector("a", text: "GitHub Apps")
        end
      end unless TestEnv.test_in_multitenancy_mode?

      test "does not render Actions sub-menu under Policies on dotcom if disabled" do
        GitHub.stubs(:actions_enabled?).returns(false)
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :policies,
          ),
          allowed_queries: 3,
        )
        assert_test_selector("policies-sidebar")
        assert_selector("a", text: "Member privileges")
        assert_selector("a", text: "Codespaces")
        refute_selector("a", text: "Actions")
        assert_selector("a", text: "Projects")
        assert_selector("a", text: "Advanced Security")
        assert_selector("a", text: "Copilot")
        assert_selector("a", text: "Personal access tokens")
        assert_selector("a", text: "Hosted compute networking")

        if @owner.feature_enabled?(:sponsors_self_serve_enterprise)
          assert_selector("a", text: "Sponsors")
        end

        if CustomProperties::Public.enterprise_properties_enabled?(@business)
          assert_selector("a", text: "Custom properties")
        end

        if @business.enterprise_rulesets_enabled?
          assert_selector("a", text: "Repository")
          assert_selector("a", text: "Code")
          assert_selector("a", text: "Code insights")
          assert_selector("a", text: "Code ruleset bypasses")
        end
      end

      test "renders Hosted compute networking sub-menu under Policies when enabled for the business" do
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true) if TestEnv.test_all_features?
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :policies,
          ),
          allowed_queries: 3,
        )
        assert_test_selector("policies-sidebar")
        assert_selector("a", text: "Member privileges")
        assert_selector("a", text: "Codespaces")
        assert_selector("a", text: "Actions")
        assert_selector("a", text: "Projects")
        assert_selector("a", text: "Advanced Security")
        assert_selector("a", text: "Copilot")
        assert_selector("a", text: "Personal access tokens")
        assert_selector("a", text: "Hosted compute networking")

        if @owner.feature_enabled?(:sponsors_self_serve_enterprise)
          assert_selector("a", text: "Sponsors")
        end

        if CustomProperties::Public.enterprise_properties_enabled?(@business)
          assert_selector("a", text: "Custom properties")
        end

        if @business.enterprise_rulesets_enabled?
          assert_selector("a", text: "Repository")
          assert_selector("a", text: "Code")
          assert_selector("a", text: "Code insights")
          assert_selector("a", text: "Code ruleset bypasses")
        end
      end

      test "renders Copilot sub-menu under Policies when enabled for the business" do
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :policies,
          ),
          allowed_queries: 3,
        )
        assert_test_selector("policies-sidebar")
        assert_selector("a", text: "Member privileges")
        assert_selector("a", text: "Codespaces")
        assert_selector("a", text: "Actions")
        assert_selector("a", text: "Projects")
        assert_selector("a", text: "Advanced Security")
        assert_selector("a", text: "Copilot")
        assert_selector("a", text: "Personal access tokens")
        assert_selector("a", text: "Hosted compute networking")

        if @owner.feature_enabled?(:sponsors_self_serve_enterprise)
          assert_selector("a", text: "Sponsors")
        end

        if CustomProperties::Public.enterprise_properties_enabled?(@business)
          assert_selector("a", text: "Custom properties")
        end

        if @business.enterprise_rulesets_enabled?
          assert_selector("a", text: "Repository")
          assert_selector("a", text: "Code")
          assert_selector("a", text: "Code insights")
          assert_selector("a", text: "Code ruleset bypasses")
        end
      end

      test "render Copilot sub-menu under Policies when enabled for the business and on trial" do
        trial = Copilot::BusinessTrial.create_trial!(
          @org,
          @org.admins.first,
          trial_length: 10,
        )
        trial.start_trial!
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :policies,
          ),
          allowed_queries: 3,
        )
        assert_test_selector("policies-sidebar")
        assert_selector("a", text: "Member privileges")
        assert_selector("a", text: "Codespaces")
        assert_selector("a", text: "Actions")
        assert_selector("a", text: "Projects")
        assert_selector("a", text: "Advanced Security")
        assert_selector("a", text: "Copilot")
        assert_selector("a", text: "Personal access tokens")
        assert_selector("a", text: "Hosted compute networking")

        if @owner.feature_enabled?(:sponsors_self_serve_enterprise)
          assert_selector("a", text: "Sponsors")
        end

        if CustomProperties::Public.enterprise_properties_enabled?(@business)
          assert_selector("a", text: "Custom properties")
        end

        if @business.enterprise_rulesets_enabled?
          assert_selector("a", text: "Repository")
          assert_selector("a", text: "Code")
          assert_selector("a", text: "Code insights")
          assert_selector("a", text: "Code ruleset bypasses")
        end
      end

      test "renders copilot policy menu items appropriately when business is basic" do
        @business.update_attribute(:seats_plan_type, :basic)
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :policies,
          ),
          allowed_queries: 2
        )
        assert_test_selector("policies-sidebar")
        assert_selector("a", text: "Copilot Business")
      end if TestEnv.test_with_all_emus? && !GitHub.enterprise?

      test "does not render Copilot sub-menu under Policies when enterprise is trial" do
        trial_business = create(:business, owners: [@owner], trial_expires_at: 3.days.from_now)
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: trial_business,
            sidebar_section: :policies,
          ),
          allowed_queries: 3
        )
        assert_test_selector("policies-sidebar")
        refute_selector("a", text: "Copilot")
      end unless TestEnv.test_with_all_emus?

      test "render Copilot sub-menu under Policies when enabled for the business trial upgraded" do
        trial = Copilot::BusinessTrial.create_trial!(
          @org,
          @org.admins.first,
          trial_length: 10,
        )
        trial.start_trial!
        Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
        trial.upgrade!(create(:user))
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :policies,
          ),
          allowed_queries: 3
        )
        assert_test_selector("policies-sidebar")
        assert_selector("a", text: "Copilot")
      end unless TestEnv.test_with_all_emus?

      test "renders Codespaces sub-menu under Policies when enabled for the business" do
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :policies,
          ),
          allowed_queries: 3
        )
        assert_test_selector("policies-sidebar")
        assert_selector("a", text: "Codespaces")
      end

      test "only renders the Overview and Organizations tabs when the business was created from a Free- or Teams-plan upgrade, and payment has not been initiated", skip_with_all_emus: true do
        upgraded_business = create :business, owners: [@owner]
        upgraded_business.initiate_organization_upgrade
        assert_predicate upgraded_business, :organization_upgrade_initiated?

        tabs_builder = Business::NavigationTabs.new(upgraded_business, current_user: @owner)
        actual_tabs = tabs_builder.tabs.map(&:text)

        assert_equal %w[Overview Organizations], actual_tabs
      end

      test "only renders the Overview and Organizations tabs when the business was created from a Free- or Teams-plan upgrade, and payment has been initiated", skip_with_all_emus: true do
        upgraded_business = create :business, owners: [@owner]
        upgraded_business.initiate_organization_upgrade
        assert_predicate upgraded_business, :organization_upgrade_initiated?

        upgraded_business.initiate_organization_upgrade_purchase
        assert_predicate upgraded_business, :organization_upgrade_purchase_initiated?

        tabs_builder = Business::NavigationTabs.new(upgraded_business, current_user: @owner)
        actual_tabs = tabs_builder.tabs.map(&:text)

        assert_equal %w[Overview Organizations], actual_tabs
      end

      test "renders the getting started tab when business has been upgraded from free- or teams-plan org and user has not dismissed onboarding", skip_with_all_emus: true do
        upgraded_business = create :business, owners: [@owner]
        upgraded_business.initiate_organization_upgrade
        upgraded_business.customer.update(billing_type: ::Customer::BILLING_TYPE_CARD)
        upgraded_business.initiate_organization_upgrade_purchase
        upgraded_business.upgrade_from_organization
        assert_predicate upgraded_business, :organization_upgrade_completed?
        assert_predicate upgraded_business, :upgraded_from_organization?
        refute @owner.dismissed_business_notice?("org_upgrade_onboarding", business_id: upgraded_business.id)

        tabs_builder = Business::NavigationTabs.new(upgraded_business, current_user: @owner)

        tab = tabs_builder.tabs.find { |tab| tab.text == "Getting started" }
        assert_equal urls.enterprise_getting_started_path(upgraded_business), tab.href
      end

      test "does not render the getting started tab when business has been upgraded from free- or teams-plan org and user has dismissed onboarding", skip_with_all_emus: true do
        upgraded_business = create :business, owners: [@owner]
        upgraded_business.initiate_organization_upgrade
        upgraded_business.customer.update(billing_type: ::Customer::BILLING_TYPE_CARD)
        upgraded_business.initiate_organization_upgrade_purchase
        upgraded_business.upgrade_from_organization
        assert_predicate upgraded_business, :organization_upgrade_completed?
        assert_predicate upgraded_business, :upgraded_from_organization?
        @owner.dismiss_business_notice("org_upgrade_onboarding", business_id: upgraded_business.id)
        assert @owner.dismissed_business_notice?("org_upgrade_onboarding", business_id: upgraded_business.id)

        tabs_builder = Business::NavigationTabs.new(upgraded_business, current_user: @owner)
        tab = tabs_builder.tabs.find { |tab| tab.text == "Getting started" }
        refute tab
      end

      test "does not render the getting started tab when business has been upgraded from free- or teams-plan org but notice was never set on user", skip_with_all_emus: true do
        upgraded_business = create :business, owners: [@owner]
        upgraded_business.initiate_organization_upgrade
        upgraded_business.customer.update(billing_type: ::Customer::BILLING_TYPE_CARD)
        upgraded_business.initiate_organization_upgrade_purchase
        upgraded_business.upgrade_from_organization
        assert_predicate upgraded_business, :organization_upgrade_completed?
        assert_predicate upgraded_business, :upgraded_from_organization?
        second_owner = create :user
        upgraded_business.add_owner(second_owner, actor: @owner)
        refute second_owner.dismissed_business_notice?("org_upgrade_onboarding", business_id: upgraded_business.id)
        refute upgraded_business.org_upgrade_onboarding_notice_set?(second_owner)

        tabs_builder = Business::NavigationTabs.new(upgraded_business, current_user: second_owner)
        tab = tabs_builder.tabs.find { |tab| tab.text == "Getting started" }
        refute tab
      end

      test "renders the getting started tab when business has been upgraded from a GHEC-org and user has not dismissed onboarding", skip_with_all_emus: true do
        direct_upgraded_business = create :business, \
          :with_self_serve_payment,
          owners: @business_plus_org.admins,
          name: "Upgraded from a business plus org",
          upgraded_at: 2.days.ago,
          upgraded_from: @business_plus_org,
          upgraded_from_plan: @business_plus_org.plan.name
        direct_upgraded_business.organization_direct_upgraded!
        direct_upgraded_business.set_org_upgrade_onboarding_notice(
          initiating_owner: @owner, organization: @business_plus_org
        )

        assert_predicate direct_upgraded_business, :organization_direct_upgraded?
        assert_predicate direct_upgraded_business, :upgraded_from_organization?
        refute @owner.dismissed_business_notice?("org_upgrade_onboarding", business_id: direct_upgraded_business.id)

        tabs_builder = Business::NavigationTabs.new(direct_upgraded_business, current_user: @owner)

        tab = tabs_builder.tabs.find { |tab| tab.text == "Getting started" }
        assert_equal urls.enterprise_getting_started_path(direct_upgraded_business), tab.href
      end

      test "does not render the getting started tab when business has been upgraded from a GHEC-org and user has dismissed onboarding", skip_with_all_emus: true do
        direct_upgraded_business = create :business, \
          :with_self_serve_payment,
          owners: @business_plus_org.admins,
          name: "Upgraded from a business plus org",
          upgraded_at: 2.days.ago,
          upgraded_from: @business_plus_org,
          upgraded_from_plan: @business_plus_org.plan.name
        direct_upgraded_business.organization_direct_upgraded!
        direct_upgraded_business.set_org_upgrade_onboarding_notice(
          initiating_owner: @owner, organization: @business_plus_org
        )
        @owner.dismiss_business_notice("org_upgrade_onboarding", business_id: direct_upgraded_business.id)

        assert_predicate direct_upgraded_business, :organization_direct_upgraded?
        assert_predicate direct_upgraded_business, :upgraded_from_organization?
        assert @owner.dismissed_business_notice?("org_upgrade_onboarding", business_id: direct_upgraded_business.id)

        tabs_builder = Business::NavigationTabs.new(direct_upgraded_business, current_user: @owner)

        tab = tabs_builder.tabs.find { |tab| tab.text == "Getting started" }
        refute tab
      end

      test "does not render the getting started tab when business has been upgraded from a GHEC-org but notice was never set on user", skip_with_all_emus: true do
        direct_upgraded_business = create :business, \
          :with_self_serve_payment,
          owners: @business_plus_org.admins,
          name: "Upgraded from a business plus org",
          upgraded_at: 2.days.ago,
          upgraded_from: @business_plus_org,
          upgraded_from_plan: @business_plus_org.plan.name
        direct_upgraded_business.organization_direct_upgraded!
        direct_upgraded_business.set_org_upgrade_onboarding_notice(
          initiating_owner: @owner, organization: @business_plus_org
        )
        second_owner = create :user
        direct_upgraded_business.add_owner(second_owner, actor: @owner)
        assert_predicate direct_upgraded_business, :organization_direct_upgraded?
        assert_predicate direct_upgraded_business, :upgraded_from_organization?
        refute second_owner.dismissed_business_notice?("org_upgrade_onboarding", business_id: direct_upgraded_business.id)
        refute direct_upgraded_business.org_upgrade_onboarding_notice_set?(second_owner)

        tabs_builder = Business::NavigationTabs.new(direct_upgraded_business, current_user: second_owner)

        tab = tabs_builder.tabs.find { |tab| tab.text == "Getting started" }
        refute tab
      end

      test "only renders the Overview tab when the business was created from a coupon, and payment is in progress", skip_with_all_emus: true do
        enable_feature_flag(:new_ea_creation_from_coupon)
        business = create :business, owners: [@owner]
        business.initiate_creation_from_coupon
        business.initiate_creation_purchase_from_coupon
        assert_predicate business, :creation_from_coupon_purchase_initiated?

        tabs_builder = Business::NavigationTabs.new(business, current_user: @owner)

        tab = tabs_builder.tabs.find { |tab| tab.text == "Overview" }
        actual_tabs = tabs_builder.tabs.map(&:text)

        assert_equal ["Overview"], actual_tabs
      end

      test "renders Sponsors sub-menu under Policies when enabled for the business" do
        enable_feature_flag(:sponsors_self_serve_enterprise, @business)
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :policies,
          ),
          allowed_queries: 3,
        )
        assert_test_selector("policies-sidebar")
        assert_selector("a", text: "Sponsors")
      end

      test "does not render Billing and Enterprise licensing sub-menu under Settings when billing is disabled" do
        GitHub.stubs(:billing_enabled?).returns(false)
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 2,
        )
        assert_test_selector("settings-sidebar")
        refute_selector("a", text: "Billing")
        refute_selector("a", text: "Enterprise licensing")
      end

      test "does not render Billing sub-menu under Settings when proxima_billing_enabled? is set to true" do
        GitHub.stubs(:proxima_billing_enabled?).returns(true)

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 3,
        )
        assert_test_selector("settings-sidebar")
        refute_selector("a", text: "Billing")
      end

      test "does not render Billing sub-menu after an enterprise has been migrated for more than 30 days" do
        @business.customer.stubs(:migration_happened_more_than_thirty_days_ago?).returns(true)
        @business.customer.stubs(:is_vnext_native?).returns(false)
        @business.customer.update(billed_via_billing_platform: true)
        create(:billing_platform_enabled_product, migration_date: 31.days.ago, customer: @business.customer)

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 2,
        )
        assert_test_selector("settings-sidebar")
        refute_selector("a", text: "Billing")
      end

      test "does not render Billing sub-menu for vnext native customer" do
        created_and_migrated_date = 1.day.ago
        @business.customer.update(billed_via_billing_platform: true, created_at: created_and_migrated_date)
        create(:billing_platform_enabled_product, migration_date: created_and_migrated_date, customer: @business.customer)

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 4,
        )
        assert_test_selector("settings-sidebar")
        refute_selector("a", text: "Billing")
      end

      test "renders Billing sub-menu for vnext native customer" do
        @business.customer.update(billed_via_billing_platform: true, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day)
        create(:billing_platform_enabled_product, customer: @business.customer)

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 4,
        )
        assert_test_selector("settings-sidebar")
        assert_selector("a", text: "Billing")
      end

      test "renders Retired namespaces sub-menu under Settings in proxima" do
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 4,
        )
        assert_test_selector("settings-sidebar")
        assert_selector("a", text: "Retired namespaces")
      end if TestEnv.test_in_multitenancy_mode?

      test "renders overview, usage, budgets, cost centers, payment information, payment history, marketplace apps, sponsorships, and emails vNext Billing links for owner if non-invoiced customer is billed_via_billing_platform " do
        GitHub.stubs(:billing_enabled?).returns(true)
        @business.customer.update!(billed_via_billing_platform: true)
        Business.any_instance.stubs(:invoiced?).returns(false)
        Business.any_instance.stubs(:can_self_serve?).returns(true)
        enable_feature_flag(:sponsors_self_serve_enterprise)

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :billing_and_licensing,
          ),
          allowed_queries: 7,
        )
        assert_test_selector("billing-and-licensing-sidebar")
        assert_selector("a", text: "Overview")
        assert_selector("a", text: "Usage")
        assert_selector("a", text: "Cost centers")
        assert_selector("a", text: "Budgets and alerts")
        assert_selector("a", text: "Licensing")
        assert_selector("a", text: "Payment information")
        assert_selector("a", text: "Payment history")
        assert_selector("a", text: "Billing contacts")
        assert_selector("a", text: "Marketplace apps")
        assert_selector("a", text: "Sponsorships")
      end

      test "renders overview, usage, budgets, cost centers, past invoices, licensing, payment information and emails vNext Billing links for owner if invoiced customer is billed_via_billing_platform " do
        GitHub.stubs(:billing_enabled?).returns(true)
        @business.customer.update!(billed_via_billing_platform: true)
        Business.any_instance.stubs(:invoiced?).returns(true)
        enable_feature_flag(:sponsors_self_serve_enterprise)

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :billing_and_licensing,
          ),
          allowed_queries: 7,
        )
        assert_test_selector("billing-and-licensing-sidebar")
        assert_selector("a", text: "Overview")
        assert_selector("a", text: "Usage")
        assert_selector("a", text: "Cost centers")
        assert_selector("a", text: "Budgets and alerts")
        assert_selector("a", text: "Licensing")
        assert_selector("a", text: "Payment information")
        assert_selector("a", text: "Past invoices")
        assert_selector("a", text: "Billing contacts")
      end
    end

    context "when current_user is a billing manager" do
      test "renders menu items appropriately on dotcom" do

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @billing_manager)
        actual_tabs = tabs_builder.tabs.map(&:text)

        assert_equal %w[Overview Settings], actual_tabs
      end if GitHub.billing_enabled?


      test "renders Settings menu item and its sub-menu items appropriately on dotcom" do
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 3,
        )
        assert_test_selector("settings-sidebar")
        assert_selector("a", text: "Billing")
        assert_selector("a", text: "Enterprise licensing")
      end if GitHub.billing_enabled?

      test "renders overview, usage, budgets, cost centers, payment information, payment history, marketplace apps, sponsorships, and emails vNext Billing links for billing manager if customer is billed_via_billing_platform " do
        GitHub.stubs(:billing_enabled?).returns(true)
        @business.customer.update!(billed_via_billing_platform: true)
        Business.any_instance.stubs(:invoiced?).returns(false)
        Business.any_instance.stubs(:can_self_serve?).returns(true)
        enable_feature_flag(:sponsors_self_serve_enterprise)

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :billing_and_licensing,
          ),
          allowed_queries: 7,
        )

        assert_test_selector "billing-and-licensing-sidebar"
        assert_selector("a", text: "Overview")
        assert_selector("a", text: "Usage")
        assert_selector("a", text: "Cost centers")
        assert_selector("a", text: "Budgets and alerts")
        assert_selector("a", text: "Licensing")
        assert_selector("a", text: "Payment information")
        assert_selector("a", text: "Payment history")
        assert_selector("a", text: "Billing contacts")
        assert_selector("a", text: "Marketplace apps")
        assert_selector("a", text: "Sponsorships")
      end
    end

    context "when current_user is an org admin" do
      test "renders menu items appropriately on dotcom" do
        @business.customer.update!(billed_via_billing_platform: true)

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @org_admin)
        actual_tabs = tabs_builder.tabs.map(&:text)
        if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
          assert_equal ["Overview", "Organizations", "People", "Security", "Billing & Licensing"], actual_tabs
        else
          assert_equal ["Overview", "Organizations", "Security", "Billing & Licensing"], actual_tabs
        end
      end if GitHub.billing_enabled?

      test "renders Organization, People, Code Security menus only for an Org Admin on dotcom when on Enterprise CLoud trial" do
        @business.update_attribute :trial_expires_at, 5.days.from_now
        @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)
        @business.reload

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @org_admin)
        actual_tabs = tabs_builder.tabs.map(&:text)
        if EnterpriseTeam.enabled_for_organization_security_manager?(@business)

          assert_equal %w[Overview Organizations People Security], actual_tabs
        else
          assert_equal %w[Overview Organizations Security], actual_tabs
        end
      end

      test "renders overview, usage, budgets, and cost centers vNext Billing links for org admin if customer is billed_via_billing_platform" do
        @business.customer.update!(billed_via_billing_platform: true)

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @owner,
            business: @business,
            sidebar_section: :billing_and_licensing,
          ),
          allowed_queries: 7,
        )

        assert_test_selector "billing-and-licensing-sidebar"
        assert_selector("a", text: "Overview")
        assert_selector("a", text: "Usage")
        assert_selector("a", text: "Cost centers")
        assert_selector("a", text: "Budgets and alerts")
      end if GitHub.billing_enabled?

      test "renders the correct path when vnext is not enabled" do
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @org_admin,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 3,
        )
        refute_selector "a[href='/enterprises/#{@business.slug}/settings/billing']"
      end if GitHub.billing_enabled?
    end

    context "when current_user is a member" do
      test "renders menu items appropriately on dotcom" do
        tabs_builder = Business::NavigationTabs.new(@business, current_user: @member)
        actual_tabs = tabs_builder.tabs.map(&:text)

        if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
          assert_equal %w[Overview Organizations People Security], actual_tabs
        else
          assert_equal %w[Overview Organizations Security], actual_tabs
        end
      end

      test "renders Organization, People, and Code Security menus only for an member on dotcom when on Enterprise CLoud trial" do
        @business.update_attribute :trial_expires_at, 5.days.from_now
        @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)
        @business.reload

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @member)
        actual_tabs = tabs_builder.tabs.map(&:text)

        if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
          assert_equal %w[Overview Organizations People Security], actual_tabs
        else
          assert_equal %w[Overview Organizations Security], actual_tabs
        end
      end

      test "renders menu items appropriately on dotcom when the business hasn't purchased GHAS" do
        Business.any_instance.stubs(:advanced_security_purchased?).returns(false)

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @member)
        actual_tabs = tabs_builder.tabs.map(&:text)

        if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
          assert_equal %w[Overview Organizations People Security], actual_tabs
        else
          assert_equal %w[Overview Organizations Security], actual_tabs
        end
      end

      test "renders a subset of sub-menu items on dotcom when token scanning is disabled" do
        GitHub.stubs(:configuration_secret_scanning_enabled?).returns(false)

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @member,
            business: @business,
            sidebar_section: :code_security,
          ),
          allowed_queries: 4,
        )
        assert_test_selector "security-sidebar"
        assert_selector "a", text: "Overview"
        assert_selector "a", text: "Risk"
        assert_selector "a", text: "Coverage"
        assert_selector "a", text: "Enablement trends"
        assert_selector "a", text: "CodeQL pull request alerts"
        assert_selector "a", text: "Dependabot alerts"
        assert_selector "a", text: "Code scanning alerts"
        refute_selector "a", text: "Secret scanning alerts"
      end

      test "renders sub-menu items appropriately on dotcom when GHAS is enabled" do
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @member,
            business: @business,
            sidebar_section: :code_security,
          ),
          allowed_queries: 4,
        )
        assert_test_selector "security-sidebar"
        assert_selector "a", text: "Overview"
        assert_selector "a", text: "Risk"
        assert_selector "a", text: "Coverage"
        assert_selector "a", text: "Enablement trends"
        assert_selector "a", text: "CodeQL pull request alerts"
        assert_selector "a", text: "Secret scanning metrics"
        assert_selector "a", text: "Dependabot alerts"
        assert_selector "a", text: "Code scanning alerts"
        assert_selector "a", text: "Secret scanning alerts"
      end

      test "renders sub-menu items appropriately based on fine-grained permissions" do
        enable_feature_flag(:custom_enterprise_role_feature, @business)
        grant_custom_enterprise_role(user: @member, target: @business, fgps: [:read_enterprise_audit_logs, :write_enterprise_custom_org_role, :write_enterprise_custom_enterprise_role])

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @member,
            business: @business,
            sidebar_section: :people,
          ),
          allowed_queries: TestEnv.test_all_features? ? 3 : 4,
        )

        assert_test_selector "people-sidebar"

        if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
          assert_selector "a", text: "Enterprise teams"
          assert_selector "a", text: "Security managers"
        end

        if @business.feature_enabled?(:enterprise_custom_organization_roles)
          assert_selector "a", text: "Organization roles"
        end

        if @business.feature_enabled?(:custom_enterprise_role_feature)
          assert_selector "a", text: "Role management"
          assert_selector "a", text: "Role assignments"
        end

        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @member,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 3,
        )

        if @business.feature_enabled?(:use_biz_audit_log_fgp_ui)
          assert_selector "a", text: "Audit log"
        end
      end
    end

    context "when current_user is an enterprise security manager" do
      context "on dotcom" do
        test "renders menu items appropriately" do
          tabs_builder = Business::NavigationTabs.new(@business, current_user: @enterprise_security_manager)
          actual_tabs = tabs_builder.tabs.map(&:text)

          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_equal %w[Overview Organizations People Policies Security], actual_tabs
          else
            assert_equal %w[Overview Organizations Policies Security Settings], actual_tabs
          end
        end

        test "policies" do
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :policies,
            ),
            allowed_queries: 2,
          )
          assert_test_selector("policies-sidebar")
          assert_selector("a", text: "Advanced Security")
        end

        test "code security" do
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 4,
          )
          assert_test_selector "security-sidebar"
          assert_selector "a", text: "Overview"
          assert_selector "a", text: "Risk"
          assert_selector "a", text: "Coverage"
          assert_selector "a", text: "Enablement trends"
          assert_selector "a", text: "CodeQL pull request alerts"
          assert_selector "a", text: "Secret scanning metrics"
          assert_selector "a", text: "Dependabot alerts"
          assert_selector "a", text: "Code scanning alerts"
          assert_selector "a", text: "Secret scanning alerts"
        end

        test "settings" do
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :settings,
            ),
            allowed_queries: 3,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            refute_selector("a", text: "Advanced Security")
          else
            assert_selector("a", text: "Advanced Security")
          end
        end

        test "people" do
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :people,
            ),
            allowed_queries: TestEnv.test_all_features? ? 3 : 4,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_selector "a", text: "Enterprise teams"
            assert_selector "a", text: "Security managers"
          else
            refute_selector "a", text: "Enterprise teams"
            refute_selector "a", text: "Security managers"
          end
        end
      end

      context "basic on dotcom" do

        test "renders menu and sub menu items appropriately when business is basic plan" do
          @business.update_attribute(:seats_plan_type, :basic)

          tabs_builder = Business::NavigationTabs.new(@business, current_user: @enterprise_security_manager)
          actual_tabs = tabs_builder.tabs.map(&:text)

          assert_equal ["Overview", "Getting started", "People", "Policies"], actual_tabs
        end

        test "people" do
          @business.update_attribute(:seats_plan_type, :basic)
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :people,
            ),
            allowed_queries: 4,
          )
          assert_test_selector "people-sidebar"
          assert_selector "a", text: "Enterprise teams"
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_selector "a", text: "Security managers"
          else
            refute_selector "a", text: "Security managers"
          end
        end

        test "policies" do
          @business.update_attribute(:seats_plan_type, :basic)
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :policies,
            ),
            allowed_queries: 2,
          )
          assert_test_selector "policies-sidebar"
          assert_selector "a", text: "Advanced Security"
        end
      end

      context "business is not invoiced" do
        test "renders menu items appropriately" do
          @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)
          tabs_builder = Business::NavigationTabs.new(@business, current_user: @enterprise_security_manager)
          actual_tabs = tabs_builder.tabs.map(&:text)

          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_equal %w[Overview Organizations People Policies Security], actual_tabs
          else
            assert_equal %w[Overview Organizations Policies Security Settings], actual_tabs
          end
        end

        test "policies" do
          @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :policies,
            ),
            allowed_queries: 2,
          )
          assert_test_selector("policies-sidebar")
          assert_selector("a", text: "Advanced Security")
        end

        test "code security" do
          @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 4,
          )
          assert_test_selector "security-sidebar"
          assert_selector "a", text: "Overview"
          assert_selector "a", text: "Risk"
          assert_selector "a", text: "Coverage"
          assert_selector "a", text: "Enablement trends"
          assert_selector "a", text: "CodeQL pull request alerts"
          assert_selector "a", text: "Secret scanning metrics"
          assert_selector "a", text: "Dependabot alerts"
          assert_selector "a", text: "Code scanning alerts"
          assert_selector "a", text: "Secret scanning alerts"
        end

        test "settings" do
          @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :settings,
            ),
            allowed_queries: 3,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            refute_selector("a", text: "Advanced Security")
          else
            assert_selector("a", text: "Advanced Security")
          end
        end

        test "people" do
          @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :people,
            ),
            allowed_queries: TestEnv.test_all_features? ? 3 : 4,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_selector "a", text: "Enterprise teams"
            assert_selector "a", text: "Security managers"
          else
            refute_selector "a", text: "Enterprise teams"
            refute_selector "a", text: "Security managers"
          end
        end
      end

      context "enterprise is in trial" do
        test "renders menu items appropriately" do
          @business.update_attribute :trial_expires_at, 5.days.from_now
          @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)
          @business.reload
          assert_predicate @business, :trial?
          refute_predicate @business, :downgraded_to_free_plan?
          refute_predicate @business, :trial_expired?

          tabs_builder = Business::NavigationTabs.new(@business, current_user: @enterprise_security_manager)
          actual_tabs = tabs_builder.tabs.map(&:text)

          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_equal %w[Overview Organizations People Policies Security], actual_tabs
          else
            assert_equal %w[Overview Organizations Policies Security Settings], actual_tabs
          end
        end

        test "policies" do
          @business.update_attribute :trial_expires_at, 5.days.from_now
          @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)
          @business.reload
          assert_predicate @business, :trial?
          refute_predicate @business, :downgraded_to_free_plan?
          refute_predicate @business, :trial_expired?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :policies,
            ),
            allowed_queries: 2,
          )
          assert_test_selector("policies-sidebar")
          assert_selector("a", text: "Advanced Security")
        end

        test "code security" do
          @business.update_attribute :trial_expires_at, 5.days.from_now
          @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)
          @business.reload
          assert_predicate @business, :trial?
          refute_predicate @business, :downgraded_to_free_plan?
          refute_predicate @business, :trial_expired?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 4,
          )
          assert_test_selector "security-sidebar"
          assert_selector "a", text: "Overview"
          assert_selector "a", text: "Risk"
          assert_selector "a", text: "Coverage"
          assert_selector "a", text: "Enablement trends"
          assert_selector "a", text: "CodeQL pull request alerts"
          assert_selector "a", text: "Secret scanning metrics"
          assert_selector "a", text: "Dependabot alerts"
          assert_selector "a", text: "Code scanning alerts"
          assert_selector "a", text: "Secret scanning alerts"
        end

        test "settings" do
          @business.update_attribute :trial_expires_at, 5.days.from_now
          @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)
          @business.reload
          assert_predicate @business, :trial?
          refute_predicate @business, :downgraded_to_free_plan?
          refute_predicate @business, :trial_expired?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :settings,
            ),
            allowed_queries: 3,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            refute_selector("a", text: "Advanced Security")
          else
            assert_selector("a", text: "Advanced Security")
          end
        end

        test "people" do
          @business.update_attribute :trial_expires_at, 5.days.from_now
          @business.customer.update_attribute(:billing_type, Customer::BILLING_TYPE_CARD)
          @business.reload
          assert_predicate @business, :trial?
          refute_predicate @business, :downgraded_to_free_plan?
          refute_predicate @business, :trial_expired?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :people,
            ),
            allowed_queries: TestEnv.test_all_features? ? 3 : 4,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_selector "a", text: "Enterprise teams"
            assert_selector "a", text: "Security managers"
          else
            refute_selector "a", text: "Enterprise teams"
            refute_selector "a", text: "Security managers"
          end
        end
      end

      context "enterprise trial has expired" do
        test "renders menu items appropriately" do
          @business.update_attribute :trial_expires_at, 1.day.ago
          @business.downgrade_to_free_plan
          @business.reload
          assert_predicate @business, :downgraded_to_free_plan?
          assert_predicate @business, :trial_expired?

          tabs_builder = Business::NavigationTabs.new(@business, current_user: @enterprise_security_manager)
          actual_tabs = tabs_builder.tabs.map(&:text)

          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_equal %w[Overview Organizations People], actual_tabs
          else
            assert_equal %w[Overview Organizations Settings], actual_tabs
          end
        end

        test "settings" do
          @business.update_attribute :trial_expires_at, 1.day.ago
          @business.downgrade_to_free_plan
          @business.reload
          assert_predicate @business, :downgraded_to_free_plan?
          assert_predicate @business, :trial_expired?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :settings,
            ),
            allowed_queries: 3,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            refute_selector("a", text: "Advanced Security")
          else
            assert_selector("a", text: "Advanced Security")
          end
        end

        test "people" do
          @business.update_attribute :trial_expires_at, 1.day.ago
          @business.downgrade_to_free_plan
          @business.reload
          assert_predicate @business, :downgraded_to_free_plan?
          assert_predicate @business, :trial_expired?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :people,
            ),
            allowed_queries: TestEnv.test_all_features? ? 3 : 4,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_selector "a", text: "Enterprise teams"
            assert_selector "a", text: "Security managers"
          else
            refute_selector "a", text: "Enterprise teams"
            refute_selector "a", text: "Security managers"
          end
        end
      end

      context "renders menu and sub menu items appropriately for trial metered plan business" do
        test "renders menu items appropriately" do
          @business.update_attribute :trial_expires_at, 5.days.from_now
          @business.customer.update metered_ghe: true
          assert_predicate @business.reload, :metered_plan?
          refute @business.metered_ghes_eligible?

          tabs_builder = Business::NavigationTabs.new(@business, current_user: @enterprise_security_manager)
          actual_tabs = tabs_builder.tabs.map(&:text)

          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_equal %w[Overview Organizations People Policies Security], actual_tabs
          else
            assert_equal %w[Overview Organizations Policies Security Settings], actual_tabs
          end
        end

        test "policies" do
          @business.update_attribute :trial_expires_at, 5.days.from_now
          @business.customer.update metered_ghe: true
          assert_predicate @business.reload, :metered_plan?
          refute @business.metered_ghes_eligible?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :policies,
            ),
            allowed_queries: 2,
          )
          assert_test_selector("policies-sidebar")
          assert_selector("a", text: "Advanced Security")
        end

        test "code security" do
          @business.update_attribute :trial_expires_at, 5.days.from_now
          @business.customer.update metered_ghe: true
          assert_predicate @business.reload, :metered_plan?
          refute @business.metered_ghes_eligible?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 4,
          )
          assert_test_selector "security-sidebar"
          assert_selector "a", text: "Overview"
          assert_selector "a", text: "Risk"
          assert_selector "a", text: "Coverage"
          assert_selector "a", text: "Enablement trends"
          assert_selector "a", text: "CodeQL pull request alerts"
          assert_selector "a", text: "Secret scanning metrics"
          assert_selector "a", text: "Dependabot alerts"
          assert_selector "a", text: "Code scanning alerts"
          assert_selector "a", text: "Secret scanning alerts"
        end

        test "settings" do
          @business.update_attribute :trial_expires_at, 5.days.from_now
          @business.customer.update metered_ghe: true
          assert_predicate @business.reload, :metered_plan?
          refute @business.metered_ghes_eligible?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :settings,
            ),
            allowed_queries: 3,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            refute_selector("a", text: "Advanced Security")
          else
            assert_selector("a", text: "Advanced Security")
          end
        end

        test "people" do
          @business.update_attribute :trial_expires_at, 5.days.from_now
          @business.customer.update metered_ghe: true
          assert_predicate @business.reload, :metered_plan?
          refute @business.metered_ghes_eligible?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :people,
            ),
            allowed_queries: TestEnv.test_all_features? ? 3 : 4,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_selector "a", text: "Enterprise teams"
            assert_selector "a", text: "Security managers"
          else
            refute_selector "a", text: "Enterprise teams"
            refute_selector "a", text: "Security managers"
          end
        end
      end

      context "renders menu and sub menu items appropriately for non-trial metered plan business" do
        test "renders menu items appropriately" do
          @business.customer.update metered_plan: true
          assert_predicate @business.reload, :metered_plan?
          assert @business.metered_ghes_eligible?

          tabs_builder = Business::NavigationTabs.new(@business, current_user: @enterprise_security_manager)
          actual_tabs = tabs_builder.tabs.map(&:text)

          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_equal %w[Overview Organizations People Policies Security], actual_tabs
          else
            assert_equal %w[Overview Organizations Policies Security Settings], actual_tabs
          end
        end

        test "policies" do
          @business.customer.update metered_plan: true
          assert_predicate @business.reload, :metered_plan?
          assert @business.metered_ghes_eligible?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :policies,
            ),
            allowed_queries: 2,
          )
          assert_test_selector("policies-sidebar")
          assert_selector("a", text: "Advanced Security")
        end

        test "code security" do
          @business.customer.update metered_plan: true
          assert_predicate @business.reload, :metered_plan?
          assert @business.metered_ghes_eligible?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 4,
          )
          assert_test_selector "security-sidebar"
          assert_selector "a", text: "Overview"
          assert_selector "a", text: "Risk"
          assert_selector "a", text: "Coverage"
          assert_selector "a", text: "Enablement trends"
          assert_selector "a", text: "CodeQL pull request alerts"
          assert_selector "a", text: "Secret scanning metrics"
          assert_selector "a", text: "Dependabot alerts"
          assert_selector "a", text: "Code scanning alerts"
          assert_selector "a", text: "Secret scanning alerts"
        end

        test "settings" do
          @business.customer.update metered_plan: true
          assert_predicate @business.reload, :metered_plan?
          assert @business.metered_ghes_eligible?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :settings,
            ),
            allowed_queries: 3,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            refute_selector("a", text: "Advanced Security")
          else
            assert_selector("a", text: "Advanced Security")
          end
        end

        test "people" do
          @business.customer.update metered_plan: true
          assert_predicate @business.reload, :metered_plan?
          assert @business.metered_ghes_eligible?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :people,
            ),
            allowed_queries: TestEnv.test_all_features? ? 3 : 4,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_selector "a", text: "Enterprise teams"
            assert_selector "a", text: "Security managers"
          else
            refute_selector "a", text: "Enterprise teams"
            refute_selector "a", text: "Security managers"
          end
        end
      end

      context "renders menu and sub menu items appropriately when the business hasn't purchased GHAS" do
        test "renders menu items appropriately" do
          Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
          tabs_builder = Business::NavigationTabs.new(@business, current_user: @enterprise_security_manager)
          actual_tabs = tabs_builder.tabs.map(&:text)

          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_equal %w[Overview Organizations People Policies Security], actual_tabs
          else
            assert_equal %w[Overview Organizations Policies Security Settings], actual_tabs
          end
        end

        test "policies" do
          Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :policies,
            ),
            allowed_queries: 2,
          )
          assert_test_selector("policies-sidebar")
          assert_selector("a", text: "Advanced Security")
        end

        test "code security" do
          Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 4,
          )
          assert_test_selector "security-sidebar"
          assert_selector "a", text: "Overview"
          assert_selector "a", text: "Risk"
          assert_selector "a", text: "Coverage"
          assert_selector "a", text: "Enablement trends"
          assert_selector "a", text: "CodeQL pull request alerts"
          assert_selector "a", text: "Secret scanning metrics"
          assert_selector "a", text: "Dependabot alerts"
          assert_selector "a", text: "Code scanning alerts"
          assert_selector "a", text: "Secret scanning alerts"
        end

        test "settings" do
          Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :settings,
            ),
            allowed_queries: 3,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            refute_selector("a", text: "Advanced Security")
          else
            assert_selector("a", text: "Advanced Security")
          end
        end

        test "people" do
          Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :people,
            ),
            allowed_queries: TestEnv.test_all_features? ? 3 : 4,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_selector "a", text: "Enterprise teams"
            assert_selector "a", text: "Security managers"
          else
            refute_selector "a", text: "Enterprise teams"
            refute_selector "a", text: "Security managers"
          end
        end
      end

      context "renders menu and sub menu items appropriately when business downgraded to free plan" do
        test "renders menu items appropriately" do
          @business.downgrade_to_free_plan
          @business.reload
          assert_predicate @business, :downgraded_to_free_plan?

          tabs_builder = Business::NavigationTabs.new(@business, current_user: @enterprise_security_manager)
          actual_tabs = tabs_builder.tabs.map(&:text)

          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_equal %w[Overview Organizations People], actual_tabs
          else
            assert_equal %w[Overview Organizations Settings], actual_tabs
          end
        end

        test "settings" do
          @business.downgrade_to_free_plan
          @business.reload
          assert_predicate @business, :downgraded_to_free_plan?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :settings,
            ),
            allowed_queries: 3,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            refute_selector("a", text: "Advanced Security")
          else
            assert_selector("a", text: "Advanced Security")
          end
        end

        test "people" do
          @business.downgrade_to_free_plan
          @business.reload
          assert_predicate @business, :downgraded_to_free_plan?
          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :people,
            ),
            allowed_queries: TestEnv.test_all_features? ? 3 : 4,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_selector "a", text: "Enterprise teams"
            assert_selector "a", text: "Security managers"
          else
            refute_selector "a", text: "Enterprise teams"
            refute_selector "a", text: "Security managers"
          end
        end
      end

      context "renders menu and sub menu items appropriately for business created from upgrade of ghec org when business downgraded to free plan" do
        test "renders menu items appropriately", skip_with_all_emus: true do
          org = create :organization
          direct_upgraded_business = create :business, \
            :with_self_serve_payment,
            owners: @business_plus_org.admins,
            name: "Upgraded from a business plus org",
            upgraded_at: 2.days.ago,
            upgraded_from: @business_plus_org,
            upgraded_from_plan: @business_plus_org.plan.name,
            organizations: [org]

          direct_upgraded_business.organization_direct_upgraded!
          direct_upgraded_business.set_org_upgrade_onboarding_notice(
            initiating_owner: @owner, organization: @business_plus_org
          )

          direct_upgraded_business.downgrade_to_free_plan
          assert_predicate direct_upgraded_business.reload, :organization_direct_upgraded?
          assert_predicate direct_upgraded_business, :upgraded_from_organization?
          refute @owner.dismissed_business_notice?("org_upgrade_onboarding", business_id: direct_upgraded_business.id)
          assert_predicate direct_upgraded_business, :downgraded_to_free_plan?

          enterprise_security_manager_team = create :enterprise_security_manager_team, business: direct_upgraded_business
          enterprise_security_manager = create :user
          enterprise_security_manager_team.bulk_add_members(users: [enterprise_security_manager])
          org.add_member enterprise_security_manager # Because the factory doesn't set up the org teams sync

          tabs_builder = Business::NavigationTabs.new(direct_upgraded_business, current_user: enterprise_security_manager)
          actual_tabs = tabs_builder.tabs.map(&:text)

          if EnterpriseTeam.enabled_for_organization_security_manager?(direct_upgraded_business)
            assert_equal %w[Overview Organizations People], actual_tabs
          else
            assert_equal %w[Overview Organizations Settings], actual_tabs
          end
        end

        test "settings" do
          org = create :organization
          direct_upgraded_business = create :business, \
            :with_self_serve_payment,
            owners: @business_plus_org.admins,
            name: "Upgraded from a business plus org",
            upgraded_at: 2.days.ago,
            upgraded_from: @business_plus_org,
            upgraded_from_plan: @business_plus_org.plan.name,
            organizations: [org]

          direct_upgraded_business.organization_direct_upgraded!
          direct_upgraded_business.set_org_upgrade_onboarding_notice(
            initiating_owner: @owner, organization: @business_plus_org
          )

          direct_upgraded_business.downgrade_to_free_plan
          assert_predicate direct_upgraded_business.reload, :organization_direct_upgraded?
          assert_predicate direct_upgraded_business, :upgraded_from_organization?
          refute @owner.dismissed_business_notice?("org_upgrade_onboarding", business_id: direct_upgraded_business.id)
          assert_predicate direct_upgraded_business, :downgraded_to_free_plan?

          enterprise_security_manager_team = create :enterprise_security_manager_team, business: direct_upgraded_business
          enterprise_security_manager = create :user
          enterprise_security_manager_team.bulk_add_members(users: [enterprise_security_manager])
          org.add_member enterprise_security_manager # Because the factory doesn't set up the org teams sync

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: enterprise_security_manager,
              business: direct_upgraded_business,
              sidebar_section: :settings,
            ),
            allowed_queries: 3,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(direct_upgraded_business)
            refute_selector("a", text: "Advanced Security")
          else
            assert_selector("a", text: "Advanced Security")
          end
        end

        test "people" do
          org = create :organization
          direct_upgraded_business = create :business, \
            :with_self_serve_payment,
            owners: @business_plus_org.admins,
            name: "Upgraded from a business plus org",
            upgraded_at: 2.days.ago,
            upgraded_from: @business_plus_org,
            upgraded_from_plan: @business_plus_org.plan.name,
            organizations: [org]

          direct_upgraded_business.organization_direct_upgraded!
          direct_upgraded_business.set_org_upgrade_onboarding_notice(
            initiating_owner: @owner, organization: @business_plus_org
          )

          direct_upgraded_business.downgrade_to_free_plan
          assert_predicate direct_upgraded_business.reload, :organization_direct_upgraded?
          assert_predicate direct_upgraded_business, :upgraded_from_organization?
          refute @owner.dismissed_business_notice?("org_upgrade_onboarding", business_id: direct_upgraded_business.id)
          assert_predicate direct_upgraded_business, :downgraded_to_free_plan?

          enterprise_security_manager_team = create :enterprise_security_manager_team, business: direct_upgraded_business
          enterprise_security_manager = create :user
          enterprise_security_manager_team.bulk_add_members(users: [enterprise_security_manager])
          org.add_member enterprise_security_manager # Because the factory doesn't set up the org teams sync

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: enterprise_security_manager,
              business: direct_upgraded_business,
              sidebar_section: :people,
            ),
            allowed_queries: TestEnv.test_all_features? ? 3 : 4,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(direct_upgraded_business)
            assert_selector "a", text: "Enterprise teams"
            assert_selector "a", text: "Security managers"
          else
            refute_selector "a", text: "Enterprise teams"
            refute_selector "a", text: "Security managers"
          end
        end
      end

      context "on proxima" do
        test "renders menu items appropriately" do
          on_multi_tenant_enterprise
          @business.customer.update_attribute(:billing_type, nil)

          tabs_builder = Business::NavigationTabs.new(@business, current_user: @enterprise_security_manager)
          actual_tabs = tabs_builder.tabs.map(&:text)

          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_equal %w[Overview Organizations People Policies Security Settings], actual_tabs
          else
            assert_equal %w[Overview Organizations Policies Security Settings], actual_tabs
          end
        end

        test "policies" do
          on_multi_tenant_enterprise
          @business.customer.update_attribute(:billing_type, nil)

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :policies,
            ),
            allowed_queries: 2,
          )
          assert_test_selector("policies-sidebar")
          assert_selector("a", text: "Advanced Security")
        end

        test "code security" do
          on_multi_tenant_enterprise
          @business.customer.update_attribute(:billing_type, nil)

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :code_security,
            ),
            allowed_queries: 4,
          )
          assert_test_selector "security-sidebar"
          assert_selector "a", text: "Overview"
          assert_selector "a", text: "Risk"
          assert_selector "a", text: "Coverage"
          assert_selector "a", text: "Enablement trends"
          assert_selector "a", text: "CodeQL pull request alerts"
          assert_selector "a", text: "Secret scanning metrics"
          assert_selector "a", text: "Dependabot alerts"
          assert_selector "a", text: "Code scanning alerts"
          assert_selector "a", text: "Secret scanning alerts"
        end

        test "settings" do
          on_multi_tenant_enterprise
          @business.customer.update_attribute(:billing_type, nil)

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :settings,
            ),
            allowed_queries: 3,
          )

          assert_selector("a", text: "Advanced Security")
        end

        test "people" do
          on_multi_tenant_enterprise
          @business.customer.update_attribute(:billing_type, nil)

          render_inline(
            Businesses::GlobalSidebarComponent.new(
              user: @enterprise_security_manager,
              business: @business,
              sidebar_section: :people,
            ),
            allowed_queries: TestEnv.test_all_features? ? 3 : 4,
          )
          if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
            assert_selector "a", text: "Enterprise teams"
            assert_selector "a", text: "Security managers"
          else
            refute_selector "a", text: "Enterprise teams"
            refute_selector "a", text: "Security managers"
          end
        end
      end
    end

    context "when current_user is an unaffiliated member" do

      test "renders subnav appropriately when business is basic plan and user is unaffiliated" do
        disable_feature_flag(:unaffiliated_user_accounts)
        @business.update_attribute(:seats_plan_type, :basic)

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @unaffiliated)
        actual_tabs = tabs_builder.tabs.map(&:text)

        assert_equal ["Overview", "Getting started"], actual_tabs
      end

      test "renders menu items appropriately on dotcom when business is full plan" do
        enable_feature_flag(:unaffiliated_user_accounts)

        tabs_builder = Business::NavigationTabs.new(@business, current_user: @unaffiliated)
        actual_tabs = tabs_builder.tabs.map(&:text)

        assert_equal ["Overview"], actual_tabs
      end
    end
  end

  private

  sig { returns(UrlHelpers) }
  memoize def urls
    T.cast(Class.new { include UrlHelpers }.new, UrlHelpers)
  end
end

class Business::EmuNavigationTabsTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @owner = create :emu, :owner, login: "owner"
    @business = @owner.enterprise_managed_business
    @member = create :emu, business: @business
    @enterprise_security_manager = create :emu, business: @business

    @billing_manager = create :emu, business: @business
    @business.billing.add_manager @billing_manager, actor: @owner

    @org = create :organization, business: @business, admin: @owner, plan: "bronze"
    @org.add_member @member

    enterprise_security_manager_team = create :enterprise_security_manager_team, business: @business
    @org.add_member @enterprise_security_manager # Because the factory doesn't set up the org teams sync
    enterprise_security_manager_team.bulk_add_members(users: [@enterprise_security_manager])
  end

  setup do
    enable_feature_flag(:batch_business_org_abilities)
    Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
    Business.any_instance.stubs(:advanced_security_policy_feature_enabled?).returns(true)
    disable_feature_flag(:actions_usage_metrics_enterprise)
    if TestEnv.test_all_features?
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      EnterpriseTeam.stubs(:enabled_for_organization_security_manager?).returns(true)
    end
  end

  context "when current_user is an owner" do
    test "renders menu items appropriately on dotcom when the business hasn't purchased GHAS" do
      Business.any_instance.stubs(:advanced_security_purchased?).returns(false)

      tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
      actual_tabs = tabs_builder.tabs.map(&:text)

      assert_equal ["Overview", "Organizations", "People", "Identity provider", "Policies", "GitHub Connect", "Security", "Settings", "Compliance"], actual_tabs
    end

    test "renders menu items appropriately on dotcom when business is basic" do
      @business.update_attribute :seats_plan_type, :basic
      EnterpriseTeam.stubs(:enabled_for_organization_security_manager?).returns(true)

      tabs_builder = Business::NavigationTabs.new(@business, current_user: @owner)
      actual_tabs = tabs_builder.tabs.map(&:text)

      assert_equal ["Overview", "Getting started", "People", "Identity provider", "Policies", "Settings", "Compliance"], actual_tabs

      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @owner,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 1,
      )
      assert_selector("a", text: "Enterprise teams")
      assert_selector("a", text: "Security managers")
      refute_selector("a", text: (@business.emu_repository_collaborators_enabled? ? "repository collaborators" : GitHub.outside_collaborators_flavor).capitalize)
    end

    test "renders Enterprise teams submenu when full EMU and sync to org enabled" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @owner,
          business: @business,
          sidebar_section: :people,
        ),
        allowed_queries: 1,
      )

      assert_selector "a", text: "Enterprise teams"
    end

    test "shows single sign-on configuration submenu" do
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @owner,
          business: @business,
          sidebar_section: :identity_provider,
        ),
        allowed_queries: 1,
      )
      assert_selector "a", text: "Groups"
      assert_selector "a", text: "Single sign-on configuration"
    end
  end

  context "when current_user is billing manager" do
    test "renders menu items appropriately on dotcom" do
      GitHub.stubs(:billing_enabled?).returns(true)

      tabs_builder = Business::NavigationTabs.new(@business, current_user: @billing_manager)
      actual_tabs = tabs_builder.tabs.map(&:text)

      assert_equal %w[Overview Settings], actual_tabs
    end

    test "renders sub-menu items appropriately on dotcom" do
      GitHub.stubs(:billing_enabled?).returns(true)

      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @billing_manager,
          business: @business,
          sidebar_section: :settings,
        ),
        allowed_queries: 3,
      )

      assert_selector "a", text: "Enterprise licensing"
    end
  end

  context "when current_user is an enterprise security manager" do
    test "renders menu and sub menu items appropriately" do
      tabs_builder = Business::NavigationTabs.new(@business, current_user: @enterprise_security_manager)
      actual_tabs = tabs_builder.tabs.map(&:text)

      if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
        assert_equal %w[Overview Organizations People Policies Security], actual_tabs
      else
        assert_equal %w[Overview Organizations Policies Security Settings], actual_tabs
      end

      unless EnterpriseTeam.enabled_for_organization_security_manager?(@business)
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @enterprise_security_manager,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 3,
        )
        assert_selector "a", text: "Advanced Security"
      end

      if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @enterprise_security_manager,
            business: @business,
            sidebar_section: :people,
          ),
          allowed_queries: 3,
        )
        assert_selector "a", text: "Enterprise teams"
        assert_selector "a", text: "Security managers"
      end
    end

    test "renders menu items appropriately on dotcom when the business hasn't purchased GHAS" do
      Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
      tabs_builder = Business::NavigationTabs.new(@business, current_user: @enterprise_security_manager)
      actual_tabs = tabs_builder.tabs.map(&:text)

      if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
        assert_equal %w[Overview Organizations People Policies Security], actual_tabs
      else
        assert_equal %w[Overview Organizations Policies Security Settings], actual_tabs
      end

      unless EnterpriseTeam.enabled_for_organization_security_manager?(@business)
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @enterprise_security_manager,
            business: @business,
            sidebar_section: :settings,
          ),
          allowed_queries: 3,
        )
        assert_selector "a", text: "Advanced Security"
      end

      if EnterpriseTeam.enabled_for_organization_security_manager?(@business)
        render_inline(
          Businesses::GlobalSidebarComponent.new(
            user: @enterprise_security_manager,
            business: @business,
            sidebar_section: :people,
          ),
          allowed_queries: 3,
        )
        assert_selector "a", text: "Enterprise teams"
        assert_selector "a", text: "Security managers"
      end
    end
  end
end unless GitHub.single_business_environment?
