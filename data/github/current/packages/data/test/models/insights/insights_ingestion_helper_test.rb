# typed: true
# frozen_string_literal: true

class InsightsIngestionHelperTest < GitHub::TestCase
  include Insights::InsightsIngestionHelper

  context "#ingestion_allowed?" do
    test "returns true" do
      assert ingestion_allowed?(ONBOARDING_STATE)
      assert ingestion_allowed?(READY_STATE)
      assert ingestion_allowed?(ERROR_READY_STATE)
      assert ingestion_allowed?(OFF_STATE)
    end

    test "returns false" do
      refute ingestion_allowed?(ERROR_ONBOARDING_STATE)
      refute ingestion_allowed?(REQUESTED_STATE)
      refute ingestion_allowed?(ERROR_STATE)
      refute ingestion_allowed?(NOT_FOUND_STATE)
      refute ingestion_allowed?(DELETING_STATE)
      refute ingestion_allowed?(DELETED_STATE)
    end
  end
end
