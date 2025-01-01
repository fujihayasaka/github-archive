# typed: true
# frozen_string_literal: true

require "test_helper"

class Businesses::SettingsSidebarComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers
  include GitHub::Memoizer

  fixtures do
    @user = create(:user)
    @business = create(:business, owners: [@user])
    SecurityProduct::Permissions::BusinessAuthz.any_instance.stubs(:can_view_code_security_settings?).returns(true)
  end

  test "renders a settings sidebar" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
  end

  test "Profile link" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Profile") do |link|
      assert_equal urls.settings_profile_enterprise_path(@business), link[:href]
    end
  end

  test "Billing link" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Billing") do |link|
      assert_equal urls.settings_billing_enterprise_path(@business), link[:href]
    end
  end if GitHub.billing_enabled?

  test "Packages link" do
    GitHub.stubs(:subdomain_isolation?).returns(true)
    GitHub.stubs(:registry_v2_enabled_for_enterprise?).returns(true)
    Registry::Package.stubs(:any_package_exists).with("docker").returns(Registry::Package.none.tap { |r| r.stubs(:count).returns(1) })

    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Packages") do |link|
      assert_equal urls.settings_packages_migration_enterprise_path(@business), link[:href]
    end
  end

  test "Authentication security link" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Authentication security") do |link|
      assert_equal urls.settings_security_enterprise_path(@business), link[:href]
    end
  end

  test "Advanced Security link" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Advanced Security") do |link|
      assert_equal urls.settings_security_analysis_enterprise_path(@business), link[:href]
    end
  end

  test "Verified & approved domains link" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Verified & approved domains") do |link|
      assert_equal urls.settings_enterprise_domains_enterprise_path(@business), link[:href]
    end
  end

  test "Audit log link" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Audit log") do |link|
      assert_equal urls.settings_audit_log_enterprise_path(@business), link[:href]
    end
  end

  test "Retired namespaces link is rendered for multi-tenant enterprises" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      without_query_count: true,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Retired namespaces") do |link|
      assert_equal urls.settings_retired_namespaces_enterprise_path(@business), link[:href]
    end
  end if TestEnv.test_in_multitenancy_mode?

  test "Retired namespaces link is not rendered for single-tenant enterprises" do
    GitHub.stubs(:multi_tenant_enterprise?).returns(false)

    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      without_query_count: true,
    )
    assert_test_selector("settings-sidebar")
    refute_selector("a", text: "Retired namespaces")
  end

  test "Hooks link" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Hooks") do |link|
      assert_equal urls.hooks_enterprise_path(@business), link[:href]
    end
  end

  test "Hosted compute networking link" do
    GitHub.stubs(:single_business_environment?).returns(false)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Hosted compute networking") do |link|
      assert_equal urls.settings_network_configurations_path(@business), link[:href]
    end
  end

  test "GitHub Insights link" do
    GitHub.stubs(:insights_available?).returns(true)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "GitHub Insights") do |link|
      assert_equal urls.settings_enterprise_insights_path(@business), link[:href]
    end
  end

  test "GitHub Apps link" do
    enable_feature_flag(:enterprise_app_installation_management)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "GitHub Apps") do |link|
      assert_equal urls.settings_apps_enterprise_path(@business), link[:href]
    end
  end

  test "Announcement link" do
    GitHub.stubs(:single_business_environment?).returns(false)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Announcement") do |link|
      assert_equal urls.edit_announcement_enterprise_path(@business), link[:href]
    end
  end

  test "Support link" do
    GitHub.stubs(:single_business_environment?).returns(false)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Support") do |link|
      assert_equal urls.enterprise_support_index_path(@business), link[:href]
    end
  end

  if GitHub.single_business_environment?
    test "Messages link" do
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :settings,
        ),
        allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
      )
      assert_test_selector("settings-sidebar")
      assert_selector("a", text: "Messages") do |link|
        assert_equal urls.custom_messages_enterprise_path(@business), link[:href]
      end
    end

    test "Site admin link" do
      render_inline(
        Businesses::GlobalSidebarComponent.new(
          user: @user,
          business: @business,
          sidebar_section: :settings,
        ),
        allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
      )
      assert_test_selector("settings-sidebar")
      assert_selector("a", text: "Site admin") do |link|
        assert_equal urls.stafftools_path, link[:href]
      end
    end
  end

  test "Linked accounts link" do
    enable_feature_flag(:enterprise_linked_accounts)
    Business.any_instance.stubs(:enterprise_managed_user_enabled?).returns(true)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Linked accounts") do |link|
      assert_equal urls.settings_linked_accounts_enterprise_path(@business), link[:href]
    end
  end

  test "Does not render Enterprise licensing link when billing tab is visible", skip_enterprise: true do
    @business.customer.update!(billed_via_billing_platform: true)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: 5,
    )
    assert_test_selector("settings-sidebar")
    refute_selector("a", text: "Enterprise licensing")
  end if GitHub.billing_enabled?

  test "Enterprise licensing link", skip_enterprise: true do
    @business.customer.update!(billed_via_billing_platform: false)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: 2,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Enterprise licensing") do |link|
      assert_equal urls.enterprise_licensing_path(@business), link[:href]
    end
  end unless TestEnv.test_in_multitenancy_mode?

  test "Networking link" do
    GitHub.stubs(:single_business_environment?).returns(false)
    enable_feature_flag(:codespaces_vnet_settings)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :settings,
      ),
      allowed_queries: GitHub.multi_tenant_enterprise? ? 2 : 3,
    )
    assert_test_selector("settings-sidebar")
    assert_selector("a", text: "Networking") do |link|
      assert_equal urls.settings_virtual_networks_path(@business), link[:href]
    end
  end


  sig { returns(UrlHelpers) }
  memoize def urls
    T.cast(Class.new { include UrlHelpers }.new, UrlHelpers)
  end
end
