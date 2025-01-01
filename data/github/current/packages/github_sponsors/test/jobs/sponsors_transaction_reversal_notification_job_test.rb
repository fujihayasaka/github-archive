# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SponsorsTransactionReversalNotificationJobTest < GitHub::TestCase
  include ActionMailer::TestHelper

  fixtures do
    @sponsor = create(:user)
    @sponsorable = create(:user, :sponsorable)
    @stripe_account = create(:stripe_connect_account, sponsors_listing: @sponsorable.sponsors_listing)
  end

  if GitHub.sponsors_enabled?
    test "sends email when Stripe account belongs to sponsorable" do
      assert_emails 1 do
        assert SponsorsTransactionReversalNotificationJob.perform_now(
          sponsor: @sponsor,
          sponsorable: @sponsorable,
          stripe_account: @stripe_account,
        )
      end
    end

    test "does not send email if Stripe account does not belong to sponsorable" do
      other_stripe_account = create(:stripe_connect_account)

      refute other_stripe_account.belongs_to?(@sponsorable)

      assert_emails 0 do
        refute SponsorsTransactionReversalNotificationJob.perform_now(
          sponsor: @sponsor,
          sponsorable: @sponsorable,
          stripe_account: other_stripe_account,
        )
      end
    end
  else
    test "does not send email when GitHub Sponsors is not enabled" do
      assert_emails 0 do
        refute SponsorsTransactionReversalNotificationJob.perform_now(
          sponsor: @sponsor,
          sponsorable: @sponsorable,
          stripe_account: @stripe_account,
        )
      end
    end
  end
end
