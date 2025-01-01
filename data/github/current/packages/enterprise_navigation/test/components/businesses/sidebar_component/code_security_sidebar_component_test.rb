# typed: true
# frozen_string_literal: true

require "test_helper"

class Businesses::CodeSecuritySidebarComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers
  include GitHub::Memoizer

  fixtures do
    @user = create(:user)
    @business = create(:business, owners: [@user])
  end

  test "renders a code security sidebar" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :code_security,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("security-sidebar")
  end

  test "Code Security Overview link" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :code_security,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("security-sidebar")
    assert_selector("a", text: "Overview") do |link|
      assert_equal urls.enterprise_security_center_overview_dashboard_path(@business), link[:href]
    end
  end

  test "Risk link" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :code_security,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("security-sidebar")
    assert_selector("a", text: "Risk") do |link|
      assert_equal urls.security_center_risk_enterprise_path(@business), link[:href]
    end
  end

  test "Coverage link" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :code_security,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("security-sidebar")
    assert_selector("a", text: "Coverage") do |link|
      assert_equal urls.security_center_coverage_enterprise_path(@business), link[:href]
    end
  end

  test "Enablement trends link" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :code_security,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("security-sidebar")
    assert_selector("a", text: "Enablement trends") do |link|
      assert_equal urls.enterprise_security_center_metrics_enablement_path(@business), link[:href]
    end
  end

  test "CodeQL pull request alerts link" do
    SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(true)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :code_security,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("security-sidebar")
    assert_selector("a", text: "CodeQL pull request alerts") do |link|
      assert_equal urls.enterprise_security_center_metrics_codeql_path(@business), link[:href]
    end
  end

  test "Dependabot alerts link" do
    SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :code_security,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("security-sidebar")
    assert_selector("a", text: "Dependabot alerts") do |link|
      assert_equal urls.security_center_alerts_dependabot_enterprise_path(@business), link[:href]
    end
  end

  test "Secret scanning metrics link" do
    SecretScanning::Features::Business::TokenScanning.any_instance.stubs(:feature_available?).returns(true)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :code_security,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("security-sidebar")
    assert_selector("a", text: "Secret scanning metrics") do |link|
      assert_equal urls.enterprise_security_center_metrics_secret_scanning_path(@business), link[:href]
    end
  end

  sig { returns(UrlHelpers) }
  memoize def urls
    T.cast(Class.new { include UrlHelpers }.new, UrlHelpers)
  end
end
