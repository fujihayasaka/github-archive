# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class FanoutThrottlerTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include HydroTestHelpers

    class TestJob < BatchedJob
      include FanoutThrottler

      @executed = false

      def self.executed?
        @executed
      end

      def self.set_executed=(value)
        @executed = value
      end

      def next_batch(*args, owner_id:, offset_item_id:, **kwargs)
        Repository.active.where(owner_id:).where("id > ?", offset_item_id).order(id: :asc).to_a
      end

      def process_batch(records, *args, owner_id:, offset_item_id:, **kwargs)
        self.class.set_executed = true
      end

      def fanout_jobs
        [RepositoryReconciliationJob, RepositorySyncJob]
      end
    end

    fixtures do
      @business = create(:business)
      @org = create(:organization, business: @business).tap do |o|
        3.times do
          create(:repository, owner: o)
        end
      end
    end

    setup do
      TestJob.set_executed = false
    end

    context "when on GHES", enterprise_only: true do
      context "when fanout job's queue depth is low" do
        test "job performs normally" do
          RepositoryReconciliationJob.stubs(:queue_depth).returns(0)
          RepositorySyncJob.stubs(:queue_depth).returns(0)
          Failbot.expects(:report).never

          assert_nothing_raised do
            TestJob.perform_now(owner_id: @org.id)
          end

          assert TestJob.executed?
        end
      end

      context "when fanout job's queue depth check raises exception" do
        test "job performs normally" do
          RepositoryReconciliationJob.stubs(:queue_depth).returns(0)
          RepositorySyncJob.stubs(:queue_depth).raises(StandardError)
          Failbot.expects(:report).once

          assert_nothing_raised do
            TestJob.perform_now(owner_id: @org.id)
          end

          assert TestJob.executed?
        end
      end

      context "when any fanout job's queue depth above limit" do
        test "job enqueues itself and does not perform" do
          RepositoryReconciliationJob.stubs(:queue_depth).returns(0)
          RepositorySyncJob.stubs(:queue_depth).returns(FanoutThrottler::MAX_ALLOWED_QUEUE_DEPTH + 1)
          Failbot.expects(:report).never

          assert_enqueued_with(job: TestJob, args: [{ owner_id: @org.id }]) do
            assert_nothing_raised do
              TestJob.perform_now(owner_id: @org.id)
            end
          end

          refute TestJob.executed?
        end
      end
    end

    context "when not on GHES", skip_enterprise: true do
      context "when fanout job's queue depth is low" do
        test "job performs normally" do
          RepositoryReconciliationJob.stubs(:queue_depth).returns(0)
          RepositorySyncJob.stubs(:queue_depth).returns(0)
          Failbot.expects(:report).never

          assert_nothing_raised do
            TestJob.perform_now(owner_id: @org.id)
          end

          assert TestJob.executed?
        end
      end

      context "when fanout job's queue depth check raises exception" do
        test "job performs normally" do
          RepositoryReconciliationJob.stubs(:queue_depth).returns(0)
          RepositorySyncJob.stubs(:queue_depth).raises(StandardError)
          Failbot.expects(:report).never

          assert_nothing_raised do
            TestJob.perform_now(owner_id: @org.id)
          end

          assert TestJob.executed?
        end
      end

      context "when any fanout job's queue depth above limit" do
        test "job performs normally" do
          RepositoryReconciliationJob.stubs(:queue_depth).returns(0)
          RepositorySyncJob.stubs(:queue_depth).returns(FanoutThrottler::MAX_ALLOWED_QUEUE_DEPTH + 1)
          Failbot.expects(:report).never

          assert_nothing_raised do
            TestJob.perform_now(owner_id: @org.id)
          end

          assert TestJob.executed?
        end
      end
    end
  end
end
