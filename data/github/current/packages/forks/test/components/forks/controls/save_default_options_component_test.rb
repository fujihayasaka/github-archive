# typed: true
# frozen_string_literal: true

require "test_helper"

class Forks::Controls::SaveDefaultOptionsComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers
  include Forks::FixtureHelpers

  setup do
    @user = create :user
    @path_resolver = path_resolver
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
end
