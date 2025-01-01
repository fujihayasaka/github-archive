# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Payloads::ShowAppTest < GitHub::TestCase
  fixtures do
    @category1 = create(:marketplace_category)
    @category2 = create(:marketplace_category)
    @owner = create(:organization)
    @listable = create(:oauth_application, user: @owner)
    @listing = create(:marketplace_listing,
                      listable: @listable,
                      categories: [@category1, @category2],
                      finance_email: "finance@email.com",
                      how_it_works: "This is how it works",
                      marketing_email: "marketing@email.com",
                      secondary_category_id: @category2.id,
                      security_email: "security@email.com",
                      technical_email: "technical@email.com")
    @listing_image = create(:marketplace_listing_image, listing: @listing)
    @user = create(:user)
    @screenshot = create(:marketplace_listing_screenshot, listing: @listing, caption: "caption")
    @customer = create(:organization)
    Marketplace::ListingFeaturedOrganization.create!(listing: @listing, organization: @customer, approved: true)
    @permissions_data = [{ scope: "repository", permissionLevel: "read", values: ["code"] }]
  end

  setup do
    @listing.hero_card_background_image = @listing_image
    @listing.save
    Marketplace::Serializers::PermissionsData.any_instance.stubs(:call).returns(@permissions_data)
    Marketplace::Listings::TransparencyData.any_instance.stubs(
      publisher_2fa_required: "Yes",
      verified_profile_domains: ["github.com"],
      repository_visibility: "Public",
      repository_url: "https://github.com",
      transparency_disclosure: "This is a disclosure",
      llms_in_use: "Some LLMS",
      is_ai_high_risk: "Yes",
      support_url: "https://support.com",
      support_email: "support@github.com",
      privacy_policy_url: "https://privacy.com",
      tos_url: "https://tos.com",
      business_id: "ID: 1234",
      owner_safe_profile_name: "owner",
      status_url: "https://status.com",
      eu_trader: "Yes"
    )
  end

  context "#call" do
    context "listing" do
      test "correctly serializes the top-level listing data" do
        Platform::Helpers::MarketplaceListingContent.expects(:html_for)
          .with(@listing, :extended_description, { current_user: @user })
          .returns("extended description")
        Platform::Helpers::MarketplaceListingContent.expects(:html_for)
          .with(@listing, :full_description, { current_user: @user })
          .returns("full description")

        listing_data = Marketplace::Payloads::ShowApp.new(marketplace_listing: @listing, current_user: @user).call[:listing]

        assert_equal @listing.bgcolor, listing_data[:bgColor]
        assert_equal "ID: 1234", listing_data[:businessId]
        assert_equal @listing.copilot_app, listing_data[:copilotApp]
        assert_equal "Yes", listing_data[:euTrader]
        assert_equal "extended description", listing_data[:extendedDescription]
        assert_equal "full description", listing_data[:fullDescription]
        assert_equal @listing.id, listing_data[:id]
        assert_equal @listing.cached_installation_count, listing_data[:installationCount]
        assert_equal "Yes", listing_data[:isAiHighRisk]
        assert_equal @listing.verified_owner?, listing_data[:isVerifiedOwner]
        assert_equal @listing.logo_url, listing_data[:listingLogoUrl]
        assert_equal "Some LLMS", listing_data[:llmsInUse]
        assert_equal @listing.name, listing_data[:name]
        assert_equal @listing.owner&.primary_avatar_url(48), listing_data[:ownerImage]
        assert_equal @listing.owner&.display_login, listing_data[:ownerLogin]
        assert_equal "owner", listing_data[:ownerSafeProfileName]
        assert_equal @listing.owner&.class&.name, listing_data[:ownerType]
        assert_equal "https://privacy.com", listing_data[:privacyPolicyUrl]
        assert_equal "Yes", listing_data[:publisher2faRequired]
        assert_equal "Public", listing_data[:repositoryVisibility]
        assert_equal "https://github.com", listing_data[:repositoryUrl]
        assert_equal @listing.short_description, listing_data[:shortDescription]
        assert_equal @listing.slug, listing_data[:slug]
        assert_equal "https://status.com", listing_data[:statusUrl]
        assert_equal "support@github.com", listing_data[:supportEmail]
        assert_equal "https://support.com", listing_data[:supportUrl]
        assert_equal @listing.third_party_services, listing_data[:thirdPartyServices]
        assert_equal "https://tos.com", listing_data[:tosUrl]
        assert_equal @listing.trader_address, listing_data[:traderAddress]
        assert_equal "This is a disclosure", listing_data[:transparencyDisclosure]
        assert_equal Marketplace::Types::ListingTypes::MarketplaceListing.serialize, listing_data[:type]
        assert_equal ["github.com"], listing_data[:verifiedProfileDomains]
      end

      context "documentationUrl, pricingUrl" do
        test "does not return blank urls" do
          @listing.update!(
            documentation_url: "",
            pricing_url: ""
          )
          listing_data = Marketplace::Payloads::ShowApp.new(marketplace_listing: @listing, current_user: @user).call[:listing]

          assert_nil listing_data[:documentationUrl]
          assert_nil listing_data[:pricingUrl]
        end

        test "does not return invalid urls" do
          @listing.update!(
            documentation_url: "https://www.example.com<script>alert(\"xss\")</script>",
            pricing_url: "https:// .example.com"
          )
          listing_data = Marketplace::Payloads::ShowApp.new(marketplace_listing: @listing, current_user: @user).call[:listing]

          assert_nil listing_data[:documentationUrl]
          assert_nil listing_data[:pricingUrl]
        end

        test "returns valid urls" do
          @listing.update!(
            documentation_url: "http://www.example.com",
            pricing_url: "https://www.example.com#pricing"
          )
          listing_data = Marketplace::Payloads::ShowApp.new(marketplace_listing: @listing, current_user: @user).call[:listing]

          assert_equal "http://www.example.com", listing_data[:documentationUrl]
          assert_equal "https://www.example.com#pricing", listing_data[:pricingUrl]
        end
      end
    end

    test "correctly serializes the listing categories" do
      category_data = Marketplace::Payloads::ShowApp.new(marketplace_listing: @listing, current_user: @user).call[:listing][:categories]

      assert_equal [
        { name: @category1.name, slug: @category1.slug },
        { name: @category2.name, slug: @category2.slug }
      ], category_data
    end

    test "correctly serializes the screenshots" do
      screenshot_data = Marketplace::Payloads::ShowApp.new(marketplace_listing: @listing, current_user: @user).call.dig(:screenshots)

      assert_equal @screenshot.id, screenshot_data.first[:id]
      assert_equal @screenshot.storage_external_url(@user), screenshot_data.first[:src]
      assert_equal @screenshot.caption, screenshot_data.first[:caption]
      assert_equal @screenshot.alt_text, screenshot_data.first[:altText]
    end

    test "correctly serializes the featured customers" do
      customer_data = Marketplace::Payloads::ShowApp.new(marketplace_listing: @listing, current_user: @user).call.dig(:customers)

      assert_equal @customer.display_login, customer_data.first[:displayLogin]
    end

    context "permissionsData" do
      context "when the listing listable is an integation" do
        test "returns the serialized permissions data" do
          listing = create(:marketplace_listing, :integration)
          permissions_data = Marketplace::Payloads::ShowApp.new(
            marketplace_listing: listing,
            current_user: @user
          ).call.dig(:permissionsData)

          assert_equal @permissions_data, permissions_data
        end
      end

      context "when the listing listable is not an integration" do
        test "returns an empty array" do
          permissions_data = Marketplace::Payloads::ShowApp.new(
            marketplace_listing: @listing,
            current_user: @user
          ).call.dig(:permissionsData)

          assert_equal [], permissions_data
        end
      end
    end
  end
end unless GitHub.enterprise?
