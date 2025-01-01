# typed: true
# frozen_string_literal: true

require "test_helper"

class GitRpcRefsCacheWithDGitReposTest < GitHub::TestCase
  setup do
    @repo = create(:repository)
  end

  test "uses dgit backend and delegate" do
    assert_kind_of GitRPC::Protocol::DGit,
      @repo.rpc.backend
    assert_same @repo.rpc.backend,
      @repo.rpc.repository_reference_key_delegate
  end

  test "does not delete cached refs" do
    enable_cache_storage

    @repo.rpc.read_refs

    initial_keys = @repo.rpc.refs_keys.sort
    refute_empty GitHub.cache.get_multi(initial_keys), "at least one set of refs are cached"

    @repo.clear_ref_cache

    assert_equal initial_keys, @repo.rpc.refs_keys.sort, "refs keys"
    refute_empty GitHub.cache.get_multi(initial_keys), "no refs are cached now"
  end

  test "changes cache key when dgit checksum changes" do
    initial_keys = @repo.rpc.refs_keys.sort
    refute_empty initial_keys

    GitHub::DGit::Delegate::Repository.any_instance.stubs(repository_reference_key: "new")
    assert_equal initial_keys, @repo.rpc.refs_keys.sort, "repo refs keys should be cached"

    @repo.clear_ref_cache
    refute_equal initial_keys, @repo.rpc.refs_keys.sort, "repo refs keys should be reset when asked"
  end
end
