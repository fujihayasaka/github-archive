# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Results
    class IssueResultTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers
      fixtures do
        @user = create(:user)
        @issue = create(:issue)
      end

      context "when the scope is within the owner repo" do
        test "doesn't have a subtitle" do
          context = build_context(current_user: @user, scope: @issue.repository)
          result = IssueResult.create(@issue, 1, context)
          assert_nil result.as_json[:subtitle]
          assert_result_structure result
        end
      end

      context "when scope is not the same as the onwer repo" do
        test "has a subtitle" do
          context = build_context(current_user: @user, scope: nil)
          result = IssueResult.create(@issue, 1, context)
          refute_nil result.as_json[:subtitle]
          assert_result_structure result
        end
      end

      test "has a default group" do
        context = build_context(current_user: @user, scope: nil)
        result = IssueResult.create(@issue, 1, context)
        assert_equal :references, result.as_json[:group]
      end

      context "overrides the group" do
        test "uses the provided group" do
          context = build_context(current_user: @user, scope: nil)
          result = IssueResult.create(@issue, 1, context, :this_page)
          assert_equal :this_page, result.as_json[:group]
        end
      end

      test "doesn't have a scope when subject != issue" do
        context = build_context(current_user: @user, scope: nil)
        result = IssueResult.create(@issue, 1, context, :this_page)
        assert_nil result.as_json[:scope]
      end

      test "has a scope when subject == issue" do
        context = build_context(current_user: @user, scope: nil, subject: @issue)
        result = IssueResult.create(@issue, 1, context, :this_page)

        expected = CommandPalette::ResultToken.new(
          id: @issue.global_relay_id,
          type: "issue",
          text: "#{@issue.class.name.underscore.humanize.pluralize} ##{@issue.number}"
        )
        assert_equal(expected.as_json, result.as_json[:scope].as_json[:tokens].last.as_json)
      end
    end
  end
end
