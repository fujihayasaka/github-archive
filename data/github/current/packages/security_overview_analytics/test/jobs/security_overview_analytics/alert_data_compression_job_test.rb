# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class AlertDataCompressionJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper

    fixtures do
      @org = create(:business_plus_organization)
      @org2 = create(:business_plus_organization)
    end

    setup do
      GitHub.flipper[:soa_data_compression_job_restraint_lock_num_concurrent_jobs].disable
      GitHub.flipper[:soa_data_compression_job_restraint_lock_ttl_minutes].disable

      @date = create(:soa_date, date_value: ::Date.current - 15)
      @dates = [
        create(:security_overview_analytics_date, date_value: Time.parse("2023-09-17")),
        create(:security_overview_analytics_date, date_value: Time.parse("2023-09-14")), # simulate gap
        create(:security_overview_analytics_date, date_value: Time.parse("2023-09-13")),
        create(:security_overview_analytics_date, date_value: Time.parse("2023-09-12")),
      ]
      @repo = create(:repository, owner: @org)
      @metadata = create(:soa_repository, repository: @repo)

      @dates.reduce(Date::FUTURE_DATE_ID) do |next_date_id, date|
        create(
          :security_overview_analytics_dependabot_alert_revision,
          alert_number: 1,
          alert_created_at: @dates.last.date_value,
          alert_updated_at: @dates.last.date_value,
          date: date,
          next_revision_date_id: next_date_id,
          repository_metadata: @metadata,
        )
        create(
          :security_overview_analytics_code_scanning_alert_revision,
          alert_number: 1,
          alert_created_at: @dates.last.date_value,
          alert_updated_at: @dates.last.date_value,
          date: date,
          next_revision_date_id: next_date_id,
          repository_metadata: @metadata,
        )
        create(
          :security_overview_analytics_secret_scanning_alert_revision,
          alert_type: "3adde576-d108-4845-85eb-bc5526da1a5d",
          alert_type_provider: "42095bb8-fe4a-4efe-8c8e-d74f74777c9f",
          alert_type_slug: "533bb433-a634-4123-8508-b3150f0fcc26",
          alert_number: 1,
          alert_created_at: @dates.last.date_value,
          alert_updated_at: @dates.last.date_value,
          date: date,
          next_revision_date_id: next_date_id,
          repository_metadata: @metadata,
        )
        create(
          :security_overview_analytics_feature_status_revision,
          date: date,
          next_revision_date_id: next_date_id,
          repository_metadata: @metadata,
        )
        next date.id
      end
    end

    context "#perform" do
      test "calls compress_revisions for the provided feature" do
        DependabotAlertRevision.expects(:compress_revisions).once

        assert_performed_jobs 1, only: AlertDataCompressionJob do
          AlertDataCompressionJob.perform_later(feature: "dependabot", repository_id: @repo.id, owner_id: @org.id)
        end
      end
    end

    context "batched job" do
      test "queues subsequent jobs for batching" do
        repo = create(:repository, owner: @org).tap do |r|
          metadata = create(:soa_repository, repository: r)

          @dates.each_with_index do |date, i|
            create(
              :security_overview_analytics_code_scanning_alert_revision,
              alert_number: 101 + i,
              alert_created_at: date.date_value,
              alert_updated_at: date.date_value,
              date: date,
              next_revision_date_id: Date::FUTURE_DATE_ID,
              repository_metadata: metadata,
            )
          end
        end

        AlertDataCompressionJob.stub_const(:BATCH_SIZE, 3) do
          assert_performed_jobs 2, only: AlertDataCompressionJob do
            perform_enqueued_jobs only: AlertDataCompressionJob do
              AlertDataCompressionJob.perform_later(feature: "code_scanning", repository_id: repo.id, owner_id: @org.id)
            end
          end
        end

        assert_dogstats_distribution 1, "batched_job.total_time.dist"
      end

      test "takes duplicate numbers into account when determining if there is a next batch" do
        # Create one more revision with a different alert number, so we have 5 revisions in total
        create(
          :security_overview_analytics_secret_scanning_alert_revision,
          alert_type: "3adde576-d108-4845-85eb-bc5526da1a5d",
          alert_type_provider: "42095bb8-fe4a-4efe-8c8e-d74f74777c9f",
          alert_type_slug: "533bb433-a634-4123-8508-b3150f0fcc26",
          alert_number: 2,
          alert_created_at: @dates.first.date_value,
          alert_updated_at: @dates.first.date_value,
          date: @dates.first,
          next_revision_date_id: Date::FUTURE_DATE_ID,
          repository_metadata: @metadata,
        )

        # First batch will process 3 revisions with alert number 1
        # The second batch will the remaining revision with alert number 1, and the only revision with alert number 2
        AlertDataCompressionJob.stub_const(:BATCH_SIZE, 3) do
          assert_performed_jobs 2, only: AlertDataCompressionJob do
            perform_enqueued_jobs only: AlertDataCompressionJob do
              AlertDataCompressionJob.perform_later(feature: "secret_scanning", repository_id: @repo.id, owner_id: @org.id)
            end
          end
        end

        assert_dogstats_distribution 1, "batched_job.total_time.dist"
      end
    end

    context "hash lock" do
      test "allows one job per repo-feature combination to be enqueued" do
        assert_enqueued_jobs 2, only: AlertDataCompressionJob do
          AlertDataCompressionJob.perform_later(feature: "code_scanning", repository_id: @repo.id, owner_id: @org.id)
          AlertDataCompressionJob.perform_later(feature: "code_scanning", repository_id: @repo.id, owner_id: @org.id)
          AlertDataCompressionJob.perform_later(feature: "secret_scanning", repository_id: @repo.id, owner_id: @org.id)
        end
      end
    end
  end
end
