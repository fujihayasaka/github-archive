# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class InitializeInvoicedSponsorJobTest < GitHub::TestCase
  include JobTestHelper
  include ActionMailer::TestHelper

  fixtures do
    @org_sponsor_admin = create(:verified_user)
    @org_sponsor = create(:organization, admin: @org_sponsor_admin)
    @name = "Test Org"
    @address = {
      city: "New York City",
      country: "US",
      line1: "123 Main Street",
      postal_code: "12345",
      state: "NY",
    }
    @email = "testorg@test.com"
  end

  setup do
    @mailer = mock
    @mailer.stubs(:deliver_later)
  end

  if GitHub.sponsors_enabled?
    test "retries on a dirty exit" do
      assert_retry_on_dirty_exit job: InitializeInvoicedSponsorJob, args: [
        {
          org: @org_sponsor,
          name: @name,
          address: @address,
          email: @email
        }
      ]
    end

    test "initializes invoiced sponsor" do
      Sponsors::InvoicedSponsorAccountCreator.any_instance.expects(:setup).once

      InitializeInvoicedSponsorJob.perform_now(
        org: @org_sponsor,
        name: @name,
        address: @address,
        email: @email
      )
    end

    test "Zuorest::TooManyRequestsError is retried" do
      Sponsors::InvoicedSponsorAccountCreator.any_instance.expects(:setup).raises(Zuorest::TooManyRequestsError.new("", {}, { "RateLimit-Reset" => "600" }))

      freeze_time do
        assert_emails 0 do # failure email should not be sent on retry
          assert_enqueued_with(job: InitializeInvoicedSponsorJob, at: Time.now + 600) do
            InitializeInvoicedSponsorJob.perform_now(
              org: @org_sponsor,
              name: @name,
              address: @address,
              email: @email
            )
          end
        end
      end
    end

    test "sends email upon success" do
      Sponsors::InvoicedSponsorAccountCreator.any_instance.expects(:setup).once.returns(true)

      SponsorsPrimerMailer
        .expects(:invoiced_sponsors_setup_success)
        .with(org: @org_sponsor)
        .once
        .returns(@mailer)

      InitializeInvoicedSponsorJob.perform_now(
        org: @org_sponsor,
        name: @name,
        address: @address,
        email: @email
      )
    end

    test "sends email upon failure" do
      Sponsors::InvoicedSponsorAccountCreator.any_instance.expects(:setup).once.returns(false)

      SponsorsPrimerMailer
        .expects(:invoiced_sponsors_setup_failure)
        .with(org: @org_sponsor)
        .once
        .returns(@mailer)

      InitializeInvoicedSponsorJob.perform_now(
        org: @org_sponsor,
        name: @name,
        address: @address,
        email: @email
      )
    end

    test "include org and actor in failbot report" do
      Sponsors::InvoicedSponsorAccountCreator.any_instance.expects(:setup).once.returns(false)

      InitializeInvoicedSponsorJob.perform_now(
        org: @org_sponsor,
        name: @name,
        address: @address,
        email: @email,
        actor: @org_sponsor.admin,
      )

      report = Failbot.reports.last
      assert_equal "Failed to set up invoiced sponsors account: []", Failbot.exception_message_from_hash(report)
      assert_equal @org_sponsor.admin.id, report["gh.actor.id"]
      assert_equal @org_sponsor.id, report["gh.organization.id"]
      assert_equal @org_sponsor.id, report["sensitive_context"]["organization_id"]
    end
  else
    test "does nothing when sponsors is not enabled" do
      Sponsors::InvoicedSponsorAccountCreator.any_instance.expects(:setup).never

      InitializeInvoicedSponsorJob.perform_now(
        org: @org_sponsor,
        name: @name,
        address: @address,
        email: @email
      )
    end
  end
end
