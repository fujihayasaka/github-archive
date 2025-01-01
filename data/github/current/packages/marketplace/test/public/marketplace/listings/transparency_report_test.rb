# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Listings::TransparencyReportTest < GitHub::TestCase
  fixtures do
    @listable = create(:integration,
      default_permissions: {
        "metadata" => :read
      }
    )
    @listing = create(:marketplace_listing,
      listable: @listable,
      name: "Test App",
      third_party_services: "Some third-party services",
      trader_address: "1234 Main St",
      transparency_disclosure: "This is a disclosure",
      copilot_app: true
    )
  end

  setup do
    Marketplace::Listings::TransparencyData.any_instance.stubs(
      publisher_2fa_required: "Yes",
      verified_profile_domains: ["github.com", "www.github.com"],
      repository_visibility: "Public",
      repository_url: "https://github.com",
      llms_in_use: "Some LLMS",
      is_ai_high_risk: "Yes",
      support_url: "https://support.com",
      support_email: "support@github.com",
      privacy_policy_url: "https://privacy.com",
      tos_url: "https://tos.com",
      business_id: "ID: 1234",
      owner_safe_profile_name: "Test Developer",
      status_url: "https://status.com",
      eu_trader: "Yes",
      indemnity_status: "Not covered"
    )
  end

  context "#as_csv" do
    test "returns the right headers and data" do
      report = Marketplace::Listings::TransparencyReport.new(listing: @listing)

      assert_equal report.as_csv.split("\n"), [
        "Field,Value",
        "App Name,Test App",
        "Listing Type,Copilot Extension",
        "Developer,Test Developer",
        "Publisher 2FA Required,Yes",
        "Company Domain,\"github.com, www.github.com\"",
        "Business Address or PO Box,1234 Main St",
        "EU Trader,Yes",
        "Required Permissions,read:metadata",
        "Repository Visibility,Public",
        "Repository URL,https://github.com",
        "Third-party Services,Some third-party services",
        "AI Models Used,Some LLMS",
        "High-risk AI Model,Yes",
        "Indemnity Status,Not covered",
        "Support Email,support@github.com",
        "Support URL,https://support.com",
        "Privacy Policy URL,https://privacy.com",
        "Terms of Service URL,https://tos.com",
        "Status page,https://status.com",
        "Business ID,ID: 1234",
        "Transparency Disclosures,This is a disclosure"
      ]
    end

    test "excludes rows that don't have values" do
      Marketplace::Listings::TransparencyData.any_instance.stubs(
        publisher_2fa_required: nil,
        verified_profile_domains: [],
        repository_visibility: nil,
        repository_url: nil,
        llms_in_use: nil,
        is_ai_high_risk: nil,
        support_url: nil,
        support_email: nil,
        privacy_policy_url: nil,
        tos_url: nil,
        business_id: nil,
        owner_safe_profile_name: nil,
        status_url: nil,
        eu_trader: nil,
        indemnity_status: nil
      )
      @listable.update!(default_permissions: {})
      @listing.update!(third_party_services: nil, trader_address: nil, transparency_disclosure: nil)
      report = Marketplace::Listings::TransparencyReport.new(listing: @listing)

      assert_equal report.as_csv.split("\n"), [
        "Field,Value",
        "App Name,Test App",
        "Listing Type,Copilot Extension"
      ]
    end

    context "listing type" do
      test "returns 'App' for a non-copilot listing" do
        @listing.update!(copilot_app: false)
        report = Marketplace::Listings::TransparencyReport.new(listing: @listing)

        assert_includes report.as_csv.split("\n"), "Listing Type,App"
      end

      test "returns 'Copilot Extension' for a copilot listing" do
        report = Marketplace::Listings::TransparencyReport.new(listing: @listing)

        assert_includes report.as_csv.split("\n"), "Listing Type,Copilot Extension"
      end
    end

    context "required permissions" do
      test "excludes row if listing listable is not an integration" do
        listable = create(:oauth_application)
        listing = create(:marketplace_listing, listable: listable)
        report = Marketplace::Listings::TransparencyReport.new(listing: listing)

        assert report.as_csv.split("\n").none? { |str| str.include?("Required Permissions") }
      end

      test "only includes permissions for Repository, Organization, or User and uses snakecased human names" do
        listable = create(:integration,
          default_permissions: {
            "emails" => :read,
            "enterprise_administration" => :read, # excluded for being a business permission
            "pull_requests" => :write,
            "organization_projects" => :admin,
            "single_file" => :read,
            "repository_projects" => :admin,
            "contents" => :write,
            "organization_api_insights" => :read,
          }, single_file_name: "test.txt")
        listing = create(:marketplace_listing, listable: listable)
        report = Marketplace::Listings::TransparencyReport.new(listing: listing)

        assert_includes report.as_csv.split("\n"), "Required Permissions,write:pull_requests; read:single_file; " \
          "admin:repository_projects; write:code; read:metadata; admin:organization_projects; " \
          "read:organization_api_insights; read:email_addresses"
      end
    end
  end
end
