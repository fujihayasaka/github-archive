# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::SubscriptionSyncStatusTest < GitHub::TestCase

  test "#succeed! marks status as success" do
    sync_status = create :billing_subscription_sync_status
    assert_equal sync_status.external_sync_status, "pending" # make sure it started out pending
    sync_status.succeed!

    assert_equal sync_status.external_sync_status, "success"
  end

  test "#fail! marks status as failure" do
    sync_status = create :billing_subscription_sync_status
    assert_equal sync_status.external_sync_status, "pending" # make sure it started out pending
    sync_status.fail!

    assert_equal sync_status.external_sync_status, "failure"
  end

  test "external_sync_status won't accept non-valid values" do
    sync_status = create :billing_subscription_sync_status

    assert_raises ArgumentError do
      sync_status.update(external_sync_status: "lost_in_space")
    end
  end

  context "#on_last_retry?" do
    test "returns false if status is failure" do
      sync_status = create :billing_subscription_sync_status, external_sync_status: "failure"
      refute sync_status.on_last_retry?
    end

    test "returns false if status is success" do
      sync_status = create :billing_subscription_sync_status, external_sync_status: "success"
      refute sync_status.on_last_retry?
    end

    test "returns false if status is failed_but_retrying and number_of_retries_remaining is 2" do
      sync_status = create :billing_subscription_sync_status, external_sync_status: "failed_but_retrying", number_of_retries_remaining: 2
      refute sync_status.on_last_retry?
    end

    test "returns true if status is failed_but_retrying and number_of_retries_remaining is 1" do
      sync_status = create :billing_subscription_sync_status, external_sync_status: "failed_but_retrying", number_of_retries_remaining: 1
      assert sync_status.on_last_retry?
    end
  end

  context "#stale?" do
    test "returns false if status is failed_but_retrying regardless of age" do
      sync_status = create :billing_subscription_sync_status, external_sync_status: "failed_but_retrying", updated_at: 30.minutes.ago
      refute sync_status.stale?
    end

    test "returns false if status is success but updated withing 10 mins" do
      sync_status = create :billing_subscription_sync_status, external_sync_status: "success", updated_at: 1.minute.ago
      refute sync_status.stale?
    end

    test "returns true if status is success but updated more than 10 mins ago" do
      sync_status = create :billing_subscription_sync_status, external_sync_status: "success", updated_at: 11.minutes.ago
      assert sync_status.stale?
    end
  end
end
