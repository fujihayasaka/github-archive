# typed: true
# frozen_string_literal: true

require "test_helper"

module Conduit
  module TopicFeed
    class Resources::LanguageReposTest < GitHub::TestCase
      include DogstatsTestHelpers

      fixtures do
        @viewer = create(:user)

        @js = create(:javascript_language_name)
        @ruby = create(:ruby_language_name)
        @many_stars_repo = create(:repository, primary_language: @js, stargazer_count: 100)
        @few_stars_repo = create(:repository, primary_language: @js, stargazer_count: 1)
        @ruby_repo = create(:repository, primary_language: @ruby)
      end

      test "finds language repos when language is present" do
        Resources::LanguageRepos.stub_const(:NUM_REPOS, 1) do
          repos = Resources::LanguageRepos.new(viewer: @viewer, language: @js).collect

          assert_includes repos, @many_stars_repo
          refute_includes repos, @few_stars_repo
          refute_includes repos, @ruby_repo
        end

        assert_dogstats_distribution(1, "topic_feed_resource_collector.top_language_repos")
      end

      test "returns empty array when language is not present" do
        repos = Resources::LanguageRepos.new(viewer: @viewer, language: nil).collect
        assert_empty repos
      end
    end
  end
end
