# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositorySlumlordTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :simple)
    @original_config = @repo.rpc.fs_read("config").freeze
  end

  setup do
    @repo.rpc.fs_delete("svn.history.msgpack")
    RefUpdater.delete_ref(@repo, "refs/__gh__/svn/v4")
    RefUpdater.delete_ref(@repo, "refs/__gh__/svn/v3")
    @repo.rpc.fs_write("config", @original_config)
  end

  test "has not been used" do
    refute @repo.svn_in_use?, "refute svn_in_use?"
  end
  test "has been used with the old mapping" do
    @repo.rpc.fs_write("svn.history.msgpack", "")
    assert @repo.svn_in_use?, "assert svn_in_use?"
  end
  test "has been used with the new mapping" do
    RefUpdater.update_ref(@repo, "refs/__gh__/svn/v4", @repo.refs.first.target_oid)
    assert @repo.svn_in_use?, "assert svn_in_use?"
  end
  test "has been used with the new old mapping" do
    RefUpdater.update_ref(@repo, "refs/__gh__/svn/v3", @repo.refs.first.target_oid)
    assert @repo.svn_in_use?, "assert svn_in_use?"
  end

  test "is not blocked" do
    refute @repo.svn_blocked?, "refute svn_blocked?"
  end
  test "is blocked" do
    @repo.svn_toggle_blocked
    assert @repo.svn_blocked?, "assert svn_blocked?"
  end
  test "is unblocked" do
    @repo.svn_toggle_blocked
    @repo.svn_toggle_blocked
    refute @repo.svn_blocked?, "refute svn_blocked?"
  end

  test "is not debugging" do
    refute @repo.svn_debugging?, "refute svn_debugging?"
  end
  test "is debugging" do
    @repo.svn_toggle_debugging
    assert @repo.svn_debugging?, "assert svn_debugging?"
  end
  test "was debugging and is not now" do
    @repo.svn_toggle_debugging
    @repo.svn_toggle_debugging
    refute @repo.svn_debugging?, "refute svn_debugging?"
  end

  test "instruments blocking svn access" do
    events = subscribe "staff.disable_svn"
    expected_payload = {
      visibility: @repo.visibility.to_sym,
      repo: @repo.name_with_owner,
      repo_id: @repo.id,
      public_repo: @repo.public?,
      user: @repo.owner.login,
      user_id: @repo.owner.id,
      fork_source: @repo.name_with_owner,
      fork_source_id: @repo.id,
    }

    @repo.svn_toggle_blocked

    assert event = events.pop, "a staff.disable_svn event was expected"
    assert_equal "staff.disable_svn", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments allowing svn access" do
    events = subscribe "staff.enable_svn"
    expected_payload = {
      visibility: @repo.visibility.to_sym,
      repo: @repo.name_with_owner,
      repo_id: @repo.id,
      public_repo: @repo.public?,
      user: @repo.owner.login,
      user_id: @repo.owner.id,
      fork_source: @repo.name_with_owner,
      fork_source_id: @repo.id,
    }

    @repo.svn_toggle_blocked
    @repo.svn_toggle_blocked

    assert event = events.pop, "a staff.enable_svn event was expected"
    assert_equal "staff.enable_svn", event.name
    assert_equal expected_payload, event.payload
  end
end
