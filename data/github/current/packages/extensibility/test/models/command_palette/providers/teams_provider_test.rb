# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  module Providers
    class TeamsProviderTest < GitHub::TestCase
      include GitHub::CommandPaletteTestHelpers

      fixtures do
        @user = create :user
        @org = create :organization
        @pull_team = create :team, organization: @org, permission: "pull", name: "Pull", privacy: :closed
        @pull_team2 = create :team, organization: @org, permission: "pull", name: "Pull2"
        @pull_team3 = create :team, organization: @org, permission: "pull", name: "Sassy Waffle", privacy: :closed
        @pull_team2.add_member @user
      end

      test "doesn't perform search without scope" do
        provider = build_provider(TeamsProvider, current_user: @user)

        results = provider.search("Pull")

        assert_equal 0, results.size
      end

      test "search with org name returns team name" do
        provider = build_provider(TeamsProvider, current_user: @user, scope: @org)

        results = provider.search("#{@org.login}/Pull2")

        assert_equal [@pull_team2.id], results.map(&:object).map(&:id)
      end

      test "prioritizes teams user is a member of" do
        provider = build_provider(TeamsProvider, current_user: @user, scope: @org)

        results = provider.search("Pull")

        assert_equal [@pull_team2.id, @pull_team.id], results.sort_by(&:priority).reverse.map(&:object).map(&:id)
      end
    end
  end
end
