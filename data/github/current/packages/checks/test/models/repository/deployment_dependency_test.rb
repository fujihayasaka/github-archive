# typed: true
# frozen_string_literal: true

require "set"
require "test_helper"

class RepositoryDeploymentDependencyTest < GitHub::TestCase
  context "environments" do
    test "returns the environments for a repository" do
      repo = create(:repository)
      env1 = create(:environment, repository: repo)
      env2 = create(:environment, repository: repo)

      assert_equal 2, repo.environments.size
      assert_equal Set[env1.id, env2.id], repo.environments.map { |e| e.id }.to_set
    end
  end
end
