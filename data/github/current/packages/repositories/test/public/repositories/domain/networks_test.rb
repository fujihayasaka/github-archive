# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Domain::NetworksTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @other_user = create(:user)
    @network = @repo.network
    @fork = create(:fork_repository, forker: @other_user, fork_repo: @repo)
  end

  context "#by_id" do
    test "finds the requested network by its ID" do
      network = T.must(Repositories.domain.networks.by_id(@repo.source_id))
      assert_equal network.id, @network.id
    end
  end

  context "#by_ids" do
    test "finds the requested networks by their IDs" do
      network = T.must(Repositories.domain.networks.by_ids([@repo.source_id]).first)
      assert_equal network.id, @network.id
    end
  end

  context "#owners_by_ids" do
    test "finds the requested owners of the network by their IDs" do
      owners_by_networks = Repositories.domain.networks.owners_by_ids([@repo.source_id])
      assert_equal owners_by_networks[@network.id], @user
    end

    test "for fork" do
      owners_by_networks = Repositories.domain.networks.owners_by_ids([@fork.source_id])
      assert_equal owners_by_networks[@network.id], @user
    end
  end
end
