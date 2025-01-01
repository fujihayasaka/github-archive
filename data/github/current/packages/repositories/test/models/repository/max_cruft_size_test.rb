# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryMaxCruftSizeTest < GitHub::TestCase
  setup do
    @root = create(:repository, :full_creation)
    @fork = create(:fork_repository, fork_repo: @root, forker: create(:user))

    @repo = create(:repository, :full_creation)
  end

  test "gitrpc_max_cruft_size feature flag enabled (network)" do
    GitHub.flipper[:gitrpc_max_cruft_size].enable(@root)
    GitHub.flipper[:gitrpc_max_cruft_size].disable(@fork)
    assert_equal 3.gigabytes, @root.max_cruft_size

    ::GitRPC::Client.any_instance.expects(:nw_gc)
      .with(has_entry(max_cruft_size: 3.gigabytes))
    @root.network.repack
  end

  test "gitrpc_max_cruft_size feature flag enabled (repo)" do
    GitHub.flipper[:gitrpc_max_cruft_size].enable(@repo)
    assert_equal 3.gigabytes, @repo.max_cruft_size

    ::GitRPC::Client.any_instance.expects(:nw_repack)
      .with(has_entry(max_cruft_size: 3.gigabytes))
    @repo.repack
  end

  test "gitrpc_max_cruft_size feature flag disabled (network)" do
    GitHub.flipper[:gitrpc_max_cruft_size].disable(@root)
    GitHub.flipper[:gitrpc_max_cruft_size].enable(@fork)
    assert_nil @root.max_cruft_size

    ::GitRPC::Client.any_instance.expects(:nw_gc)
      .with(has_entry(max_cruft_size: nil))
    @root.network.repack
  end

  test "gitrpc_max_cruft_size feature flag disabled (repo)" do
    GitHub.flipper[:gitrpc_max_cruft_size].disable(@repo)
    assert_nil @root.max_cruft_size

    ::GitRPC::Client.any_instance.expects(:nw_repack)
      .with(has_entry(max_cruft_size: nil))
    @repo.repack
  end
end
