# typed: true
# frozen_string_literal: true

require "test_helper"

class ResyncMemexProjectItemsIndexJobStatusTest < GitHub::TestCase

  setup do
    @completed_job_ttl_lower_bound = ResyncMemexProjectItemsIndexJobStatus::COMPLETED_JOB_TTL - 5.minutes
  end

  context ".create" do
    test "creates a job status with a project-specific ID" do
      status = ResyncMemexProjectItemsIndexJobStatus.create(123)
      retrieved_status = ResyncMemexProjectItemsIndexJobStatus.find!(status.id)
      assert_match /resync-memex-project-items-index:123:[a-fA-F0-9]{16}/, retrieved_status.id
    end

    test "creates a job status with a custom TTL" do
      status = ResyncMemexProjectItemsIndexJobStatus.create(123)
      retrieved_status = ResyncMemexProjectItemsIndexJobStatus.find!(status.id)

      # Assert that we use the OVERALL_TTL from our `JobStatus` subclass rather than `JobStatus::DEFAULT_OVERALL_TTL`
      assert_equal ResyncMemexProjectItemsIndexJobStatus::OVERALL_TTL.to_i, retrieved_status.ttl.to_i
    end
  end

  context ".find_prefix" do
    test "can retrieve all job statuses for a given project" do
      3.times { ResyncMemexProjectItemsIndexJobStatus.create(123) }

      single_project_prefix = ResyncMemexProjectItemsIndexJobStatus.single_project_id_prefix(123)
      statuses = ResyncMemexProjectItemsIndexJobStatus.find_prefix(single_project_prefix)
      assert_equal 3, statuses.length

      ids = Set.new(statuses.map(&:id))
      assert_equal 3, ids.length
      assert ids.all? { |id| id.match?(/resync-memex-project-items-index:123:/) }
    end

    test "can retrieve job statuses for all projects" do
      2.times { ResyncMemexProjectItemsIndexJobStatus.create(123) }
      2.times { ResyncMemexProjectItemsIndexJobStatus.create(456) }

      global_prefix = ResyncMemexProjectItemsIndexJobStatus.global_project_id_prefix
      statuses = ResyncMemexProjectItemsIndexJobStatus.find_prefix(global_prefix)
      assert_equal 4, statuses.length

      ids = Set.new(statuses.map(&:id))
      assert_equal 4, ids.length
      assert_equal 2, ids.count { |id| id.match?(/resync-memex-project-items-index:123:/) }
      assert_equal 2, ids.count { |id| id.match?(/resync-memex-project-items-index:456:/) }
    end
  end

  context "#success!" do
    test "sets a custom ttl" do
      assert @completed_job_ttl_lower_bound > JobStatus::DEFAULT_COMPLETED_JOB_TTL

      Timecop.freeze do
        status = ResyncMemexProjectItemsIndexJobStatus.create(123)
        cache_key = status.send(:cache_key)

        status.success!

        assert status.success?
        assert status.finished?
        assert GitHub.kv.ttl(cache_key).value!.to_i > (Time.now + @completed_job_ttl_lower_bound).to_i
      end
    end
  end

  context "#error!" do
    test "sets a custom ttl" do
      assert @completed_job_ttl_lower_bound > JobStatus::DEFAULT_COMPLETED_JOB_TTL

      Timecop.freeze do
        status = ResyncMemexProjectItemsIndexJobStatus.create(123)
        cache_key = status.send(:cache_key)

        status.error!

        assert status.error?
        assert status.finished?
        assert GitHub.kv.ttl(cache_key).value!.to_i > (Time.now + @completed_job_ttl_lower_bound).to_i
      end
    end
  end
end
