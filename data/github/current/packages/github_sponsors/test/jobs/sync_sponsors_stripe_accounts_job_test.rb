# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SyncSponsorsStripeAccountsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @account_without_email = create(:stripe_connect_account, email: nil, verification_status: :unverified)
    @account_with_email = create(:stripe_connect_account, email: "somebody@example.com")
    @inactive_account = create(:stripe_connect_account, :inactive, email: nil, verification_status: :unknown)
  end

  test "retries on a dirty exit" do
    assert_retry_on_dirty_exit job: SyncSponsorsStripeAccountsJob
  end

  test "checks Stripe only for accounts that are missing an email" do
    SyncSponsorsStripeAccountJob.expects(:perform_later).with(@account_without_email).once
    SyncSponsorsStripeAccountJob.expects(:perform_later).with(@account_with_email).never
    SyncSponsorsStripeAccountJob.expects(:perform_later).with(@inactive_account).once

    SyncSponsorsStripeAccountsJob.perform_now
  end
end
