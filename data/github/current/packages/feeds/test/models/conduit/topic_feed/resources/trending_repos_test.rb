# typed: true
# frozen_string_literal: true

require "test_helper"

module Conduit
  module TopicFeed
    class Resources::TrendingReposTest < GitHub::TestCase
      include DogstatsTestHelpers

      fixtures do
        @viewer = create(:user)
      end

      test "returns an empty list when language is nil" do
        repo = create(:trending_repository)
        create(:topic, name: "javascript")
        GitHub.munger.stubs(trending_repositories: [{ "repository_id" => repo.id }])

        repos = Resources::TrendingRepos.new(viewer: @viewer, language: nil).collect

        assert_empty repos
      end

      test "finds trending repositories when a language is present" do
        js = create(:javascript_language_name)
        create(:topic, name: "javascript")
        repo = create(:trending_repository)

        GitHub.munger.stubs(trending_repositories: [{ "repository_id" => repo.id }])

        repos = Resources::TrendingRepos.new(viewer: @viewer, language: js).collect

        assert_includes repos.map(&:id), repo.id
        assert_dogstats_distribution(1, "topic_feed_resource_collector.trending_repos")
      end
    end
  end
end
