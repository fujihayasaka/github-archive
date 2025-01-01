# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListing::FiscalHostOrgsExportTest < GitHub::TestCase
  include ActionView::Helpers::NumberHelper

  fixtures do
    @osc_admin = create(:user)
  end

  setup do
    skip unless GitHub.sponsors_enabled?

    travel_to "2020-09-19" do
      @osc = create(:organization, :open_source_collective, admin: @osc_admin)
      @osc_listing = @osc.sponsors_listing
      @osc_listing.update!(is_fiscal_host: true)

      @waitlisted_listing = create(:sponsors_listing, :for_org, :waitlisted,
        parent_listing: @osc_listing, sponsorable_login: "aaa")
      @waitlisted_org = @waitlisted_listing.sponsorable
      @waitlisted_org.profile_name = "AAA Org"
      @waitlisted_org.profile.save

      @draft_listing = create(:sponsors_listing, :for_org, :draft,
        parent_listing: @osc_listing, sponsorable_login: "ccc")
      @draft_org = @draft_listing.sponsorable
      @draft_org.profile_name = "CCC Org"
      @draft_org.profile.save

      @approved_listing = create(:sponsors_listing, :for_org, :approved, tier_count: 0,
        parent_listing: @osc_listing, sponsorable_login: "bbb")
      @approved_org = @approved_listing.sponsorable
      @approved_org.profile_name = "BBB Org"
      @approved_org.profile.save
    end
  end

  context "#as_csv" do
    test "returns CSV of all orgs associated with fiscal host" do
      export = SponsorsListing::FiscalHostOrgsExport.new(sponsors_listing: @osc_listing, viewer: @osc_admin)

      expected_headers = [
        "Login",
        "Name",
        "Profile status",
        "Billing county",
        "Country of residence",
        "Joined waitlist on",
        "Profile published on",
      ]

      expected_waitlisted_org = [
        "aaa",
        "AAA Org",
        "waitlisted",
        "US",
        "US",
        "2020-09-19",
        nil
      ].join(",")

      expected_draft_org = [
        "ccc",
        "CCC Org",
        "draft",
        "US",
        "US",
        "2020-09-19",
        nil
      ].join(",")

      expected_approved_org = [
        "bbb",
        "BBB Org",
        "approved",
        "US",
        "US",
        "2020-09-19",
        "2020-09-19"
      ].join(",")

      # these are lexicographically order by sponsorable login
      expected = <<~CSV
        #{expected_headers.join(",")}
        #{expected_waitlisted_org}
        #{expected_approved_org}
        #{expected_draft_org}
      CSV

      assert_equal expected, export.as_csv
    end

    test "query count does not depend on org count" do
      initial_query_count = count_queries do
        SponsorsListing::FiscalHostOrgsExport.new(sponsors_listing: @osc_listing, viewer: @osc_admin).as_csv
      end

      assert_difference -> { @osc_listing.child_listings.count } do
        create(:sponsors_listing, :for_org, :pending_approval, tier_count: 0, parent_listing: @osc.sponsors_listing)
      end

      added_org_query_count = count_queries do
        SponsorsListing::FiscalHostOrgsExport.new(sponsors_listing: @osc_listing, viewer: @osc_admin).as_csv
      end

      assert_equal added_org_query_count, initial_query_count
    end
  end

  context "#filename" do
    test "filename includes fiscal host and date" do
      export = SponsorsListing::FiscalHostOrgsExport.new(sponsors_listing: @osc_listing, viewer: @osc_admin)
      assert_equal "sponsors-#{@osc}-orgs-#{Date.current}.csv", export.filename
    end
  end
end
