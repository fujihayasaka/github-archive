# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRpcTest < GitHub::TestCase
  fixtures do
    @maddox = create(:user, login: "maddox")
    @repo = create(:repository, name: "repo",  owner: @maddox, from_example: :defunkt_facebox)
    @repo_bad = create(:repository, name: "repo_bad", owner: @maddox)
  end

  setup do
    enable_cache_storage
    reset_cache
  end

  teardown { disable_cache_storage }

  test "simple rpc call" do
    assert_equal "hello", @repo.rpc.echo("hello")
  end

  test "branch_contains sees commit in its branch" do
    branches = @repo.rpc.branch_contains("3bb5f6888bdb538a883843c34856e5cdeb0cd1d6")
    assert_equal ["chuyeow/master", "semis"], branches
  end

  test "tag_contains sees commit in its tag" do
    branches = @repo.rpc.tag_contains("fce84b4fccc622fa682b8550785cd596a0539c33")
    assert_equal ["v1.2"], branches
  end

  test "branch/tag_contains fail on invalid commit" do
    assert_raises(GitRPC::InvalidFullOid) { @repo.rpc.branch_contains("invalid-commit") }
    assert_raises(GitRPC::InvalidFullOid) { @repo.rpc.tag_contains("invalid-commit") }
  end

  test "repository objects collection access" do
    oid = @repo.ref_to_sha("master")
    assert @repo.objects.exist?(oid)
  end

  test "ahead-behind information is available and cached" do
    expect = {
      "chuyeow/master" => [3, 9],
      "subwindow/master" => [0, 3],
      "semis" => [1, 12],
      "webweaver/master" => [0, 0],
    }

    # ahead-behind counts should always be available,
    # even if bitmaps have not been generated
    ab = @repo.rpc.ahead_behind("master", expect.keys)
    assert_equal expect, ab
  end

  test "establishes cache keys" do
    refute_nil @repo.rpc.content_key
    refute_nil @repo.rpc.repository_key
  end

  test "describe returns a correct description" do
    branches = @repo.rpc.describe("fce84b4fccc622fa682b8550785cd596a0539c33", 7)
    assert_equal "v1.2-0-gfce84b4", branches
  end

  test "describing an invalid commit fails" do
    assert_raises(GitRPC::ObjectMissing) { @repo.rpc.describe("not-a-real-commit", 7) }
  end

  test "describe can deal with a dashed tag" do
    branches = @repo.rpc.describe("-v2.0", 7)
    assert_equal "-v2.0-0-g75822fc", branches
  end

  test "route a network with no host" do
    no_network_repo = create :repository, :full_creation, owner: @maddox
    no_network_repo.network = nil

    assert_raises(Repository::RpcDependency::UnroutedError) do
      p no_network_repo.rpc
    end

    refute no_network_repo.online?
  end

  test "sets repo and user information in the rpc backend" do
    GitHub.context.push(actor_id: @maddox.id, actor_ip: "127.0.0.1", request_id: "abcd")
    repo = create(:repository, name: "info-test", owner: @maddox)
    expected = {
      user_id: @maddox.id,
      real_ip: "127.0.0.1",
      repo_id: repo.id,
      repo_name: repo.nwo,
      request_id: "abcd"
    }
    assert_equal expected, repo.rpc.backend.options[:info]
  end
end
