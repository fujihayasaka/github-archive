# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class FeatureStatusDataCompressionJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper
    include ::SecurityCenter::TestHelpers

    fixtures do
      @org = create(:business_plus_organization)
      @org2 = create(:business_plus_organization)
    end

    setup do
      disable_feature_flag(:soa_data_compression_job_restraint_lock_num_concurrent_jobs)
      disable_feature_flag(:soa_data_compression_job_restraint_lock_ttl_minutes)

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
        FeatureStatusRevision.expects(:compress_revisions).once

        assert_logged_statements([
          { Body: "Block start", "gh.security_center.step": "perform" },
          { Body: "Block end", "gh.security_center.step": "perform", "gh.security_center.elapsed_ms": /\d+/ },
          { "gh.security_overview_analytics.data_compression.dry_run": true },
        ]) do
          assert_performed_jobs 1, only: FeatureStatusDataCompressionJob do
            perform_enqueued_jobs only: FeatureStatusDataCompressionJob do
              FeatureStatusDataCompressionJob.perform_later(repository_id: @repo.id, owner_id: @org.id, dry_run: true)
            end
          end
        end
      end
    end

    context "hash lock" do
      test "allows one job per repo-feature combination to be enqueued" do
        assert_enqueued_jobs 1, only: FeatureStatusDataCompressionJob do
          FeatureStatusDataCompressionJob.perform_later(repository_id: @repo.id, owner_id: @org.id)
          FeatureStatusDataCompressionJob.perform_later(repository_id: @repo.id, owner_id: @org.id)
        end
      end
    end
  end
end
