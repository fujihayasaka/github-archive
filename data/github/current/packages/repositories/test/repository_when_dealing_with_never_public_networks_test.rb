# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryWhenDealingWithNeverPublicNetworksTest < GitHub::TestCase
  fixtures do
    @repo       = create(:repository)
    @other_repo = create(:repository)
    @user       = create(:user)
    @fork = create(:fork_repository, forker: @user, fork_repo: @repo)
  end

  setup do
    GitHub.reset_never_public_network_ids
  end

  test "Repository#public? returns false for members of a never-public repository network" do
    assert @repo.public?
    assert @fork.public?
    assert @other_repo.public?

    GitHub.stubs(:never_public_network_ids).returns([@repo.network_id])
    refute @repo.public?
    refute @fork.public?
    assert @other_repo.public?
  end

  test "GitHub.never_public_network_ids looks up network ids for present networks" do
    GitHub.stubs(:never_public_networks).returns([@repo.nwo, @fork.nwo, @other_repo.nwo])
    assert_equal [@repo.network_id, @other_repo.network_id].sort,
      GitHub.never_public_network_ids.sort
  end

  test "GitHub.never_public_network_ids skips network ids for non-present networks" do
    GitHub.stubs(:never_public_networks).returns(["non/existent", @repo.nwo])
    assert_equal [@repo.network_id], GitHub.never_public_network_ids
  end

  test "GitHub.never_public_networks cannot be modified" do
    assert_raises(FrozenError) do
      GitHub.never_public_networks.pop
    end
  end

  test "GitHub.never_public_network_ids cannot be modified" do
    assert_raises(FrozenError) do
      GitHub.never_public_network_ids.pop
    end
  end

  if GitHub.enterprise?
    test "GitHub.never_public_networks is empty on Enterprise" do
      assert_equal [], GitHub.never_public_networks
    end
  else
    test "GitHub.never_public_networks includes github/github and github/puppet in dotcom" do
      assert_equal ["github/github", "github/puppet"], GitHub.never_public_networks
    end
  end

  test "self.with_name_with_owner returns nil when nil is passed for name" do
    assert_nil Repository.with_name_with_owner(nil)
  end
end
