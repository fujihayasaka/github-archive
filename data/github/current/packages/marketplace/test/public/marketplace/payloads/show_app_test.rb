# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Payloads::ShowAppTest < GitHub::TestCase
  fixtures do
    @category1 = create(:marketplace_category)
    @category2 = create(:marketplace_category)
    @listing = create(:marketplace_listing,
                      categories: [@category1, @category2],
                      company_url: "https://www.company.url",
                      documentation_url: "https://www.documentation.url",
                      finance_email: "finance@email.com",
                      how_it_works: "This is how it works",
                      learn_more_url: "https://www.learn_more.url",
                      marketing_email: "marketing@email.com",
                      pricing_url: "https://www.pricing.url",
                      privacy_policy_url: "https://www.privacy_policy.url",
                      secondary_category_id: @category2.id,
                      security_email: "security@email.com",
                      status_url: "https://www.status.url",
                      support_url: "https://www.support.url",
                      technical_email: "technical@email.com",
                      tos_url: "https://www.tos.url")
    @listing_image = create(:marketplace_listing_image, listing: @listing)
    @user = create(:user)
    @screenshot = create(:marketplace_listing_screenshot, listing: @listing, caption: "caption")
    @customer = create(:organization)
    Marketplace::ListingFeaturedOrganization.create!(listing: @listing, organization: @customer, approved: true)
  end

  setup do
    @listing.hero_card_background_image = @listing_image
    @listing.save
  end

  context "#call" do
    test "correctly serializes the top-level listing data" do
      Platform::Helpers::MarketplaceListingContent.expects(:html_for)
        .with(@listing, :extended_description, { current_user: @user })
        .returns("extended description")
      Platform::Helpers::MarketplaceListingContent.expects(:html_for)
        .with(@listing, :full_description, { current_user: @user })
        .returns("full description")

      listing_data = Marketplace::Payloads::ShowApp.new(marketplace_listing: @listing, current_user: @user).call[:listing]

      assert_equal @listing.bgcolor, listing_data[:bgColor]
      assert_equal @listing.copilot_app, listing_data[:copilotApp]
      assert_equal @listing.documentation_url, listing_data[:documentationUrl]
      assert_equal "extended description", listing_data[:extendedDescription]
      assert_equal "full description", listing_data[:fullDescription]
      assert_equal @listing.id, listing_data[:id]
      assert_equal @listing.cached_installation_count, listing_data[:installationCount]
      assert_equal @listing.verified_owner?, listing_data[:isVerifiedOwner]
      assert_equal @listing.logo_url, listing_data[:listingLogoUrl]
      assert_equal @listing.name, listing_data[:name]
      assert_equal @listing.owner&.display_login, listing_data[:ownerLogin]
      assert_equal @listing.pricing_url, listing_data[:pricingUrl]
      assert_equal @category1.name, listing_data[:primaryCategory]
      assert_equal @listing.privacy_policy_url, listing_data[:privacyPolicyUrl]
      assert_equal @category2.name, listing_data[:secondaryCategory]
      assert_equal @listing.short_description, listing_data[:shortDescription]
      assert_equal @listing.slug, listing_data[:slug]
      assert_equal @listing.status_url, listing_data[:statusUrl]
      assert_equal @listing.support_url, listing_data[:supportUrl]
      assert_equal @listing.tos_url, listing_data[:tosUrl]
      assert_equal Marketplace::Types::ListingTypes::MarketplaceListing.serialize, listing_data[:type]
    end

    test "correctly serializes the screenshots" do
      screenshot_data = Marketplace::Payloads::ShowApp.new(marketplace_listing: @listing, current_user: @user).call.dig(:screenshots)

      assert_equal @screenshot.id, screenshot_data.first[:id]
      assert_equal @screenshot.storage_external_url(@user), screenshot_data.first[:src]
      assert_equal @screenshot.caption, screenshot_data.first[:caption]
      assert_equal @screenshot.alt_text, screenshot_data.first[:alt_text]
    end

    test "correctly serializes the featured customers" do
      customer_data = Marketplace::Payloads::ShowApp.new(marketplace_listing: @listing, current_user: @user).call.dig(:customers)

      assert_equal @customer.display_login, customer_data.first[:displayLogin]
    end
  end
end unless GitHub.enterprise?
