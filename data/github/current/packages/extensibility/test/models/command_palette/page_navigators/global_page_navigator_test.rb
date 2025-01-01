# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module PageNavigators
    class GlobalPageNavigatorTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      setup do
        @user = build(:user)
      end

      context "unscoped context" do
        test "returns valid items" do
          unscoped_context = build_context(current_user: @user)
          navigator = GlobalPageNavigator.new(unscoped_context)
          navigator.items.each do |item|
            assert_result_structure(item)
          end

          expected_items = GitHub.enterprise? ? 39 : 43
          assert_equal expected_items, navigator.items.count
        end

        test "copilot links" do
          unscoped_context = build_context(current_user: @user)
          navigator = GlobalPageNavigator.new(unscoped_context)

          if GitHub.enterprise?
            refute_includes navigator.items.map(&:title), "Copilot"
            refute_includes navigator.items.map(&:title), "Models"
          else
            assert_includes navigator.items.map(&:title), "Copilot"
          end
        end

        unless GitHub.enterprise?
          context "model links" do
            test "includes models link" do
              unscoped_context = build_context(current_user: @user)
              navigator = GlobalPageNavigator.new(unscoped_context)
              assert_includes navigator.items.map(&:title), "Models"
              assert_equal 43, navigator.items.count
            end
          end
        end
      end

      context "scoped context" do
        test "return no global results" do
          scoped_context = build_context(current_user: @user, scope: @user)
          navigator = GlobalPageNavigator.new(scoped_context)
          assert_empty navigator.items
        end
      end
    end
  end
end
