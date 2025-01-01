# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Results
    class RepositoryResultTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @user = create(:user)
        @repo = create(:repository)
      end

      context "no scope" do
        test "doesn't have a typehead override" do
          context = build_context(current_user: @user)

          result = Result.jump_to(@repo, context: context)
          assert_nil result.typeahead
          assert_result_structure result
        end
      end

      context "same owner as scope" do
        test "has a typehead override" do
          context = build_context(current_user: @user, scope: @repo.owner)

          result = Result.jump_to(@repo, context: context)
          assert_equal @repo.name, result.typeahead
          assert_result_structure result
        end

        test "has a match fields override" do
          context = build_context(current_user: @user, scope: @repo.owner)

          result = Result.jump_to(@repo, context: context)
          assert_equal [@repo.name, "/#{@repo.name}"], result.match_fields
        end
      end

      test "has a default group" do
        context = build_context(current_user: @user, scope: nil)
        result = Result.jump_to(@repo, context: context)
        assert_equal :repositories, result.as_json[:group]
      end

      context "overrides the group" do
        test "uses the provided group" do
          context = build_context(current_user: @user, scope: nil)
          result = Result.jump_to(@repo, context: context, group: :this_page)
          assert_equal :this_page, result.as_json[:group]
        end
      end
    end
  end
end
