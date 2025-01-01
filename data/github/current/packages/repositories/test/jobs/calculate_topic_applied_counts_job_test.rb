# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CalculateTopicAppliedCountsJobTest < GitHub::TestCase
  include JobTestHelper

  test "sets the applied_count value for all Topics" do
    topic1 = create(:topic)
    topic2 = create(:topic)
    topic3 = create(:topic)

    create(:repository_topic, topic: topic1, state: :created)
    to_update = create(:repository_topic, topic: topic2, state: :created)
    to_remove = create(:repository_topic, topic: topic2, state: :created)

    CalculateTopicAppliedCountsJob.perform_now

    assert_equal 1, topic1.reload.applied_count
    assert_equal 2, topic2.reload.applied_count
    assert_equal 0, topic3.reload.applied_count

    to_update.update!(state: :declined_not_relevant)
    to_remove.destroy!
    create(:repository_topic, topic: topic3, state: :created)

    CalculateTopicAppliedCountsJob.perform_now

    assert_equal 1, topic1.reload.applied_count
    assert_equal 0, topic2.reload.applied_count
    assert_equal 1, topic3.reload.applied_count
  end

  test "re-enqueues CalculateTopicAppliedCountsJob when duration is exceeded" do
    topics = []

    5.times do
      topic = create(:topic)
      create(:repository_topic, topic: topic, state: :created)
      topics << topic
    end

    topics.each { |t| assert_equal 0, t.reload.applied_count }
    assert_performed_jobs 4, only: CalculateTopicAppliedCountsJob do
      CalculateTopicAppliedCountsJob.perform_later(batch_size: 2, duration: 0)
    end
    topics.each { |t| assert_equal 1, t.reload.applied_count }
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: CalculateTopicAppliedCountsJob, args: []
  end
end
