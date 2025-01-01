# typed: true
# frozen_string_literal: true

require "test_helper"

LISTING_NAME_ERROR = "is unavailable. The listing name cannot be the same as an existing GitHub account unless it is your own user or organization name.".freeze

class MarketplaceListingSlugValidatorTest < GitHub::TestCase
  test "disallows reserved words as slugs" do
    slugs = %w[admin ci preview]

    Marketplace::ListingSlugValidator.stub_const(:RESERVED_SLUGS, slugs) do
      Marketplace::ListingSlugValidator::RESERVED_SLUGS.each do |slug|
        listing = build(:marketplace_listing, name: slug)

        refute_predicate listing, :valid?
        assert_includes listing.errors[:name], LISTING_NAME_ERROR
      end
    end
  end

  test "disallows reserved words as prefix in a slug" do
    slugs = %w[github gist agreements]

    Marketplace::ListingSlugValidator.stub_const(:RESERVED_SLUG_PREFIXES, slugs) do
      Marketplace::ListingSlugValidator::RESERVED_SLUG_PREFIXES.each do |slug|
        listing = build(:marketplace_listing, name: "#{slug}-abcd")

        refute_predicate listing, :valid?
        assert_includes listing.errors[:name], LISTING_NAME_ERROR
      end
    end
  end

  test "allows usage of reserved words by GitHub owned listings" do
    slugs = %w[github gist agreements]

    org = create(:github_organization)
    github_app = create(:integration, owner: org)

    Marketplace::ListingSlugValidator.stub_const(:RESERVED_SLUG_PREFIXES, slugs) do
      Marketplace::ListingSlugValidator::RESERVED_SLUG_PREFIXES.each do |slug|
        listing = build(:marketplace_listing, name: "#{slug}-abcd", listable: github_app)

        assert_predicate listing, :valid?
      end
    end
  end

  test "disallows slugs that match an existing category" do
    category = create(:marketplace_category, name: "Monitoring")
    listing = build(:marketplace_listing, name: category.name)

    refute_predicate listing, :valid?
    assert_includes listing.errors[:name], LISTING_NAME_ERROR
  end

  test "disallows slugs that match another user's login when integratable is an OAuth app" do
    other_user = create(:user)
    listing = build(:marketplace_listing, name: other_user.login)

    refute_predicate listing, :valid?
    assert_includes listing.errors[:name], LISTING_NAME_ERROR
  end

  test "disallows slugs that match another org's login when integratable is an OAuth app" do
    other_org = create(:organization)
    listing = build(:marketplace_listing, name: other_org.login)

    refute_predicate listing, :valid?
    assert_includes listing.errors[:name], LISTING_NAME_ERROR
  end

  test "disallows slugs that match another user's login when integratable is a GitHub app" do
    other_user = create(:user)
    listing = build(:marketplace_listing, :integration, name: other_user.login)

    refute_predicate listing, :valid?
    assert_includes listing.errors[:name], LISTING_NAME_ERROR
  end

  test "disallows slugs that match another org's login when integratable is a GitHub app" do
    other_org = create(:organization)
    listing = build(:marketplace_listing, :integration, name: other_org.login)

    refute_predicate listing, :valid?
    assert_includes listing.errors[:name], LISTING_NAME_ERROR
  end

  test "allows slugs that match user login if OAuth app owned by same user" do
    user = create(:user)
    oauth_application = create(:oauth_application, user: user)
    listing = build(:marketplace_listing, listable: oauth_application, name: user.login)

    assert_predicate listing, :valid?
    assert_empty listing.errors[:name]
  end

  test "allows slugs that match org login if OAuth app owned by same org" do
    org = create(:organization)
    oauth_application = create(:oauth_application, user: org)
    listing = build(:marketplace_listing, listable: oauth_application, name: org.login)

    assert_predicate listing, :valid?
    assert_empty listing.errors[:name]
  end

  test "allows slugs that match user login if GitHub app owned by same user" do
    user = create(:user)
    integration = create(:integration, owner: user)
    listing = build(:marketplace_listing, listable: integration, name: user.login)

    assert_predicate listing, :valid?
    assert_empty listing.errors[:name]
  end

  test "allows slugs that match org login if GitHub app owned by same org" do
    org = create(:organization)
    integration = create(:integration, owner: org)
    listing = build(:marketplace_listing, listable: integration, name: org.login)

    assert_predicate listing, :valid?
    assert_empty listing.errors[:name]
  end

  test "allows slugs that case-insensitive match org login" do
    org = create(:organization, login: "Mixed-Case")
    integration = create(:integration, owner: org, name: "Mixed-Case")
    listing = build(:marketplace_listing, listable: integration, name: org.login)

    assert_predicate listing, :valid?
    assert_empty listing.errors[:name]
    assert_equal "mixed-case", listing.slug
  end
end
