# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsUpdateSponsorsListingTest < GitHub::TestCase
  fixtures do
    @sponsorable = create(:user)
    @new_short_description = "New short description"
    @new_full_description = "New full description"

    @sponsors_listing = create(:sponsors_listing, :approved, sponsorable: @sponsorable,
      featured_state: "disabled")
  end

  context "sponsors listing update" do
    test "sponsorable updates sponsors listing" do
      refute_predicate @sponsors_listing, :hide_past_sponsorships?
      refute_predicate @sponsors_listing.featured_sponsorships_settings, :enabled?
      refute_predicate @sponsors_listing.featured_sponsorships_settings, :automatic?

      updated_listing = Sponsors::UpdateSponsorsListing.call(
        slug: @sponsors_listing.slug,
        short_description: @new_short_description,
        full_description: @new_full_description,
        featured_state: "allowed",
        viewer: @sponsorable,
        hide_past_sponsorships: true,
        enable_featured_sponsorships: true,
        automate_featured_sponsorships: true,
      )

      assert_equal @new_short_description, updated_listing.short_description
      assert_equal @new_short_description, updated_listing.featured_description
      assert_equal @new_full_description, updated_listing.full_description
      assert_predicate updated_listing, :featured_allowed?
      assert_predicate updated_listing, :hide_past_sponsorships?
      assert_predicate updated_listing.featured_sponsorships_settings, :enabled?
      assert_predicate updated_listing.featured_sponsorships_settings, :automatic?
    end

    test "errors when bizdev updates sponsors listing" do
      bizdev = create(:biztools_user)

      error = assert_raises Sponsors::UpdateSponsorsListing::ForbiddenError do
        Sponsors::UpdateSponsorsListing.call(
          slug: @sponsors_listing.slug,
          full_description: @new_full_description,
          viewer: bizdev,
        )
      end
      assert_equal "#{bizdev.login} does not have permission to update the sponsors listing.", error.message
    end

    test "errors when site admin updates sponsors listing" do
      site_admin = create(:staff_admin_user)

      error = assert_raises Sponsors::UpdateSponsorsListing::ForbiddenError do
        Sponsors::UpdateSponsorsListing.call(
          slug: @sponsors_listing.slug,
          full_description: @new_full_description,
          viewer: site_admin,
        )
      end
      assert_equal "#{site_admin.login} does not have permission to update the sponsors listing.", error.message
    end

    test "errors when non-sponsorable updates sponsors listing" do
      user = create(:user)

      error = assert_raises Sponsors::UpdateSponsorsListing::ForbiddenError do
        Sponsors::UpdateSponsorsListing.call(
          slug: @sponsors_listing.slug,
          full_description: @new_full_description,
          viewer: user,
        )
      end
      assert_equal "#{user.login} does not have permission to update the sponsors listing.", error.message
    end
  end
end unless GitHub.enterprise?
