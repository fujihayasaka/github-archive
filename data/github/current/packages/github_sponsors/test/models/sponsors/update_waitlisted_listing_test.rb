# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsUpdateWaitlistedListingTest < GitHub::TestCase
  fixtures do
    @waitlist_user = create(:sponsorable_user, :neutral_trust, listing_traits: [:waitlisted],
      country_of_residence: "AX", billing_country: "AX")
    @waitlisted_user_listing = @waitlist_user.sponsors_listing
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  test "updates the listing" do
    new_email = create(:verified_user_email, user: @waitlist_user)
    listing_params = {
      contact_email_id: new_email.id,
      billing_country: "AF",
      country_of_residence: "AF"
    }

    Sponsors::UpdateWaitlistedListing.call(@waitlisted_user_listing, listing_params)

    assert_predicate @waitlisted_user_listing, :waitlisted?
    assert_equal new_email, @waitlisted_user_listing.reload.contact_email
    assert_equal listing_params[:billing_country], @waitlisted_user_listing.billing_country
    assert_equal listing_params[:country_of_residence], @waitlisted_user_listing.country_of_residence
  end

  test "auto-accepts waitlisted listings if billing country is updated to a supported region" do
    new_email = create(:verified_user_email, user: @waitlist_user)
    listing_params = {
      contact_email_id: new_email.id,
      billing_country: "US",
      country_of_residence: "US"
    }

    Sponsors::UpdateWaitlistedListing.call(@waitlisted_user_listing, listing_params)

    assert_predicate @waitlisted_user_listing, :draft?
  end

  test "does not process auto-accept if billing country is not updated" do
    new_email = create(:verified_user_email, user: @waitlist_user)
    listing_params = {
      contact_email_id: new_email.id,
      billing_country: "AX",
      country_of_residence: "AX"
    }

    Sponsors::UpdateWaitlistedListing.expects(:process_auto_accept).never

    Sponsors::UpdateWaitlistedListing.call(@waitlisted_user_listing, listing_params)
  end
end
