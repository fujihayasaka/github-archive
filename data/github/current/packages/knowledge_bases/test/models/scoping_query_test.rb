# typed: true
# frozen_string_literal: true

require "test_helper"

class ScopingQueryTest < GitHub::TestCase
  context "#from_source_repositories" do
    test "returns the scoping query for a single source respository" do
      repo = create(:repository)
      source_repos = [{ id: repo.id, owner_id: repo.owner_id, paths: [] }]

      scoping_query = KnowledgeBase::ScopingQuery.from_source_repositories(source_repos:)

      assert_equal "repo:#{repo.nwo}", scoping_query
    end

    test "returns the scoping query for multiple source repositories" do
      repo1 = create(:repository)
      repo2 = create(:repository)
      repo3 = create(:repository)

      source_repos = [repo1, repo2, repo3].map do |repo|
        source_repo = { id: repo.id, owner_id: repo.owner_id, paths: [] }
      end

      scoping_query = KnowledgeBase::ScopingQuery.from_source_repositories(source_repos:)

      assert_equal "repo:#{repo1.nwo} OR repo:#{repo2.nwo} OR repo:#{repo3.nwo}", scoping_query
    end

    test "returns the scoping query for a source repository with multiple file paths" do
      repo = create(:repository)
      paths = ["docs", "README.*"]
      source_repos = [{ id: repo.id, owner_id: repo.owner_id, paths: paths }]

      scoping_query = KnowledgeBase::ScopingQuery.from_source_repositories(source_repos:)

      assert_equal "(repo:#{repo.nwo} (path:#{paths[0]} OR path:#{paths[1]}))", scoping_query
    end

    test "returns the scoping query for multiple source repositories with multiple file paths" do
      repo1 = create(:repository)
      repo2 = create(:repository)
      repo3 = create(:repository)

      source_repos = [
        { id: repo1.id, owner_id: repo1.owner_id, paths: ["docs/api", "dev/*/**"] },
        { id: repo2.id, owner_id: repo2.owner_id, paths: ["README.*"] },
        { id: repo3.id, owner_id: repo3.owner_id, paths: [] }
      ]

      scoping_query = KnowledgeBase::ScopingQuery.from_source_repositories(source_repos:)

      expected_scoping_query =
        "(repo:#{repo1.nwo} (path:docs/api OR path:dev/*/**)) OR (repo:#{repo2.nwo} (path:README.*)) OR repo:#{repo3.nwo}"
      assert_equal expected_scoping_query, scoping_query
    end
  end

  context "#repository_paths" do
    test "returns a single source repository" do
      repo = create(:repository)
      query = "repo:#{repo.name_with_display_owner}"

      source_repos = KnowledgeBase::ScopingQuery.new(query:).source_repositories

      assert_equal 1, source_repos.length
      assert_same_elements([
        { id: repo.id, owner_id: repo.owner_id, paths: [] },
      ], source_repos)
    end

    test "returns a source repository with paths" do
      repo = create(:repository)
      path1 = "docs/api"
      path2 = "dev/*/**"
      query = "(repo:#{repo.name_with_display_owner} (path:#{path1} OR path:#{path2}))"

      source_repos = KnowledgeBase::ScopingQuery.new(query:).source_repositories

      assert_equal 1, source_repos.length
      assert_same_elements([
        { id: repo.id, owner_id: repo.owner_id, paths: [path1, path2] },
      ], source_repos)
    end

    test "returns multiple source repositories" do
      repo1 = create(:repository)
      repo2 = create(:repository)
      query = "repo:#{repo1.name_with_display_owner} OR repo:#{repo2.name_with_display_owner}"

      source_repos = KnowledgeBase::ScopingQuery.new(query:).source_repositories

      assert_equal 2, source_repos.length
      assert_same_elements([
        { id: repo1.id, owner_id: repo1.owner_id, paths: [] },
        { id: repo2.id, owner_id: repo2.owner_id, paths: [] }
      ], source_repos)
    end

    test "returns multiple source repositories with paths" do
      repo1 = create(:repository)
      repo2 = create(:repository)
      path1 = "docs/api"
      path2 = "dev/*/**"
      query = "(repo:#{repo1.name_with_display_owner} path:#{path1} OR path:#{path2}) OR (repo:#{repo2.name_with_display_owner} path:#{path2})"

      source_repos = KnowledgeBase::ScopingQuery.new(query:).source_repositories

      assert_equal 2, source_repos.length
      assert_same_elements([
        { id: repo1.id, owner_id: repo1.owner_id, paths: [path1, path2] },
        { id: repo2.id, owner_id: repo2.owner_id, paths: [path2] }
      ], source_repos)
    end

    test "returns an empty scoping query when repo cannot be found" do
      source_repos = [{ id: 7, owner_id: 10, paths: [] }]

      scoping_query = KnowledgeBase::ScopingQuery.from_source_repositories(source_repos:)

      assert_equal "", scoping_query
    end

    test "returns the scoping query when a repo cannot be found and other repositories exist" do
      repo = create(:repository)
      source_repos = [{ id: 7, owner_id: 10, paths: [] }, { id: repo.id, owner_id: repo.owner_id, paths: [] }]

      scoping_query = KnowledgeBase::ScopingQuery.from_source_repositories(source_repos:)

      assert_equal "repo:#{repo.nwo}", scoping_query
    end
  end
end
