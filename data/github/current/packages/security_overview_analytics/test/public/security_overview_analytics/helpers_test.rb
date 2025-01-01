# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class HelpersTest < GitHub::TestCase
    include Helpers

    context ".handle_updated_vulnerability" do
      test "queues a job with provided vulnerability_id" do
        assert_enqueued_with(job: SecurityOverviewAnalytics::HandleChangedAdvisoryJob, args: ->(args) {
          assert_equal 1000, args.first[:vulnerability_id]
          assert_nil args.first[:vulnerable_version_range_id]
          assert_equal SecurityOverviewAnalytics::HandleChangedAdvisoryJob::UPDATE_SOURCE_EVENT, args.first[:source_event]
        }) do
          Helpers.handle_updated_vulnerability(vulnerability_id: 1000)
        end
      end
    end
  end
end
