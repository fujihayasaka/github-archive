# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Results
    class MemexProjectResultTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @org = create(:organization)
        @repo = create(:repository, owner: @org)
        @user = create(:user)
        @memex_project = create(:memex_project, :with_linked_repo, owner: @org, repo: @repo)
      end

      context "when scope is the same as the memex org" do
        test "doesn't have a subtitle" do
          context = build_context(current_user: @user, scope: @org)
          result = MemexProjectResult.create(@memex_project, 1, context)
          assert_nil result.as_json[:subtitle]
          assert_result_structure result
        end
      end

      context "when scope is not the same as the memex org" do
        test "has a subtitle" do
          context = build_context(current_user: @user)
          result = MemexProjectResult.create(@memex_project, 1, context)
          refute_nil result.as_json[:subtitle]
          assert_result_structure result
        end
      end

      test "has a default group" do
        context = build_context(current_user: @user, scope: nil)
        result = MemexProjectResult.create(@memex_project, 1, context)
        assert_equal :memex_projects, result.as_json[:group]
      end

      context "overrides the group" do
        test "uses the provided group" do
          context = build_context(current_user: @user, scope: nil)
          result = MemexProjectResult.create(@memex_project, 1, context, :this_page)
          assert_equal :this_page, result.as_json[:group]
        end
      end

      test "doesn't have a scope when subject != memexproject" do
        context = build_context(current_user: @user, scope: nil)
        result = MemexProjectResult.create(@memex_project, 1, context, :this_page)
        assert_nil result.as_json[:scope]
      end

      test "has a scope when subject == memex_project" do
        context = build_context(current_user: @user, scope: nil, subject: @memex_project)
        result = MemexProjectResult.create(@memex_project, 1, context, :this_page)

        expected = CommandPalette::ResultToken.new(
          id: @memex_project.global_relay_id,
          type: "memex_project",
          text: "Project ##{@memex_project.number}"
        )
        assert_equal(expected.as_json, result.as_json[:scope].as_json[:tokens].last.as_json)
      end

      context "in a repository context" do
        test "doesn't have a subtitle" do
          context = build_context(current_user: @user, scope: @repo)
          result = MemexProjectResult.create(@memex_project, 1, context)
          assert_nil result.as_json[:subtitle]
          assert_result_structure result
        end
      end
    end
  end
end
