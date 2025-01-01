# typed: true
# frozen_string_literal: true

require "test_helper"

class ClusterWaitDependencyDependencyTest < GitHub::TestCase
  extend T::Helpers

  setup do
    @last_writes = {
      mysql1: { gtid: "000-000", time: Time.now.to_i * 1000 },
      repositories: { gtid: "000-000", time: Time.now.to_i * 1000 }
    }
  end

  class WaitSomeTestEvent < Hook::Event
    wait_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::RepositoriesActionsChecks
  end

  class WaitEmptyTestEvent < Hook::Event
  end

  context "#wait_cluster_names" do
    test "stores cluster names when set" do
      assert_equal [:mysql1, :"repositories-actions-checks"], WaitSomeTestEvent.wait_cluster_names
    end

    test "empty when unset" do
      assert_empty WaitEmptyTestEvent.wait_cluster_names
    end
  end

  context "#filter_wait_clusters?" do
    test "returns true when cluster names are set" do
      assert WaitSomeTestEvent.filter_wait_clusters?
    end

    test "returns false when cluster names are not set" do
      refute WaitEmptyTestEvent.filter_wait_clusters?
    end
  end

  context "#filter_last_writes" do
    test "filters when cluster names are set" do
      filtered_last_writes = WaitSomeTestEvent.filter_last_writes(@last_writes)
      assert_nil filtered_last_writes[:repositories]
      refute_nil filtered_last_writes[:mysql1]
    end

    test "does not filter when cluster names are not set" do
      assert_equal @last_writes, WaitEmptyTestEvent.filter_last_writes(@last_writes)
    end
  end
end
