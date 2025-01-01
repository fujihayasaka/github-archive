# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class QueueMemexElasticsearchResyncsJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers

  setup do
    @projects = create_list(:memex_project, 10, last_visited_on: Time.new(2024, 8, 14, 0, 10, 0).utc)
  end

  context "#perform" do
    test "retries job on dirty exit" do
      assert_retry_on_dirty_exit(job: QueueMemexElasticsearchResyncsJob)
    end

    test "enqueus resync jobs with unevaluated consistency records" do
      0.0.step(0.9, 0.1).each_with_index { |consistency, index| setup_consistency(@projects[index] => { consistency: }) }
      assert_equal_enqueued_resync_jobs @projects.size
    end

    test "enqueus resync jobs with evaluated consistency records" do
      0.0.step(0.9, 0.1).each_with_index do |consistency, index|
        setup_consistency(@projects[index] => { consistency:, evaluated_at: Time.now.utc })
      end

      assert_equal_enqueued_resync_jobs @projects.size
    end

    test "tags resync jobs with sample size appropiately" do
      0.0.step(0.9, 0.1).each_with_index { |consistency, index| setup_consistency(@projects[index] => { consistency: }) }

      assert_equal_enqueued_resync_jobs @projects.size
      assert_dogstats_gauge_value(@projects.size, QueueMemexElasticsearchResyncsJob::SAMPLE_SIZE_METRIC_NAME)
    end
  end

  sig { params(expectations: T::Hash[MemexProject, { consistency: Float, evaluated_at: T.nilable(Time) }]).void }
  private def setup_consistency(expectations)
    expectations.each do |project, args|
      MemexProjectElasticsearchConsistency.create_or_update(T.must(project.id), **args)
    end
  end

  sig { params(size: Integer).void }
  private def assert_equal_enqueued_resync_jobs(size)
    MemexProjectElasticsearchConsistency.stub_const(:SAMPLE_PERCENTAGE, 1) do
      QueueMemexElasticsearchResyncsJob.stub_const(:BATCH_SIZE, 2) do
        assert_enqueued_jobs(size, only: ResyncMemexProjectItemsIndexJob) do
          QueueMemexElasticsearchResyncsJob.perform_now
        end
      end
    end
  end
end
