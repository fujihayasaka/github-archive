# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Results
    class ProjectResultTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      setup do
        @user = build(:user)
        @org = build(:organization, admin: @user)
        @repo = build(:repository, owner: @org)
        @empty_context = build_context(current_user: @user)
      end

      context "repo project" do
        test "creates a valid result" do
          project = build(:project, owner: @repo)
          result = ProjectResult.create(project, 1, @empty_context)
        end
      end

      context "org project" do
        test "creates a valid result" do
          project = build(:project, owner: @org)
          result = ProjectResult.create(project, 1, @empty_context)
        end
      end

      context "user project" do
        test "creates a valid result" do
          project = build(:project, owner: @user)
          result = ProjectResult.create(project, 1, @empty_context)
        end
      end


      context "when scope is the same as the project owner" do
        test "doesn't have a subtitle" do
          project = build(:project, owner: @org)
          context = build_context(current_user: @user, scope: @org)
          result = ProjectResult.create(project, 1, context)
          assert_nil result.as_json[:subtitle]
          assert_result_structure result
        end
      end

      context "when scope is not the same as the memex org" do
        test "has a subtitle" do
          project = build(:project, owner: @org)
          context = build_context(current_user: @user, scope: @repo)
          result = ProjectResult.create(project, 1, context)
          refute_nil result.as_json[:subtitle]
          assert_result_structure result
        end
      end

      test "has a default group" do
        project = build(:project, owner: @repo)
        context = build_context(current_user: @user, scope: nil)
        result = ProjectResult.create(project, 1, @empty_context)
        assert_equal :projects, result.as_json[:group]
      end

      context "overrides the group" do
        test "uses the provided group" do
          project = build(:project, owner: @repo)
          context = build_context(current_user: @user, scope: nil)
          result = ProjectResult.create(project, 1, @empty_context, :this_page)
          assert_equal :this_page, result.as_json[:group]
        end
      end
    end
  end
end
