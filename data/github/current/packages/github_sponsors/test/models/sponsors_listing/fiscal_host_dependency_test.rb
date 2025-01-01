# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListing::FiscalHostDependencyTest < GitHub::TestCase
  fixtures do
    @osc = create(:organization, :open_source_collective)
    @fiscal_host_listing = create(:sponsors_listing, :fiscal_host, :with_customized_sponsorable_profile,
      sponsorable_login: "numfocus")
    @listing = create(:sponsors_listing)
  end

  test "syncs country of residence with billing country for org with fiscal host on listing creation" do
    org = create(:organization)
    listing = create(:sponsors_listing, :with_fiscal_host, sponsorable: org, parent_listing: @fiscal_host_listing)

    assert_equal @fiscal_host_listing.billing_country, listing.reload.billing_country
    assert_equal @fiscal_host_listing.billing_country, listing.country_of_residence
  end

  context "validations" do
    test "parent listing must be a fiscal host" do
      listing = SponsorsListing.new(parent_listing: @listing)
      refute_predicate listing, :valid?
      assert_includes listing.errors[:parent_listing], "must be a fiscal host listing"
    end

    test "disallows a fiscal host listing to also be a child listing" do
      listing = SponsorsListing.new(parent_listing_id: 1, is_fiscal_host: true)
      refute_predicate listing, :valid?
      assert_includes listing.errors[:parent_listing_id], "must be nil for fiscal host listing"
    end

    test "requires fiscal host listing to have an org sponsorable" do
      user = create(:user, :verified)
      listing = SponsorsListing.new(is_fiscal_host: true, sponsorable: user)
      refute_predicate listing, :valid?
      assert_includes listing.errors[:sponsorable], "must be an organization for fiscal host listing"
    end

    test "disallows more than one level of child listings" do
      child_listing = create(:sponsors_listing, :with_fiscal_host)
      grandchild_listing = SponsorsListing.new(parent_listing: child_listing)
      refute_predicate grandchild_listing, :valid?
      assert_includes grandchild_listing.errors[:parent_listing], "is already a child listing"
    end
  end

  context ".fiscal_host_usage_counts" do
    test "returns count of how many listings use each requested fiscal host" do
      parent_listing1 = create(:sponsors_listing, :fiscal_host)
      parent_listing2 = create(:sponsors_listing, :fiscal_host)
      parent_listing3 = create(:sponsors_listing, :fiscal_host)
      create(:sponsors_listing, :with_fiscal_host, parent_listing: parent_listing1)
      create(:sponsors_listing, :with_fiscal_host, parent_listing: parent_listing2)
      create(:sponsors_listing, :with_fiscal_host, parent_listing: parent_listing2)

      result = SponsorsListing.fiscal_host_usage_counts([
        parent_listing1.sponsorable_login,
        parent_listing2.sponsorable_login,
        parent_listing3.sponsorable_login,
      ])

      assert_equal 1, result[parent_listing1.sponsorable_login]
      assert_equal 2, result[parent_listing2.sponsorable_login]
      assert_equal 0, result[parent_listing3.sponsorable_login]
    end
  end

  context ".fiscal_host_organization" do
    test "returns organization for the given fiscal host name" do
      assert_equal @osc, SponsorsListing.fiscal_host_organization(SponsorsListing::FiscalHostDependency::OPEN_SOURCE_COLLECTIVE_LOGIN)
    end

    test "returns nil when no organization exists for given value" do
      assert_nil SponsorsListing.fiscal_host_organization("some_nonexistent_org_login")
    end

    test "returns nil when invalid fiscal host is given" do
      create(:organization, login: "InvalidFiscalHost")
      assert_nil SponsorsListing.fiscal_host_organization("InvalidFiscalHost")
    end
  end

  context ".fiscal_host_listing" do
    test "returns listing for the given fiscal host name" do
      assert_equal @osc.sponsors_listing,
        SponsorsListing.fiscal_host_listing(SponsorsListing::FiscalHostDependency::OPEN_SOURCE_COLLECTIVE_LOGIN)
    end

    test "returns nil when no organization exists for given value" do
      refute Organization.exists?(login: "some_nonexistent_org_login")
      assert_nil SponsorsListing.fiscal_host_listing("some_nonexistent_org_login")
    end

    test "returns nil when invalid fiscal host is given" do
      create(:organization, :sponsorable, login: "notARealFiscalHost")
      assert_nil SponsorsListing.fiscal_host_listing("notARealFiscalHost")
    end

    test "returns nil when org exists but no listing exists for given value" do
      create(:organization, login: "Open-Collective-Foundation")
      assert_nil SponsorsListing.fiscal_host_listing("Open-Collective-Foundation")
    end
  end

  context "#uses_fiscal_host?" do
    test "true when listing has a parent listing" do
      listing = build(:sponsors_listing, parent_listing: @fiscal_host_listing)
      assert_predicate listing, :uses_fiscal_host?
    end

    test "false when listing does not have a parent listing" do
      listing = build(:sponsors_listing, parent_listing: nil)
      refute_predicate listing, :uses_fiscal_host?
    end
  end

  context "#uses_open_source_collective_as_fiscal_host?" do
    test "true for listing with Open-Source-Collective as its parent listing" do
      child_listing = create(:sponsors_listing, parent_listing: @osc.sponsors_listing)
      assert_predicate child_listing, :uses_open_source_collective_as_fiscal_host?
    end

    test "false for listing with no parent listing" do
      listing = create(:sponsors_listing, parent_listing: nil)
      refute_predicate listing, :uses_open_source_collective_as_fiscal_host?
    end

    test "false for listing with a different fiscal host for its parent listing" do
      parent_listing = create(:sponsors_listing, :fiscal_host)
      refute_equal SponsorsListing::FiscalHostDependency::OPEN_SOURCE_COLLECTIVE_LOGIN,
        parent_listing.sponsorable_login
      child_listing = create(:sponsors_listing, parent_listing: parent_listing)
      refute_predicate child_listing, :uses_open_source_collective_as_fiscal_host?
    end
  end

  context ".human_fiscal_host" do
    test "returns fiscal host login when no profile name is set" do
      assert_equal SponsorsListing::FiscalHostDependency::OPEN_SOURCE_COLLECTIVE_LOGIN,
        SponsorsListing.human_fiscal_host(SponsorsListing::FiscalHostDependency::OPEN_SOURCE_COLLECTIVE_LOGIN)
    end

    test "returns fiscal host profile name when set" do
      create(:profile, user: @osc, name: "A nice display name")
      assert_equal "A nice display name",
        SponsorsListing.human_fiscal_host(SponsorsListing::FiscalHostDependency::OPEN_SOURCE_COLLECTIVE_LOGIN)
    end

    test "returns 'none' or 'other' when given" do
      assert_equal "none", SponsorsListing.human_fiscal_host("none")
      assert_equal "other", SponsorsListing.human_fiscal_host("other")
    end

    test "returns nil when a non-fiscal host value is given" do
      create(:organization, login: "someOrg")
      assert_nil SponsorsListing.human_fiscal_host("someOrg")
    end
  end

  context "#human_fiscal_host" do
    test "returns display name of the parent listing's sponsorable" do
      @fiscal_host_listing.sponsorable.profile.update!(name: "Some Neat Fiscal Host")
      listing = build(:sponsors_listing, parent_listing: @fiscal_host_listing)
      assert_equal "Some Neat Fiscal Host", listing.human_fiscal_host
    end

    test "returns 'none' when listing does not use a fiscal host" do
      refute_predicate @listing, :uses_fiscal_host?, "need a listing that doesn't use a fiscal host"
      assert_equal "none", @listing.human_fiscal_host
    end
  end

  context "filter_by_fiscal_host scope" do
    test "returns listings not using a supported fiscal host" do
      refute_predicate @listing, :uses_fiscal_host?, "need a listing that isn't fiscally hosted"
      listing1 = create(:sponsors_listing, :with_fiscal_host)

      result = SponsorsListing.filter_by_fiscal_host("none")
        .where(id: [listing1, @listing])
        .pluck(:id)

      refute_includes result, listing1.id
      assert_includes result, @listing.id
    end

    test "returns listings using the specified fiscal host" do
      refute_predicate @listing, :uses_fiscal_host?, "need a non-fiscally hosted listing"
      listing1 = create(:sponsors_listing, :with_fiscal_host)

      result = SponsorsListing.filter_by_fiscal_host(listing1.parent_sponsorable_login)
        .where(id: [listing1, @listing])
        .pluck(:id)

      assert_includes result, listing1.id
      refute_includes result, @listing.id
    end

    test "returns listings matching any of the given filters" do
      listing1 = create(:sponsors_listing, :with_fiscal_host)
      listing2 = create(:sponsors_listing, :with_fiscal_host)
      listing3 = create(:sponsors_listing, :with_fiscal_host)
      filters = [listing1.parent_sponsorable_login, listing2.parent_sponsorable_login, "other"]

      result = SponsorsListing.filter_by_fiscal_host(filters)
        .where(id: [listing1, listing2, listing3, @listing])
        .pluck(:id)

      assert_includes result, listing1.id
      assert_includes result, listing2.id
      refute_includes result, listing3.id
      refute_includes result, @listing.id
    end
  end

  context "child_listings relation" do
    test "includes other listings that have the listing as their parent" do
      child1 = create(:sponsors_listing, :with_fiscal_host)
      parent = child1.parent_listing
      child2 = create(:sponsors_listing, :with_fiscal_host, parent_listing: parent)

      assert_same_elements [child1, child2], parent.child_listings
      assert_empty child1.child_listings
      assert_empty child2.child_listings
    end
  end

  context "without_parent_listing scope" do
    test "includes listings with no parent listing" do
      uses_supported_fiscal_host = create(:sponsors_listing, :with_fiscal_host)
      all_listings = [@listing, uses_supported_fiscal_host]

      result = SponsorsListing.without_parent_listing.
        where(id: all_listings).pluck(:id)

      assert_includes result, @listing.id
      refute_includes result, uses_supported_fiscal_host.id
    end
  end

  context "fiscal_hosts scope" do
    test "includes listings marked with is_fiscal_host=true" do
      result = SponsorsListing.fiscal_hosts

      assert_includes result, @fiscal_host_listing,
        "should include a listing marked with is_fiscal_host=true"
      refute_includes result, @listing,
        "should not include listing that isn't marked as one"
    end
  end

  context "fiscal_hosts_visible_for_signup scope" do
    test "includes all fiscal hosts that are not marked as hidden" do
      refute_includes SponsorsListing::FiscalHostDependency::USER_HIDDEN_FISCAL_HOSTS,
        @fiscal_host_listing.sponsorable_login
      refute_includes SponsorsListing::FiscalHostDependency::USER_HIDDEN_FISCAL_HOSTS, @osc.login
      hidden_fiscal_host_listing = create(:sponsors_listing, :fiscal_host,
        sponsorable_login: SponsorsListing::FiscalHostDependency::USER_HIDDEN_FISCAL_HOSTS.first)

      result = SponsorsListing.fiscal_hosts_visible_for_signup
        .where(id: [@fiscal_host_listing, @osc.sponsors_listing, hidden_fiscal_host_listing])

      assert_includes result, @fiscal_host_listing, "should include a fiscal host listing that is not hidden"
      assert_includes result, @osc.sponsors_listing, "should include a fiscal host listing that is not hidden"
      refute_includes result, hidden_fiscal_host_listing, "should not include a fiscal host listing that is hidden"
    end
  end

  context "#can_use_fiscal_host?" do
    test "returns true for a non-fiscal host org listing" do
      listing = build(:sponsors_listing, :for_org)
      assert_predicate listing, :can_use_fiscal_host?
    end

    test "returns false for fiscal host org listing" do
      refute_predicate @osc.sponsors_listing, :can_use_fiscal_host?
    end

    test "returns true for user listing" do
      listing = build(:sponsors_listing)
      assert_predicate listing, :can_use_fiscal_host?
    end
  end

  context "fiscally_hosted_project_profile_survey_answer relation" do
    test "returns the sponsorable's answer to the fiscal host project profile survey question" do
      sponsorable = create(:user, :verified)
      listing = create(:sponsors_listing, :with_fiscal_host, sponsorable: sponsorable,
        fiscally_hosted_project_profile_url: "http://example.com/whee")
      choice = listing.first_fiscally_hosted_project_profile_survey_choice
      refute_nil choice
      expected_answer = choice.answers.find_by!(user_id: listing.sponsorable_id)

      actual_answer = listing.reload_fiscally_hosted_project_profile_survey_answer

      refute_nil actual_answer
      assert_equal expected_answer, actual_answer
      assert_equal "http://example.com/whee", actual_answer.other_text
    end
  end
end
