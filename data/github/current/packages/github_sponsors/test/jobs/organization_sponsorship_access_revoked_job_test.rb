# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class OrganizationSponsorshipAccessRevokedJobTest < GitHub::TestCase
  include JobTestHelper
  include HydroTestHelpers
  include GitHub::SponsorsInstrumentationTestHelpers

  fixtures do
    @business = create(:business)
    @org_sponsor = create(:organization, business: @business)
    @active_sponsorship1, @active_sponsorship2 = create_pair(:sponsorship, sponsor: @org_sponsor)
    @inactive_sponsorship = create(:sponsorship, :inactive, sponsor: @org_sponsor)

    @unrelated_sponsorship = create(:sponsorship)
  end

  test "immediately cancels active sponsorships for an organization" do
    assert_predicate @active_sponsorship1, :active?
    assert_predicate @active_sponsorship2, :active?
    refute_predicate @inactive_sponsorship, :active?
    assert_predicate @unrelated_sponsorship, :active?

    OrganizationSponsorshipAccessRevokedJob.perform_now(organization: @org_sponsor, actor: @business.admins.first)

    refute_predicate @active_sponsorship1.reload, :active?
    refute_predicate @active_sponsorship2.reload, :active?
    refute_predicate @inactive_sponsorship.reload, :active?
    assert_predicate @unrelated_sponsorship.reload, :active?
  end

  test "only enqueues one job per organization" do
    assert_enqueued_jobs 1, only: OrganizationSponsorshipAccessRevokedJob do
      OrganizationSponsorshipAccessRevokedJob.perform_later(organization: @org_sponsor, actor: @business.admins.first)
      OrganizationSponsorshipAccessRevokedJob.perform_later(organization: @org_sponsor, actor: create(:user))
    end
  end

  test "instruments Hydro event SponsorshipCancelRequest for each active sponsorship cancellation" do
    OrganizationSponsorshipAccessRevokedJob.perform_now(organization: @org_sponsor, actor: @business.admins.first)

    assert_sponsorship_cancel_request_hydro_published(
      sponsorship: @active_sponsorship1,
      reason: :BUSINESS_REVOKED_ORG_SPONSOR_ACCESS,
      actor: @business.admins.first,
    )
    assert_sponsorship_cancel_request_hydro_published(
      sponsorship: @active_sponsorship2,
      reason: :BUSINESS_REVOKED_ORG_SPONSOR_ACCESS,
      actor: @business.admins.first,
    )
    assert_hydro_messages(count: 2, schema: "github.sponsors.v1.SponsorshipCancelRequest")
  end
end if GitHub.sponsors_enabled?
