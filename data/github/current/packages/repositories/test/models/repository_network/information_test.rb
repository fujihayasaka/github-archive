# typed: true
# frozen_string_literal: true

require "test_helper"

class InformationTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, name: "owner", plan: "medium")
    @repo  = create(:repository, name: "network_information_test", owner: @owner)
    @repo2 = create(:repository, name: "network_information_test_2", owner: @owner)
    @network1 = @repo.reload_network
    @network2 = @repo2.reload_network
  end

  test "returns the most pushed repository networks in order, defaulting to 1" do
    @network1.update_attribute :pushed_count, 1000
    @network2.update_attribute :pushed_count, 500
    assert_equal @network1, RepositoryNetwork::Information.most_pushed[0]

    @network2.update_attribute :pushed_count, 2000
    assert_equal @network2, RepositoryNetwork::Information.most_pushed[0]
  end

  test "returns the largest repository networks in order, defaulting to 1" do
    @network1.update_attribute :disk_usage, 50000
    @network2.update_attribute :disk_usage, 10000
    assert_equal @network1, RepositoryNetwork::Information.largest[0]

    @network2.update_attribute :disk_usage, 90000
    assert_equal @network2, RepositoryNetwork::Information.largest[0]
  end

  test "information queries can have limits set" do
    @network1.update_attribute :disk_usage, 50000
    @network2.update_attribute :disk_usage, 10000
    assert_equal @network1, RepositoryNetwork::Information.largest(3)[0]
    assert_equal @network2, RepositoryNetwork::Information.largest(3)[1]
    assert_nil RepositoryNetwork::Information.largest(3)[2]
  end

  test "doesn't attempt a query when MAX_LIMIT is exceeded" do
    assert_raises RepositoryNetwork::Information::ExcessiveQuery do
      RepositoryNetwork::Information.largest(50000)
    end
  end
end
