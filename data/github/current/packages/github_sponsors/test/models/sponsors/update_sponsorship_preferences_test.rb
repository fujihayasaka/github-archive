# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsUpdateSponsorshipPreferencesTest < GitHub::TestCase
  include HydroTestHelpers

  skip_unless :sponsors_enabled?

  fixtures do
    @listing = create(:sponsors_listing, :with_valid_contact_for_billing, :approved)
    @sponsorable = @listing.sponsorable
    @sponsorship = create(:sponsorship, :sponsor_with_valid_contact_for_billing, sponsorable: @sponsorable, is_sponsor_opted_in_to_email: true,
      privacy_level: "public")
    @tier = @sponsorship.tier
    @sponsor = @sponsorship.sponsor

    @invoiced_org_admin = create(:user, :verified)
    @invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription,
      admin: @invoiced_org_admin)
    @invoiced_org_sponsorship = create(:sponsorship, :sponsors_invoiced, sponsor: @invoiced_org)
  end

  test "raises if end date is specified and sponsor is not an organization" do
    error = assert_raises Sponsors::UpdateSponsorship::UnprocessableError do
      Sponsors::UpdateSponsorshipPreferences.call(@sponsorship, viewer: @sponsor, end_date: 3.months.from_now.to_date)
    end
    assert_equal "You cannot set an end date for this sponsorship.", error.message
  end

  test "changes end date for invoiced org's Zuora-based sponsorship", skip_enterprise: true do
    old_expires_at = @invoiced_org_sponsorship.expires_at
    new_end_date = (old_expires_at + 1.month).to_date

    Sponsors::UpdateSponsorshipPreferences.call(@invoiced_org_sponsorship, viewer: @invoiced_org_admin,
      end_date: new_end_date)

    assert_equal new_end_date, @invoiced_org_sponsorship.reload.expires_at.to_date
  end

  test "toggles privacy from public to private" do
    assert_predicate @sponsorship, :privacy_public?

    Sponsors::UpdateSponsorshipPreferences.call(@sponsorship, is_public: false, viewer: @sponsor)

    assert_predicate @sponsorship.reload, :privacy_private?
  end

  test "instruments sponsor_sponsorship_preference_change audit log event if privacy changed" do
    assert_predicate @sponsorship, :privacy_public?

    events = subscribe "sponsors.sponsor_sponsorship_preference_change"
    expected_payload = {
      sponsorable_user: @sponsorable.login,
      sponsorable_user_id: @sponsorable.id,
      actor: @sponsor.login,
      actor_id: @sponsor.id,
      user: @sponsor.login,
      user_id: @sponsor.id,
      active: true,
      public: false,
      sponsor: @sponsor.login,
      frequency: "recurring",
      sponsor_id: @sponsor.id,
      current_tier_id: @tier.id,
      current_tier_monthly_amount_in_cents: @tier.monthly_price_in_cents,
      sponsorship_id: @sponsorship.id,
      payment_source: "github",
    }

    Sponsors::UpdateSponsorshipPreferences.call(@sponsorship, is_public: false, viewer: @sponsor)

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
    assert_predicate @sponsorship.reload, :privacy_private?
  end

  test "instruments sponsor_sponsorship_edited audit log event if privacy changed" do
    assert_predicate @sponsorship, :privacy_public?

    events = subscribe "sponsors.sponsor_sponsorship_edited"
    expected_payload = {
      sponsorable_user: @sponsorable.login,
      sponsorable_user_id: @sponsorable.id,
      actor: @sponsor.login,
      actor_id: @sponsor.id,
      user: @sponsor.login,
      user_id: @sponsor.id,
      public: false,
      current_tier_id: @tier.id,
      current_tier_monthly_amount_in_cents: @tier.monthly_price_in_cents,
      sponsorship_id: @sponsorship.id,
      active: true,
      frequency: "recurring",
      sponsor: @sponsor.login,
      sponsor_id: @sponsor.id,
      changes: { privacy_level: { from: "public" } },
      payment_source: "github",
    }

    Sponsors::UpdateSponsorshipPreferences.call(@sponsorship, is_public: false, viewer: @sponsor)

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
    assert_predicate @sponsorship.reload, :privacy_private?
  end

  test "publishes privacy preference change to hydro", skip_enterprise: true do
    now = Time.parse("2018-01-01")
    previous_sponsorship_data = Hydro::EntitySerializer.sponsorship(@sponsorship)
    assert_equal "public", previous_sponsorship_data[:privacy_level]

    travel_to(now) do
      Sponsors::UpdateSponsorshipPreferences.call(@sponsorship, is_public: false, viewer: @sponsor)

      new_sponsorship_data = Hydro::EntitySerializer.sponsorship(@sponsorship.reload)
      assert_equal "private", new_sponsorship_data[:privacy_level]

      message = {
        actor: Hydro::EntitySerializer.user(@sponsor),
        request_context: nil,
        previous_sponsorship: previous_sponsorship_data,
        current_sponsorship: new_sponsorship_data,
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@tier),
      }

      assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipPreferenceChange")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipPreferenceChange")

      # Verify no create/cancel message sent for a privacy change:
      assert_hydro_messages(count: 0, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end
  end

  test "raises an error if no viewer is provided" do
    assert_raises Sponsors::UpdateSponsorship::ForbiddenError do
      Sponsors::UpdateSponsorshipPreferences.call(@sponsorship, viewer: nil)
    end
  end

  test "raises an error if no sponsorship is given" do
    assert_raises Sponsors::UpdateSponsorship::UnprocessableError do
      Sponsors::UpdateSponsorshipPreferences.call(nil, viewer: @sponsor)
    end
  end

  test "raises an error if viewer cannot admin sponsorship" do
    rando = create(:user, :verified)
    assert_raises Sponsors::UpdateSponsorship::ForbiddenError do
      Sponsors::UpdateSponsorshipPreferences.call(@sponsorship, viewer: rando)
    end
  end

  test "raises an error if viewer cannot see sponsorship" do
    other_private_sponsorship = create(:sponsorship, :private, sponsorable: @sponsorable)
    assert_raises Sponsors::UpdateSponsorship::ForbiddenError do
      Sponsors::UpdateSponsorshipPreferences
        .call(other_private_sponsorship, viewer: @sponsor, is_public: false)
    end
  end

  test "supports only supplying subset of preferences to update" do
    assert_predicate @sponsorship, :privacy_public?
    assert_predicate @sponsorship, :is_sponsor_opted_in_to_email?

    Sponsors::UpdateSponsorshipPreferences.call(@sponsorship, viewer: @sponsor, is_public: false)

    assert_predicate @sponsorship.reload, :privacy_private?
    assert_predicate @sponsorship, :is_sponsor_opted_in_to_email?

    Sponsors::UpdateSponsorshipPreferences.call(@sponsorship, viewer: @sponsor, email_opt_in: false)

    assert_predicate @sponsorship.reload, :privacy_private?
    refute_predicate @sponsorship, :is_sponsor_opted_in_to_email?
  end

  test "supports updating privacy of an inactive sponsorship" do
    @sponsorship.update!(active: false)

    refute_predicate @sponsorship, :active?
    assert_predicate @sponsorship, :privacy_public?

    Sponsors::UpdateSponsorshipPreferences.call(@sponsorship, viewer: @sponsor, is_public: false)

    assert_predicate @sponsorship.reload, :privacy_private?
  end

  # See https://github.com/github/sponsors/issues/2500
  test "does not affect selected at when changing privacy level of one-time tier" do
    travel_to "2023-11-13"
    listing = create(:sponsors_listing, :approved, :with_one_time_tier)
    one_time_tier = listing.published_sponsors_tiers.one_time.first
    sponsorship = travel_to 7.days.ago do
      Sponsors::AddOneTimePayment.call(
        tier: one_time_tier,
        sponsor: @sponsor,
        viewer: @sponsor,
        is_public: false,
      )
    end
    old_selected_at = sponsorship.subscribable_selected_at
    assert_predicate sponsorship, :active?

    Sponsors::UpdateSponsorshipPreferences.call(@sponsorship, viewer: @sponsor, is_public: true)

    assert_equal old_selected_at, sponsorship.reload.subscribable_selected_at
  end
end
