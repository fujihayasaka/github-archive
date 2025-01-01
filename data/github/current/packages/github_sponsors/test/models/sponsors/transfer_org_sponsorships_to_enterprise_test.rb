# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsTransferOrgSponsorshipsToEnterpriseTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  skip_unless :sponsors_enabled?

  fixtures do
    @credit_card_org = create(:credit_card_organization)
    @enterprise = create(:business, :with_self_serve_payment)
    @sponsors_listing = create(:sponsors_listing, :approved, :with_tier, :with_one_time_tier)
    @recurring_tier = @sponsors_listing.sponsors_tiers.recurring.first
    @one_time_tier = @sponsors_listing.sponsors_tiers.one_time.first
  end

  test "creates scheduled activation of enterprise-funded recurring sponsorship" do
    org = @credit_card_org
    actor = @credit_card_org.admin
    bill_on = GitHub::Billing.today + 7.days
    sponsorship = create(:sponsorship, sponsor: org, tier: @recurring_tier)

    @enterprise.add_organization(org, actor: @enterprise.owners.first)
    org.reload

    expected_log = {
      "Body": "Sponsorships transferred from org to enterprise",
      "gh.catalog_service": "github/github_sponsors",
      "code.namespace": "Sponsors::TransferOrgSponsorshipsToEnterprise",
      "code.function": "instrument_sponsorship_transfer",
      "gh.business.id": @enterprise.id.to_s,
      "gh.organization.id": org.id.to_s,
    }

    assert_logged(**expected_log) do
      Sponsors::TransferOrgSponsorshipsToEnterprise.call(organization: org, actor: actor, bill_on: bill_on)
    end

    assert_dogstats_increment 1, "sponsors.transfer_org_sponsorships_to_enterprise.count"

    assert_predicate sponsorship.reload, :has_pending_activation?
    assert_equal bill_on, sponsorship.pending_activation_date
    assert_equal @enterprise.sponsors_plan_subscription, sponsorship.plan_subscription
  end

  test "logs errors that occcur during transfer" do
    org = @credit_card_org
    actor = @credit_card_org.admin
    bill_on = GitHub::Billing.today + 7.days
    sponsorship = create(:sponsorship, sponsor: org, tier: @recurring_tier)

    @enterprise.add_organization(org, actor: @enterprise.owners.first)
    org.reload

    Sponsors::UpdateSponsorshipTier.expects(:call).raises(
      Sponsors::UpdateSponsorship::UnprocessableError.new("nope!")
    )

    expected_log = {
      "Body": "nope!",
      "gh.catalog_service": "github/github_sponsors",
      "code.namespace": "Sponsors::TransferOrgSponsorshipsToEnterprise",
      "code.function": "report_transfer_error",
      "gh.business.id": @enterprise.id.to_s,
      "gh.sponsorship.id": sponsorship.id.to_s,
    }

    assert_logged(**expected_log) do
      Sponsors::TransferOrgSponsorshipsToEnterprise.call(organization: org, actor: actor, bill_on: bill_on)
    end

    report = Failbot.reports.last

    assert_equal "nope!", Failbot.exception_message_from_hash(report)
  end

  test "preserves one-time sponsorship" do
    org = @credit_card_org
    actor = @credit_card_org.admin
    bill_on = GitHub::Billing.today + 7.days
    sponsorship = create(:sponsorship, sponsor: org, tier: @one_time_tier)

    @enterprise.add_organization(org, actor: @enterprise.owners.first)
    org.reload

    Sponsors::TransferOrgSponsorshipsToEnterprise.call(organization: org, actor: actor, bill_on: bill_on)

    refute_predicate sponsorship.reload, :has_pending_activation?
    assert_predicate sponsorship, :active?
    assert_equal org.sponsors_plan_subscription, sponsorship.plan_subscription
  end

  test "does nothing if org has no sponsorships" do
    org = @credit_card_org
    actor = @credit_card_org.admin
    bill_on = GitHub::Billing.today + 7.days

    @enterprise.add_organization(org, actor: @enterprise.owners.first)
    org.reload

    expected_log = {
      "Body": "Invalid organization for enterprise sponsorship transfer",
      "gh.catalog_service": "github/github_sponsors",
      "code.namespace": "Sponsors::TransferOrgSponsorshipsToEnterprise",
      "code.function": "log_invalid_organization",
      "gh.business.id": @enterprise.id.to_s,
      "gh.organization.id": org.id.to_s,
      "org_invalid_reason": "no sponsorships"
    }

    assert_logged(**expected_log) do
      Sponsors::TransferOrgSponsorshipsToEnterprise.call(organization: org, actor: actor, bill_on: bill_on)
    end
  end

  test "does nothing if organization is not an enterprise member" do
    org = @credit_card_org
    actor = @credit_card_org.admin
    bill_on = GitHub::Billing.today + 7.days
    sponsorship = create(:sponsorship, sponsor: org, tier: @recurring_tier)

    expected_log = {
      "Body": "Invalid organization for enterprise sponsorship transfer",
      "gh.catalog_service": "github/github_sponsors",
      "code.namespace": "Sponsors::TransferOrgSponsorshipsToEnterprise",
      "code.function": "log_invalid_organization",
      "gh.business.id": "nil",
      "gh.organization.id": org.id.to_s,
      "org_invalid_reason": "no self serve payment for enterprise"
    }

    assert_logged(**expected_log) do
      Sponsors::TransferOrgSponsorshipsToEnterprise.call(organization: org, actor: actor, bill_on: bill_on)
    end

    refute_predicate sponsorship.reload, :has_pending_activation?
    assert_predicate sponsorship, :active?
    assert_equal org.sponsors_plan_subscription, sponsorship.plan_subscription
  end

  test "does nothing if enterprise does not use self-serve payment" do
    org = @credit_card_org
    actor = @credit_card_org.admin
    bill_on = GitHub::Billing.today + 7.days
    sponsorship = create(:sponsorship, sponsor: org, tier: @recurring_tier)

    non_self_serve_business = create(:business)
    non_self_serve_business.add_organization(org, actor: @enterprise.owners.first)
    org.reload

    expected_log = {
      "Body": "Invalid organization for enterprise sponsorship transfer",
      "gh.catalog_service": "github/github_sponsors",
      "code.namespace": "Sponsors::TransferOrgSponsorshipsToEnterprise",
      "code.function": "log_invalid_organization",
      "gh.business.id": non_self_serve_business.id.to_s,
      "gh.organization.id": org.id.to_s,
      "org_invalid_reason": "no self serve payment for enterprise"
    }

    assert_logged(**expected_log) do
      Sponsors::TransferOrgSponsorshipsToEnterprise.call(organization: org, actor: actor, bill_on: bill_on)
    end

    refute_predicate sponsorship.reload, :has_pending_activation?
    assert_predicate sponsorship, :active?
    assert_equal org.sponsors_plan_subscription, sponsorship.plan_subscription
  end

  test "does nothing if organization is Sponsors-invoiced" do
    org = create(:credit_card_org, :sponsors_invoiced)
    actor = @credit_card_org.admin
    bill_on = GitHub::Billing.today + 7.days
    sponsorship = create(:sponsorship, sponsor: org, tier: @recurring_tier)

    @enterprise.add_organization(org, actor: @enterprise.owners.first)
    org.reload

    expected_log = {
      "Body": "Invalid organization for enterprise sponsorship transfer",
      "gh.catalog_service": "github/github_sponsors",
      "code.namespace": "Sponsors::TransferOrgSponsorshipsToEnterprise",
      "code.function": "log_invalid_organization",
      "gh.business.id": @enterprise.id.to_s,
      "gh.organization.id": org.id.to_s,
      "org_invalid_reason": "sponsors-invoiced"
    }

    assert_logged(**expected_log) do
      Sponsors::TransferOrgSponsorshipsToEnterprise.call(organization: org, actor: actor, bill_on: bill_on)
    end

    refute_predicate sponsorship.reload, :has_pending_activation?
    assert_predicate sponsorship, :active?
    assert_equal org.sponsors_plan_subscription, sponsorship.plan_subscription
  end

  test "does nothing if bill_on is not in the future" do
    freeze_time

    org = @credit_card_org
    actor = @credit_card_org.admin
    bill_on = GitHub::Billing.today
    sponsorship = create(:sponsorship, sponsor: org, tier: @recurring_tier)

    @enterprise.add_organization(org, actor: @enterprise.owners.first)
    org.reload

    expected_log = {
      "Body": "Invalid organization for enterprise sponsorship transfer",
      "gh.catalog_service": "github/github_sponsors",
      "code.namespace": "Sponsors::TransferOrgSponsorshipsToEnterprise",
      "code.function": "log_invalid_organization",
      "gh.business.id": @enterprise.id.to_s,
      "gh.organization.id": org.id.to_s,
      "org_invalid_reason": "no future billing date for org"
    }

    assert_logged(**expected_log) do
      Sponsors::TransferOrgSponsorshipsToEnterprise.call(organization: org, actor: actor, bill_on: bill_on)
    end

    refute_predicate sponsorship.reload, :has_pending_activation?
    assert_predicate sponsorship, :active?
    assert_equal org.sponsors_plan_subscription, sponsorship.plan_subscription
  end
end
