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
    enable_feature_flag(:gitrpc_max_cruft_size_3g, @root)
    disable_feature_flag(:gitrpc_max_cruft_size_3g, @fork)
    assert_equal 3.gigabytes, @root.max_cruft_size

    ::GitRPC::Client.any_instance.expects(:nw_gc)
      .with(has_entry(max_cruft_size: 3.gigabytes))
    @root.network.repack
  end

  test "gitrpc_max_cruft_size feature flag enabled (repo)" do
    disable_feature_flag(:gitrpc_max_cruft_size_3g, @repo)
    enable_feature_flag(:gitrpc_max_cruft_size_2g, @repo)
    assert_equal 2.gigabytes, @repo.max_cruft_size

    ::GitRPC::Client.any_instance.expects(:nw_repack)
      .with(has_entry(max_cruft_size: 2.gigabytes))
    @repo.repack
  end

  test "gitrpc_max_cruft_size feature flag disabled (network)" do
    disable_feature_flag(:gitrpc_max_cruft_size_2g, @root)
    disable_feature_flag(:gitrpc_max_cruft_size_3g, @root)
    disable_feature_flag(:gitrpc_max_cruft_size_1g, @root)
    enable_feature_flag(:gitrpc_max_cruft_size_1g, @fork)
    assert_nil @root.max_cruft_size

    ::GitRPC::Client.any_instance.expects(:nw_gc)
      .with(has_entry(max_cruft_size: nil))
    @root.network.repack
  end

  test "gitrpc_max_cruft_size feature flag disabled (repo)" do
    disable_feature_flag(:gitrpc_max_cruft_size_3g, @repo)
    disable_feature_flag(:gitrpc_max_cruft_size_2g, @repo)
    disable_feature_flag(:gitrpc_max_cruft_size_1g, @repo)
    assert_nil @root.max_cruft_size

    ::GitRPC::Client.any_instance.expects(:nw_repack)
      .with(has_entry(max_cruft_size: nil))
    @repo.repack
  end
end
