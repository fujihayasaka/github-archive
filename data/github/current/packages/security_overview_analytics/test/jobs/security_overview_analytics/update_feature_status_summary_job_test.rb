# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class UpdateFeatureStatusSummaryJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper
    include SecurityOverviewAnalytics::TestFixtures

    fixtures do
      @owner = create(:user)
      @org = create(:organization, admin: @owner)
      @repo = create(:repository, owner: @org)
    end

    context "#perform" do
      context "when record already exists" do
        test "updates the existing FeatureStatus record" do
          create(:soa_feature_status, repository: @repo, updated_at: 2.days.ago)

          # give it some reason to update the summary
          create(:soa_feature_status_revision, repository: @repo, advanced_security_enabled: true)

          now = Time.current.utc
          Timecop.freeze(now) do
            UpdateFeatureStatusSummaryJob.perform_now(repository_id: @repo.id)
          end

          record = FeatureStatus.find_by(repository_id: @repo.id)
          refute_nil record
          record = T.cast(record, FeatureStatus)
          assert_equal now.to_i, record.updated_at&.utc&.to_i
        end
      end

      context "when record does not exist" do
        test "creates a new FeatureStatus record" do
          assert_nil FeatureStatus.find_by(repository_id: @repo.id)

          now = Time.current.utc
          Timecop.freeze(now) do
            UpdateFeatureStatusSummaryJob.perform_now(repository_id: @repo.id)
          end

          record = FeatureStatus.find_by(repository_id: @repo.id)
          refute_nil record
          record = T.cast(record, FeatureStatus)
          assert_equal now.to_i, record.created_at&.utc&.to_i
          assert_equal now.to_i, record.updated_at&.utc&.to_i
        end
      end
    end

    context ".enqueue" do
      test "only enqueues once within interval" do
        assert_enqueued_jobs 1, only: UpdateFeatureStatusSummaryJob do
          Timecop.freeze do
            UpdateFeatureStatusSummaryJob.enqueue(repository_id: @repo.id)
            UpdateFeatureStatusSummaryJob.enqueue(repository_id: @repo.id)
          end
        end
      end

      test "enqueues again within interval for different repository" do
        assert_enqueued_jobs 2, only: UpdateFeatureStatusSummaryJob do
          Timecop.freeze do
            UpdateFeatureStatusSummaryJob.enqueue(repository_id: 1)
            UpdateFeatureStatusSummaryJob.enqueue(repository_id: 2)
          end
        end
      end
    end

    context "resiliency" do
      test "retries on common exceptions" do
        assert_retry_conditions(job: UpdateFeatureStatusSummaryJob, args: [{ repository_id: @repo.id }])
      end
    end
  end
end
