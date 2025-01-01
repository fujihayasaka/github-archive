# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositorySlumlordDependencyTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  setup do
    make_bare_git_repo(@repo)
  end

  test "defaults" do
    refute_predicate @repo, :svn_debugging?
    refute_predicate @repo, :svn_blocked?
  end

  test "enable/disable debugging" do
    @repo.debug_svn
    assert_predicate @repo, :svn_debugging?

    @repo.undebug_svn
    refute_predicate @repo, :svn_debugging?

    @repo.svn_toggle_debugging
    assert_predicate @repo, :svn_debugging?

    @repo.svn_toggle_debugging
    refute_predicate @repo, :svn_debugging?
  end

  test "wacky debug value" do
    @repo.rpc.config_store "github.debug-svn-until", "boomtown"
    refute_predicate @repo, :svn_debugging?

    @repo.debug_svn
    assert_predicate @repo, :svn_debugging?
  end

  test "block/unblock" do
    @repo.block_svn
    assert_predicate @repo, :svn_blocked?

    @repo.unblock_svn
    refute_predicate @repo, :svn_blocked?

    @repo.svn_toggle_blocked
    assert_predicate @repo, :svn_blocked?

    @repo.svn_toggle_blocked
    refute_predicate @repo, :svn_blocked?
  end

  context "#svn_status" do
    test "fails gracefully when gitrpc fails" do
      GitRPC::Client.any_instance.stubs(:config_get).raises(GitRPC::InvalidRepository)

      assert_equal :offline, @repo.svn_status
    end
  end
end
