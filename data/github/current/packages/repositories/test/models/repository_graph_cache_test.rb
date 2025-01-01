# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryGraphCacheTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  setup do
    enable_cache_storage
    reset_cache
  end

  test "can return an instance of the repo's graph cache" do
    assert_equal @repo.graph_cache.class, GitHub::RepoGraph::Cache
  end

  test "returns a boolean regarding the whether the graph cache is enabled" do
    assert !@repo.graph_cache.disabled?
  end

  test "can toggle the graph cache status" do
    assert !@repo.graph_cache.disabled?

    @repo.toggle_allow_git_graph
    assert @repo.graph_cache.disabled?
  end
end
