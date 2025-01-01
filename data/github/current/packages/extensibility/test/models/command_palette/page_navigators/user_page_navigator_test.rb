# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module PageNavigators
    class UserPageNavigatorTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      setup do
        @user = build(:user)
      end

      context "unscoped context" do
        test "returns empty array" do
          unscoped_context = build_context(current_user: @user)
          navigator = UserPageNavigator.new(unscoped_context)
          assert_predicate navigator.items, :empty?
        end
      end

      context "scoped context" do
        test "returns valid items" do
          scoped_context = build_context(current_user: @user, scope: @user)
          navigator = UserPageNavigator.new(scoped_context)
          navigator.items.each do |item|
            assert_result_structure(item)
          end
        end

        test "first item is a link to the user" do
          scoped_context = build_context(current_user: @user, scope: @user)
          navigator = UserPageNavigator.new(scoped_context)
          first_item = navigator.items.first

          assert_equal "@#{@user.login}", first_item.title
          assert_equal "pages", first_item.group
          assert_equal "Jump to", first_item.hint
          assert_result_structure(first_item)
        end
      end
    end
  end
end
