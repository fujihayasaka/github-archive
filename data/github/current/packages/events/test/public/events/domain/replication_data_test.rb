# typed: true
# frozen_string_literal: true

require "test_helper"

class ReplicationsCompletedTest < GitHub::TestCase
  include DogstatsTestHelpers
  setup do
    @domain = Events::Domain.new
    @now = Time.now.beginning_of_day
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    Timecop.freeze(@now) do
      @tracked_writes = [
        { gtid: "000-000", cluster_name: "mysql1", time: { "seconds": 1.second.ago.to_i } },
        { gtid: "000-000", cluster_name: "repositories", time: { "seconds": 1.second.ago.to_i } },
      ]
    end
    Failbot.reports.clear
  end


  context "when track writes is nil" do
    test "it returns replications_completed is true and exceeded_maximum_timeout is false" do
      Timecop.freeze(@now) do
        ApplicationRecord::Mysql1.stubs(:default_replication_wait).returns(1000) # rubocop:disable GitHub/DoNotCallMethodsOnApplicationRecordMysql1
        ApplicationRecord::Repositories.stubs(:default_replication_wait).returns(1000)
        result = @domain.replication_data(nil, :EVENT_TYPE_ISSUES)
        assert_predicate result, :replications_completed?
        refute_predicate result, :exceeded_maximum_timeout?
        assert_dogstats_increment(1, "events.domain.nil_tracked_writes", tags: ["event_type:issues"])
      end
    end
  end

  context "when replications are completed" do
    test "it returns replications_completed is true and exceeded_maximum_timeout is false" do
      Timecop.freeze(@now) do
        ApplicationRecord::Mysql1.stubs(:default_replication_wait).returns(500) # rubocop:disable GitHub/DoNotCallMethodsOnApplicationRecordMysql1
        ApplicationRecord::Repositories.stubs(:default_replication_wait).returns(510)
        result = @domain.replication_data(@tracked_writes, :EVENT_TYPE_ISSUES)
        assert_predicate result, :replications_completed?
        assert_dogstats_increment(1, "events.domain.replication_data.replications_completed", tags: ["event_type:issues", "replications_completed:true"])
        refute_predicate result, :exceeded_maximum_timeout?
        assert_dogstats_distribution_value(500, "events.domain.replication_data.replication_lag", tags: ["event_type:issues", "cluster_name:mysql1"])
      end
    end
  end

  context "when replications are not completed" do
    test "it returns replications_completed is false and exceeded_maximum_timeout is false when one of the cluster did not finish replications" do
      Timecop.freeze(@now) do
        ApplicationRecord::Mysql1.stubs(:default_replication_wait).returns(3000) # rubocop:disable GitHub/DoNotCallMethodsOnApplicationRecordMysql1
        ApplicationRecord::Repositories.stubs(:default_replication_wait).returns(500)
        result = @domain.replication_data(@tracked_writes, :EVENT_TYPE_ISSUES)
        refute_predicate result, :replications_completed?
        assert_dogstats_increment(1, "events.domain.replication_data.replications_completed", tags: ["event_type:issues", "replications_completed:false"])
        refute_predicate result, :exceeded_maximum_timeout?
      end
    end

    test "it returns replications_completed is false and exceeded_maximum_timeout is false when none of the cluster finished replication" do
      Timecop.freeze(@now) do
        ApplicationRecord::Mysql1.stubs(:default_replication_wait).returns(3000) # rubocop:disable GitHub/DoNotCallMethodsOnApplicationRecordMysql1
        ApplicationRecord::Repositories.stubs(:default_replication_wait).returns(3000)
        result = @domain.replication_data(@tracked_writes, :EVENT_TYPE_ISSUES)
        refute_predicate result, :replications_completed?
        assert_dogstats_increment(1, "events.domain.replication_data.replications_completed", tags: ["event_type:issues", "replications_completed:false"])
        refute_predicate result, :exceeded_maximum_timeout?
      end
    end

    test "it returns replications_completed is false and exceeded_maximum_timeout is true when replication lag is over 5s" do
      Timecop.freeze(@now) do
        ApplicationRecord::Mysql1.stubs(:default_replication_wait).returns(7000) # rubocop:disable GitHub/DoNotCallMethodsOnApplicationRecordMysql1
        ApplicationRecord::Repositories.stubs(:default_replication_wait).returns(1000)
        result = @domain.replication_data(@tracked_writes, :EVENT_TYPE_ISSUES)
        refute_predicate result, :replications_completed?
        assert_dogstats_increment(1, "events.domain.replication_data.replications_completed", tags: ["event_type:issues", "replications_completed:false"])
        assert_predicate result, :exceeded_maximum_timeout?
        assert_dogstats_increment(1, "events.domain.replication_data.exceeded_maximum_timeout", tags: ["event_type:issues"])
      end
    end
  end

  context "when we get an error" do
    test "it returns replications_completed is false, exceeded_maximum_timeout is false and  metrics are incremented when error is unexpected" do
      Timecop.freeze(@now) do
        ApplicationRecord::Mysql1.stubs(:default_replication_wait).raises(StandardError, "oops") # rubocop:disable GitHub/DoNotCallMethodsOnApplicationRecordMysql1
        result = @domain.replication_data(@tracked_writes, :EVENT_TYPE_ISSUES)
        refute_predicate result, :replications_completed?
        refute_predicate result, :exceeded_maximum_timeout?
        assert_dogstats_increment(1, "events.domain.replication_data.error", tags: ["call:replication_data"])
        report = Failbot.reports.last
        refute_nil report
        assert_equal("github-webhook", report["app"])
      end
    end
  end
end
