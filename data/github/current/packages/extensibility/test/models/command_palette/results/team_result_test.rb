# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Results
    class TeamResultTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
      fixtures do
        @user = create :user
        @org = create :organization
        @pull_team = create :team, organization: @org, permission: "pull", name: "My Team"
        @pull_team.add_member @user
        @context = build_context(current_user: @user)
      end

      test "builds a team result" do
        result = Result.jump_to(@pull_team, context: @context)

        assert_result_structure result
        assert_match /my-team/, result.title
        assert_equal result.group, :teams
        assert_equal result.object, @pull_team
      end

      test "has a default group" do
        context = build_context(current_user: @user, scope: nil)
        result = Result.jump_to(@pull_team, context: @context)
        assert_equal :teams, result.as_json[:group]
      end

      context "overrides the group" do
        test "uses the provided group" do
          context = build_context(current_user: @user, scope: nil)
          result = Result.jump_to(@pull_team, context: @context, group: :this_page)
          assert_equal :this_page, result.as_json[:group]
        end
      end
    end
  end
end
