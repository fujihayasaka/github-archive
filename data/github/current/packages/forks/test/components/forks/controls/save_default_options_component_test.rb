# typed: true
# frozen_string_literal: true

require "test_helper"

class Forks::Controls::SaveDefaultOptionsComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers
  include Forks::FixtureHelpers

  setup do
    @user = create :user
    @path_resolver = path_resolver
    if GitHub.flipper[:forks_view_user_default_options].enabled?
      @path_resolver.options.enable_feature(:user_default_options)
    end
  end

  def component_with_options(**options)
    Forks::Controls::SaveDefaultOptionsComponent.new(@path_resolver, **options)
  end

  def refute_render(**options)
    render_inline component_with_options(**options)
    refute_test_selector "save-default-user-options"
  end

  def assert_render(**options)
    render_inline component_with_options(**options)
    assert_test_selector "save-default-user-options"
  end

  if GitHub.flipper[:forks_view_user_default_options].enabled?
    context "When the user default options feature flag is enabled" do
      context "and a user is logged in" do
        context "and controls are rendered" do
          test "it renders the component" do
            as @user
            assert_render
          end
        end
      end
    end

    context "and no user is logged in" do
      test "it does not render the component" do
        refute_render
      end
    end
  else
    context "When the user default options feature flag is disabled" do
      test "it does not render the component" do
        as @user
        refute_render
      end
    end
  end
end
