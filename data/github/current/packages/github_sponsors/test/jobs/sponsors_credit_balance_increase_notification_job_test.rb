# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsCreditBalanceIncreaseNotificationJobTest < GitHub::TestCase
  include ActionMailer::TestHelper

  test "sends email to a Sponsors-invoiced org" do
    invoiced_org = create(:invoiced_organization, :sponsors_invoiced)
    assert_emails 1 do
      assert SponsorsCreditBalanceIncreaseNotificationJob.perform_now(
        sponsor: invoiced_org,
      )
    end
  end

  test "does not send email if org is not Sponsors-invoiced" do
    org = create(:organization)

    refute_predicate org, :sponsors_invoiced?, "User should not be sponsors-invoiced"

    assert_emails 0 do
      refute SponsorsCreditBalanceIncreaseNotificationJob.perform_now(
        sponsor: org,
      )
    end
  end

end if GitHub.sponsors_enabled?
