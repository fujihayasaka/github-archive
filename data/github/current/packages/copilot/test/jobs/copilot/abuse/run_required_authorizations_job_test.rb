# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::RunRequiredAuthorizationsJobTest < GitHub::TestCase
  include JobTestHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include GitHub::LoggerHelper

  setup do
    GitHub.flipper[:copilot_required_authorizations_job].enable
    GitHub.flipper[:copilot_org_auth_and_capture_job].enable

    @org = T.let(create(:credit_card_organization), Organization)
    @copilot_org = T.let(Copilot::Organization.new(@org), Copilot::Organization)
    create(:copilot_seat, organization: @org)
    create(:billing_plan_subscription, :zuora, user: @org)
  end

  test "does nothing if no required authorizations exist" do
    free_user = create(:copilot_free_user)
    free_user.user.delete

    assert_enqueued_jobs(0, only: [Copilot::Billing::OrganizationAuthAndCaptureJob, Billing::CreateAuthorizationBillingTransactionJob]) do
      Copilot::Abuse::RunRequiredAuthorizationsJob.perform_now
    end
  end

  test "ignores state: :pending_token required authorizations" do
    @copilot_org.schedule_auth_and_capture!(pending_token: true)

    assert_equal 1, Copilot::RequiredAuthorization.count

    assert_enqueued_jobs(0, only: [Copilot::Billing::OrganizationAuthAndCaptureJob, Billing::CreateAuthorizationBillingTransactionJob]) do
      Copilot::Abuse::RunRequiredAuthorizationsJob.perform_now
    end

    assert_equal 1, Copilot::RequiredAuthorization.count
  end

  test "if required authorizations exist, queues it" do
    @copilot_org.schedule_auth_and_capture!

    assert_equal 1, Copilot::RequiredAuthorization.count

    # Check that the number of auth jobs queued before and after running the req auth job is 1+ (1 new job queued)
    org_auth_jobs = enqueued_jobs_with(only: Copilot::Billing::OrganizationAuthAndCaptureJob).count
    Copilot::Abuse::RunRequiredAuthorizationsJob.perform_now
    assert_enqueued_jobs org_auth_jobs + 1, only: Copilot::Billing::OrganizationAuthAndCaptureJob
  end

  test "if unauthable authorization exist, doesn't queue it" do
    unauthable_org = create(:organization)

    Copilot::Organization.new(unauthable_org).schedule_auth_and_capture!

    assert_equal 1, Copilot::RequiredAuthorization.count

    # Check that the number of auth jobs queued before and after running the req auth job is the same (no new job queued)
    org_auth_jobs = enqueued_jobs_with(only: Copilot::Billing::OrganizationAuthAndCaptureJob).count
    Copilot::Abuse::RunRequiredAuthorizationsJob.perform_now
    assert_enqueued_jobs org_auth_jobs, only: Copilot::Billing::OrganizationAuthAndCaptureJob
  end

  test "if recent authorizations exist, deletes the RequiredAuthorization record" do
    @copilot_org.schedule_auth_and_capture!

    Timecop.travel(10.minutes) do
      perform_enqueued_jobs(only: ::Billing::CreateAuthorizationBillingTransactionJob) do
        @copilot_org.perform_auth_and_capture!
      end

      assert_equal 1, ::Billing::BillingTransaction.current_authorizations_for_customer(T.must(@copilot_org.customer).id).count
      assert_equal 1, Copilot::RequiredAuthorization.count

      Copilot::Abuse::RunRequiredAuthorizationsJob.perform_now

      assert_equal 0, Copilot::RequiredAuthorization.count
    end
  end

  test "if authorizations exist for trusted orgs, deletes the RequiredAuthorization record" do
    @copilot_org.schedule_auth_and_capture!
    @org.settings.set!(:trust_tier, TrustTiers::Tier::TRUSTED)

    assert_equal 1, Copilot::RequiredAuthorization.count

    Copilot::Abuse::RunRequiredAuthorizationsJob.perform_now

    assert_equal 0, Copilot::RequiredAuthorization.count
  end

  test "if authorizations exist that are over a month old, deletes the RequiredAuthorization record" do
    @copilot_org.schedule_auth_and_capture!
    auth = Copilot::RequiredAuthorization.last
    auth.update!(created_at: 40.days.ago)

    assert_equal 1, Copilot::RequiredAuthorization.count

    Copilot::Abuse::RunRequiredAuthorizationsJob.perform_now

    assert_equal 0, Copilot::RequiredAuthorization.count
  end

  test "if authorizations exist for business-owned orgs that can never be authed, deletes the RequiredAuthorization record" do
    org = create(:copilot_for_business_enabled_organization)
    Copilot::Organization.new(org).schedule_auth_and_capture!

    assert_equal 1, Copilot::RequiredAuthorization.count

    Copilot::Abuse::RunRequiredAuthorizationsJob.perform_now

    assert_equal 0, Copilot::RequiredAuthorization.count
  end

  test "if the org is deleted, deletes the RequiredAuthorization record" do
    @copilot_org.schedule_auth_and_capture!
    @org.destroy

    assert_equal 1, Copilot::RequiredAuthorization.count

    Copilot::Abuse::RunRequiredAuthorizationsJob.perform_now

    assert_equal 0, Copilot::RequiredAuthorization.count
  end
end if GitHub.copilot_enabled?
