# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCacheKeyTest < GitHub::TestCase
  fixtures do
    @public_repo = create(:public_repository)
    @public_fork = create(:public_repository, parent: @public_repo)

    user = create(:user, plan: "medium")
    @private_repo = create(:private_repository, owner: user)
    @private_fork = create(:private_repository, parent: @private_repo)
  end

  test "public repositories" do
    refute_equal @public_repo.repository_cache_key,
      @public_repo.network_cache_key

    refute_equal @public_fork.repository_cache_key,
      @public_fork.network_cache_key

    refute_equal @public_fork.repository_cache_key,
      @public_repo.repository_cache_key

    assert_equal @public_fork.network_cache_key,
      @public_repo.network_cache_key
  end

  test "private repositories" do
    assert_equal @private_repo.repository_cache_key,
      @private_repo.network_cache_key

    assert_equal @private_fork.repository_cache_key,
      @private_fork.network_cache_key

    refute_equal @private_fork.repository_cache_key,
      @private_repo.repository_cache_key

    refute_equal @private_repo.network_cache_key,
      @private_fork.network_cache_key
  end

  test "cache key id" do
    assert_equal 0, @public_repo.network.cache_version_number

    @public_repo.increment_cache_version!
    assert_equal 1, @public_repo.network.cache_version_number

    @public_repo.increment_cache_version!
    assert_equal 2, @public_repo.network.cache_version_number
  end

  test "incrementing cache id breaks repo cache" do
    old_key = @public_repo.repository_cache_key
    @public_repo.increment_cache_version!
    refute_equal @public_repo.repository_cache_key, old_key
  end

  test "incrementing cache id breaks whole network cache" do
    old_key = @public_repo.network_cache_key
    @public_repo.increment_cache_version!
    refute_equal @public_repo.network_cache_key, old_key
  end

  test "incrementing cache id breaks forks cache" do
    old_network_key = @public_fork.network_cache_key
    old_repo_key = @public_fork.repository_cache_key
    @public_repo.increment_cache_version!
    refute_equal @public_repo.network_cache_key, old_network_key
    refute_equal @public_repo.repository_cache_key, old_repo_key
  end
end
