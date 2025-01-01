# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRepositoriesUsingDependenciesLoaderTest < GitHub::TestCase
  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    @dependency_id = 1
    @loader = Repository::RepositoriesUsingDependenciesLoader.new(
      owner_id: 1,
      dependency_ids: [@dependency_id],
    )
  end

  context "#async_usage_counts_by_dependency" do
    test "returns a Promise of a hash of repo counts for each dependency" do
      repo_owner = create(:user)
      repo_using_dependency1 = create(:repository, owner: repo_owner)
      other_repo_using_dependency1 = create(:repository, owner: repo_owner)
      repo_using_dependency2 = create(:repository, owner: repo_owner)
      dependency1, dependency2, dependency3 = create_list(:repository, 3)

      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoriesUsingDependencies: [
          {
            dependencyId: dependency1.id,
            repositories: [repo_using_dependency1.id, other_repo_using_dependency1.id],
          },
          { dependencyId: dependency2.id, repositories: [repo_using_dependency2.id] },
          { dependencyId: dependency3.id, repositories: nil },
        ] },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = Repository::RepositoriesUsingDependenciesLoader.new(
        owner_id: repo_owner.id,
        dependency_ids: [dependency1.id, dependency2.id, dependency3.id],
      )

      result = loader.async_usage_counts_by_dependency(viewer: repo_owner).sync

      assert_equal({ dependency1 => 2, dependency2 => 1, dependency3 => 0 }, result)
    end

    test "does not count repositories the viewer can't see" do
      org = create(:organization, plan: "silver")
      org.update_default_repository_permission(:none, actor: org.admins.first)
      org_member = create(:user)
      non_visible_repo_using_dependency = create(:private_repository, owner: org)
      org.add_member(org_member)
      refute non_visible_repo_using_dependency.readable_by?(org_member),
        "need private org repo to not be visible to the org member"
      dependency = create(:repository)

      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: {
          repositoriesUsingDependencies: [{
            dependencyId: dependency.id,
            repositories: [non_visible_repo_using_dependency.id],
          }],
        },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

      loader = Repository::RepositoriesUsingDependenciesLoader.new(owner_id: org.id, dependency_ids: [dependency.id])

      result = loader.async_usage_counts_by_dependency(viewer: org_member).sync

      assert_equal({ dependency => 0 }, result)
    end
  end
end
