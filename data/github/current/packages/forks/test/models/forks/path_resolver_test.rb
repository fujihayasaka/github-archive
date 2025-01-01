# typed: true
# frozen_string_literal: true

require "test_helper"

class Forks::PathResolverTest < GitHub::TestCase
  include Forks::FixtureHelpers

  DEFAULT_PATH = "/owner/repo/forks?include=active&page=1&period=2y&sort_by=stargazer_counts"
  context "#to_path" do
    test "default options" do
      assert_equal DEFAULT_PATH, path_resolver.to_path
    end

    context "When period is nil" do
      context "and :forks_view_unbound_period is enabled" do
        test "the period is nil in the returned path" do
          expected = DEFAULT_PATH.sub("period=2y", "period=")
          assert_equal expected, path_resolver(period: nil, enabled_features: [:unbound_period]).to_path
        end
      end

      context "and :forks_view_unbound_period is disabled" do
        test "the default path is still returned" do
          assert_equal DEFAULT_PATH, path_resolver(period: nil, enabled_features: []).to_path
        end
      end
    end


    test "returns an updated URL with mixed overrides" do
      expected = "/owner/repo/forks?include=active%2Cinactive&page=2&period=1mo&sort_by=last_updated"
      assert_equal expected, path_resolver(include: [:active, :inactive], page: 2, period: "1mo", sort_by: :last_updated).to_path
    end
  end

  context "#next_path" do
    test "it overlays new options on top of previous options" do
      show_inactive = path_resolver(include: [:active, :inactive])
      # Preliminary baselines
      expected = DEFAULT_PATH.sub("include=active", "include=active%2Cinactive")
      assert_equal expected, show_inactive.next_path

      expected = expected.sub("period=2y", "period=1mo")
      assert_equal expected, show_inactive.next_path(period: "1mo")
    end
  end
end
