# typed: true
# frozen_string_literal: true

require "test_helper"
class  Businesses::GlobalSidebarComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @user = create(:user)
    @business = create(:business, owners: [@user])
  end

  # For section specific tests, visit:
  # packages/enterprise_navigation/test/components/businesses/sidebar_component/

  test "does not render a sidebar when section is none" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :none,
        test_selector: "global-sidebar",
      ),
      allowed_queries: 1,
    )
    refute_test_selector("global-sidebar")
  end

  test "does not render a sidebar when section is unknown" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        test_selector: "global-sidebar",
      ),
      allowed_queries: 1,
    )
    refute_test_selector("global-sidebar")
  end

  test "does not render if db error is thrown" do
    Business.any_instance.stubs(:owner?).raises(GitHub::KV::UnavailableError)
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :people,
        test_selector: "global-sidebar",
      ),
      allowed_queries: 1,
    )
    refute_component_rendered
  end

  test "renders a named sidebar" do
    render_inline(
      Businesses::GlobalSidebarComponent.new(
        user: @user,
        business: @business,
        sidebar_section: :people,
        test_selector: "global-sidebar",
      ),
      allowed_queries: 1,
    )
    assert_test_selector("global-sidebar")
    assert_test_selector("people-sidebar")
  end
end
