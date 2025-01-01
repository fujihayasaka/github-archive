# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryOwnerDependenciesLoaderResultTest < GitHub::TestCase
  context "#dependency_ids" do
    test "returns the IDs of the dependencies" do
      owner1, owner2 = create_pair(:user)
      dependencies = create_pair(:repository, owner: owner1) + [create(:repository, owner: owner2)]
      result = Repository::OwnerDependenciesLoader::Result.new(dependencies: dependencies, already_sorted: true)
      assert_same_elements dependencies.map(&:id), result.dependency_ids
    end
  end
end
