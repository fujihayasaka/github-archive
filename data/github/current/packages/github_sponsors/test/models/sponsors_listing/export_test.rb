# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListingExportTest < GitHub::TestCase
  fixtures do
    @submitted_user = create(:user)
    @accepted_user = create(:user)
    @banned_user = create(:user)
    create(:profile, user: @banned_user, name: "A Pleasant Title")
    @accepted_org = create(:organization)
    create(:profile, user: @accepted_org, name: "Some Nice Name")

    @waitlisted_listing = create(:sponsors_listing, :waitlisted, sponsorable: @submitted_user, joined_at: 2.days.ago)
    @draft_listing = create(:sponsors_listing, sponsorable: @accepted_user, joined_at: 1.day.ago)
    @banned_listing = create(:sponsors_listing, :banned, sponsorable: @banned_user)
    @draft_org_listing = create(:sponsors_listing, sponsorable: @accepted_org, joined_at: 3.days.ago)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  context "#as_csv" do
    test "returns CSV of all listings" do
      export = SponsorsListing::Export.new
      expected = <<~CSV
        state,login,name,email,joined_at
        #{listing_csv_row(@draft_org_listing)}
        #{listing_csv_row(@waitlisted_listing)}
        #{listing_csv_row(@draft_listing)}
        #{listing_csv_row(@banned_listing)}
      CSV

      assert_equal expected, export.as_csv
    end

    test "filters only listings for those accepted into the program" do
      export = SponsorsListing::Export.new(filter: [:draft, :pending_approval, :approved])
      expected = <<~CSV
        state,login,name,email,joined_at
        #{listing_csv_row(@draft_org_listing)}
        #{listing_csv_row(@draft_listing)}
      CSV

      assert_equal expected, export.as_csv
    end
  end

  def listing_csv_row(listing)
    "#{listing.current_state_name},#{listing.sponsorable},#{listing.sponsorable.profile_name}," \
      "#{listing.sponsorable.billing_email},#{listing.joined_at}"
  end
end
