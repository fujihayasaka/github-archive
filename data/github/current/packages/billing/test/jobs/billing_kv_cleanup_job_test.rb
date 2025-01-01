# typed: strict
# frozen_string_literal: true

require "test_helper"

class BillingKvCleanupJobTest < GitHub::TestCase
  test "runs on the billing_platform_maintenance queue" do
    assert_enqueued_jobs 1, queue: :billing_maintenance do
      BillingKvCleanupJob.perform_later(duration: 60, batch_size: 100)
    end
  end
end
