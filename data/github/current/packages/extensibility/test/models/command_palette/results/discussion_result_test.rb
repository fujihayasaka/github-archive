# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Results
    class DiscussionResultTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers
      fixtures do
        @user = create(:user)
        @discussion = create(:discussion)
      end

      context "when the scope is within the owner repo" do
        test "doesn't have a subtitle" do
          context = build_context(current_user: @user, scope: @discussion.repository)
          result = DiscussionResult.create(@discussion, 1, context)
          assert_nil result.as_json[:subtitle]
          assert_result_structure result
        end
      end

      context "when scope is not the same as the onwer repo" do
        test "has a subtitle" do
          context = build_context(current_user: @user, scope: nil)
          result = DiscussionResult.create(@discussion, 1, context)
          refute_nil result.as_json[:subtitle]
          assert_result_structure result
        end
      end

      test "has a default group" do
        context = build_context(current_user: @user, scope: nil)
        result = DiscussionResult.create(@discussion, 1, context)
        assert_equal :references, result.as_json[:group]
      end

      context "overrides the group" do
        test "uses the provided group" do
          context = build_context(current_user: @user, scope: nil)
          result = DiscussionResult.create(@discussion, 1, context, :this_page)
          assert_equal :this_page, result.as_json[:group]
        end
      end

      test "doesn't have a scope when subject != discussion" do
        context = build_context(current_user: @user, scope: nil)
        result = DiscussionResult.create(@discussion, 1, context, :this_page)
        assert_nil result.as_json[:scope]
      end

      test "has a scope when subject == discussion" do
        context = build_context(current_user: @user, scope: nil, subject: @discussion)
        result = DiscussionResult.create(@discussion, 1, context, :this_page)

        expected = CommandPalette::ResultToken.new(
          id: @discussion.global_relay_id,
          type: "discussion",
          text: "#{@discussion.class.name.underscore.humanize.pluralize} ##{@discussion.number}"
        )
        assert_equal(expected.as_json, result.as_json[:scope].as_json[:tokens].last.as_json)
      end
    end
  end
end
