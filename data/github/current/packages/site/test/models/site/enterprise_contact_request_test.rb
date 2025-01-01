# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseContactRequestTest < GitHub::TestCase
  setup do
    @enterprise_contact_request = build(:enterprise_contact_request, :with_utm_info, :with_remote_ip, :with_referral_info)
  end

  context "validations" do
    test "validates presence of `first_name` and `last_name`" do
      @enterprise_contact_request.first_name = nil
      @enterprise_contact_request.last_name = nil

      refute_valid @enterprise_contact_request
      assert_includes @enterprise_contact_request.errors[:first_name], "can't be blank"
      assert_includes @enterprise_contact_request.errors[:last_name], "can't be blank"
    end

    test "validates presense of `company`" do
      @enterprise_contact_request.company = nil

      refute_valid @enterprise_contact_request
      assert_includes @enterprise_contact_request.errors[:company], "can't be blank"
    end

    test "validates presense of `email`" do
      @enterprise_contact_request.email = nil

      refute_valid @enterprise_contact_request
      assert_includes @enterprise_contact_request.errors[:email], "can't be blank"
    end

    test "validates format of `email`" do
      @enterprise_contact_request.email = "invalid-email@hey"

      refute_valid @enterprise_contact_request
      assert_includes @enterprise_contact_request.errors[:email], "is invalid"
    end

    test "validates format of `email` with personal domain" do
      @enterprise_contact_request.email = "invalid-email-domain@yandex.com"

      refute_valid @enterprise_contact_request

      assert_includes @enterprise_contact_request.errors[:email], "is invalid"
    end

    test "validates format of `email` with personal domain and excluded tld" do
      @enterprise_contact_request.email = "invalid-email-domain@yandex.net"

      refute_valid @enterprise_contact_request

      assert_includes @enterprise_contact_request.errors[:email], "is invalid"
    end

    test "allows valid email domain" do
      @enterprise_contact_request.email = "mona-lisa@github.com"

      assert_valid @enterprise_contact_request
      refute @enterprise_contact_request.errors.include?(:email)
    end
  end

  context "callbacks" do
    test "generates a submission_id before validation" do
      @enterprise_contact_request.submission_id = nil

      assert_valid @enterprise_contact_request

      uuid_match = /[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}/
      assert_match uuid_match, @enterprise_contact_request.submission_id
    end
  end

  context "#enqueue_submission_job" do
    test "enqueues a job for submitting enterprise_contact_request data" do
      @enterprise_contact_request.save

      assert_enqueued_with(
        job: EnterpriseContactRequestSubmissionJob,
      ) do
        @enterprise_contact_request.enqueue_submission_job
      end
    end

    test "doesn't enqueue the job if the contact request hasn't been saved" do
      @enterprise_contact_request.enqueue_submission_job

      assert_no_enqueued_jobs
    end
  end

  context "#status" do
    test "defaults to `:submission_pending`" do
      assert_predicate @enterprise_contact_request, :submission_pending?
    end

    test "setting the sync status to `:submitted`" do
      @enterprise_contact_request.submitted!

      assert_predicate @enterprise_contact_request, :submitted?
    end
  end

  context "#marketing_forms_data" do
    test "maps contact request data to properties for marketing forms api" do
      expected_data = {
        title: @enterprise_contact_request.job_title,
        company: @enterprise_contact_request.company,
        contactComments: @enterprise_contact_request.request_details,
        country: @enterprise_contact_request.country,
        email_address: @enterprise_contact_request.email,
        first_name: @enterprise_contact_request.first_name,
        last_name: @enterprise_contact_request.last_name,
        marketingConsent: "optInExplicit",
        phone: @enterprise_contact_request.phone,
        cDLProgramName: @enterprise_contact_request.cdl_program_name,
        source: @enterprise_contact_request.source,
        sFDCLastCampaignStatus: @enterprise_contact_request.salesforce_campaign_status,
        referrer_details: @enterprise_contact_request.__send__(:referrer_details),
        utm_campaign: @enterprise_contact_request.utm_campaign,
        utm_medium: @enterprise_contact_request.utm_medium,
        utm_source: @enterprise_contact_request.utm_source,
      }

      assert_equal expected_data, @enterprise_contact_request.marketing_forms_data
    end

    test "marketingConsent is nil when marketing_email_opt_in is false" do
      @enterprise_contact_request.marketing_email_opt_in = false

      assert_nil @enterprise_contact_request.marketing_forms_data[:marketingConsent]
    end
  end

  test "#cdl_program_name" do
    assert_equal GitHub.enterprise_contact_campaign_id, @enterprise_contact_request.cdl_program_name
  end

  context "#source" do
    test "from config value" do
      assert_equal GitHub.enterprise_contact_source, @enterprise_contact_request.source
    end

    test "defaults to cdl_program_name" do
      GitHub.stubs(:enterprise_contact_source).returns(nil)
      assert_equal @enterprise_contact_request.cdl_program_name, @enterprise_contact_request.source
    end

    test "uses default if configured value is blank" do
      GitHub.stubs(:enterprise_contact_source).returns("")
      assert_equal @enterprise_contact_request.cdl_program_name, @enterprise_contact_request.source
    end
  end

  test "#salesforce_campaign_status" do
    assert_equal GitHub.enterprise_contact_status, @enterprise_contact_request.salesforce_campaign_status
  end
end
