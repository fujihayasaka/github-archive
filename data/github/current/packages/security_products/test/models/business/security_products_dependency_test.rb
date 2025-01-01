# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProductsDependencyTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
  end

  context "#security_configurations_applying_or_blocked?" do
    test "returns true if SecurityProductsEnablement::JobProgressTracker is in progress for the enterprise" do
      job_progress_tracker = SecurityProductsEnablement::JobProgressTracker.new(@business.id)

      # Start job progress and ensure we return true:
      job_progress_tracker.start
      assert_predicate @business, :security_configurations_applying_or_blocked?

      # Finish job progress and ensure we return false:
      job_progress_tracker.finish
      refute_predicate @business, :security_configurations_applying_or_blocked?
    end

    test "returns false by default" do
      refute_predicate @business, :security_configurations_applying_or_blocked?
    end
  end
end
