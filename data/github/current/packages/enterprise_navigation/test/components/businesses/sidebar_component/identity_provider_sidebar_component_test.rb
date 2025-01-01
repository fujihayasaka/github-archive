# typed: true
# frozen_string_literal: true

require "test_helper"

class Businesses::IdentityProviderSidebarComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers
  include GitHub::Memoizer

  fixtures do
    @user = create(:user)
    @business = create(:business, owners: [@user])
  end

  setup do
    Business.any_instance.stubs(:enterprise_managed_user_enabled?).returns(true)
  end

  test "renders an identity provider sidebar" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :identity_provider,
      ),
      allowed_queries: 1,
    )
    assert_test_selector("identity-provider-sidebar")
  end

  test "SSO Configuration link is shown when enterprise managed user is enabled" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :identity_provider,
      ),
      allowed_queries: 1,
    )

    assert_test_selector("identity-provider-sidebar")
    assert_selector("a", text: "Single sign-on configuration") do |link|
      assert_equal urls.enterprise_single_sign_on_configuration_path(@business), link[:href]
    end
  end

  test "Groups link is always shown" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :identity_provider,
      ),
      allowed_queries: 1,
    )

    assert_test_selector("identity-provider-sidebar")
    assert_selector("a", text: "Groups") do |link|
      assert_equal urls.external_groups_enterprise_path(@business), link[:href]
    end
  end

  sig { returns(UrlHelpers) }
  memoize def urls
    T.cast(Class.new { include UrlHelpers }.new, UrlHelpers)
  end
end
