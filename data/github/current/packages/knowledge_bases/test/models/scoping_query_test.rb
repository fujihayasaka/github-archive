# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopingQueryTest < GitHub::TestCase
  context "#build_scoping_query" do
    test "returns the scoping query for a single source respository" do
      repo = create(:repository)
      source_repos = [{ id: repo.id, ownerID: repo.owner_id, paths: [] }]

      scoping_query = KnowledgeBase::ScopingQuery.from_source_repositories(source_repos:)

      assert_equal "repo:#{repo.nwo}", scoping_query
    end

    test "returns the scoping query for multiple source repositories" do
      repo1 = create(:repository)
      repo2 = create(:repository)
      repo3 = create(:repository)

      source_repos = [repo1, repo2, repo3].map do |repo|
        source_repo = { id: repo.id, ownerID: repo.owner_id, paths: [] }
      end

      scoping_query = KnowledgeBase::ScopingQuery.from_source_repositories(source_repos:)

      assert_equal "repo:#{repo1.nwo} OR repo:#{repo2.nwo} OR repo:#{repo3.nwo}", scoping_query
    end

    test "returns the scoping query for a source repository with multiple file paths" do
      repo = create(:repository)
      paths = ["docs", "README.*"]
      source_repos = [{ id: repo.id, ownerID: repo.owner_id, paths: paths }]

      scoping_query = KnowledgeBase::ScopingQuery.from_source_repositories(source_repos:)

      assert_equal "(repo:#{repo.nwo} (path:#{paths[0]} OR path:#{paths[1]}))", scoping_query
    end

    test "returns the scoping query for multiple source repositories with multiple file paths" do
      repo1 = create(:repository)
      repo2 = create(:repository)
      repo3 = create(:repository)

      source_repos = [
        { id: repo1.id, ownerID: repo1.owner_id, paths: ["docs/api", "dev/*/**"] },
        { id: repo2.id, ownerID: repo2.owner_id, paths: ["README.*"] },
        { id: repo3.id, ownerID: repo3.owner_id, paths: [] }
      ]

      scoping_query = KnowledgeBase::ScopingQuery.from_source_repositories(source_repos:)

      expected_scoping_query =
        "(repo:#{repo1.nwo} (path:docs/api OR path:dev/*/**)) OR (repo:#{repo2.nwo} (path:README.*)) OR repo:#{repo3.nwo}"
      assert_equal expected_scoping_query, scoping_query
    end
  end
end
