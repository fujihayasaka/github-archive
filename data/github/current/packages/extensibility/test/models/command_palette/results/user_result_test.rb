# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Results
    class UserResultTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      setup do
        @user = build(:user)
        @context = build_context(current_user: @user)
      end

      test "does not priority weight if not current user" do
        assert_equal Result.jump_to(create(:user), context: @context).priority, 1
      end

      test "adds priority weight if current user" do
        assert_equal Result.jump_to(@user, context: @context).priority, 1 + Result::PRIORITY_WEIGHTS[:current_user]
      end

      test "typeahead is just the login" do
        assert_equal @user.login, Result.jump_to(@user, context: @context).typeahead
      end

      test "has a default group" do
        context = build_context(current_user: @user, scope: nil)
        result = Result.jump_to(@user, context: @context)
        assert_equal :users, result.as_json[:group]
      end

      context "overrides the group" do
        test "uses the provided group" do
          context = build_context(current_user: @user, scope: nil)
          result = Result.jump_to(@user, context: @context, group: :this_page)
          assert_equal :this_page, result.as_json[:group]
        end
      end
    end
  end
end
