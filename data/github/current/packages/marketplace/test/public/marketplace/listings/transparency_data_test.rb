# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Listings::TransparencyDataTest < GitHub::TestCase
  fixtures do
    @organization = create(:organization)
    @user = create(:user)
    @integration = create(:integration, owner: @organization)
    @copilot_app = create(:marketplace_listing, :copilot, llms_in_use: "some llms", ai_risk_level: :high)
    @listing = create(
      :marketplace_listing,
      listable: @integration,
      transparency_disclosure: "disclosure in markdown",
      llms_in_use: "some llms",
      support_url: nil,
      trader_self_certification: nil,
      repository_visibility: :public,
      repository_url: "https://www.example.com",
      ai_risk_level: :high,
      trader_id: "1234",
      trader_id_type: "custom"
    )
  end

  def transparency_data(listing = @listing)
    Marketplace::Listings::TransparencyData.new(listing: listing)
  end

  context "#publisher_2fa_required" do
    context "when the listing owner is a user" do
      test "returns Not applicable text" do
        @integration.update!(owner: @user)

        assert_equal "Not applicable - Individual publisher", transparency_data.publisher_2fa_required
      end
    end

    context "when the listing owner is an organization" do
      context "when the organization has 2FA requirement enabled" do
        test "returns Yes text" do
          org_with_2fa = create(:two_factor_credential_org)
          @integration.update!(owner: org_with_2fa)

          assert_equal "Yes - Publisher organization requires 2FA", transparency_data.publisher_2fa_required
        end
      end

      context "when the organization does not have 2FA requirement enabled" do
        test "returns No text" do
          assert_equal "No - Publisher organization does not require 2FA", transparency_data.publisher_2fa_required
        end
      end
    end

    context "when the listing owner is a neither an organization nor user" do
      test "returns nil" do
        business = create(:business)
        @integration.update!(owner: business, visibility: "internal_visibility")

        assert_nil transparency_data.publisher_2fa_required
      end
    end
  end

  context "#verified_profile_domains" do
    context "when the listing owner is an organization" do
      test "returns an array of the verified profile domains" do
        @organization.update!(profile_blog: "www.example.com")
        org_website = create(:verifiable_domain, owner: @organization, verified: true, domain: "www.example.com")

        assert_equal ["www.example.com"], transparency_data.verified_profile_domains
      end
    end

    context "when the listing owner is a not an organization" do
      test "returns an empty array" do
        @integration.update!(owner: @user)

        assert_equal [], transparency_data.verified_profile_domains
      end
    end
  end

  context "#repository_visibility" do
    test "returns listing's repository_visibility if it is not unspecified" do
      assert_equal "public", transparency_data.repository_visibility
    end

    test "returns nil if listing's repository_visibility is unspecified" do
      @listing.update!(repository_visibility: :unspecified)

      assert_nil transparency_data.repository_visibility
    end
  end

  context "#repository_url" do
    test "returns listing's repository_url if listing's repository_visibility is public" do
      assert_equal "https://www.example.com", transparency_data.repository_url
    end

    test "returns nil if listing's repository_visibility is not public" do
      @listing.update!(repository_visibility: :unspecified)

      assert_nil transparency_data.repository_url
    end
  end

  context "#transparency_disclosure" do
    test "returns the listing's converted transparency_disclosure" do
      GitHub::Goomba::MarkdownPipeline.stubs(:to_html).with("disclosure in markdown").returns("disclosure in html")

      assert_equal "disclosure in html", transparency_data.transparency_disclosure
    end
  end

  context "#llms_in_use" do
    test "returns llms_in_use if listing is a copilot app" do
      assert_equal "some llms", transparency_data(@copilot_app).llms_in_use
    end

    test "returns nil if listing is not a copilot app" do
      assert_nil transparency_data.llms_in_use
    end
  end

  context "#is_ai_high_risk" do
    test "returns Yes if listing is a copilot app and ai_risk_level is high" do
      assert_equal "Yes", transparency_data(@copilot_app).is_ai_high_risk
    end

    test "returns No if listing is a copilot app and ai_risk_level is not high" do
      @copilot_app.update!(ai_risk_level: :not_high)

      assert_equal "No", transparency_data(@copilot_app).is_ai_high_risk
    end

    test("returns nil if listing is a copilot app and ai_risk_level is not specified") do
      @copilot_app.update!(ai_risk_level: :unspecified)

      assert_nil transparency_data(@copilot_app).is_ai_high_risk
    end

    test("returns nil if listing is not a copilot app") do
      assert_nil transparency_data.is_ai_high_risk
    end
  end

  context "#support_url" do
    test "returns nil if the listing's support_url is an email" do
      @listing.update!(support_url: "support@github.com")

      assert_nil transparency_data.support_url
    end

    test "returns the listing's support_url if the listing's support_url is a url" do
      @listing.update!(support_url: "https://www.support.com")

      assert_equal "https://www.support.com", transparency_data.support_url
    end

    test "returns nil if the listing's support_url is nil" do
      assert_nil transparency_data.support_url
    end
  end

  context "#support_email" do
    test "returns nil if the listing's support_url is a url" do
      @listing.update!(support_url: "https://www.support.com")

      assert_nil transparency_data.support_email
    end

    context "when the listing's support_url is an email" do
      test "returns the support email" do
        @listing.update!(support_url: "support@github.com")

        assert_equal "support@github.com", transparency_data.support_email
      end

      test "strips mailto: from the support email when present at the beginning of the email" do
        @listing.update!(support_url: "mailto:support@github.com")

        assert_equal "support@github.com", transparency_data.support_email
      end

      test "does not modify the support email when mailto: is only partially present" do
        @listing.update!(support_url: "mailtosupport@github.com")

        assert_equal "mailtosupport@github.com", transparency_data.support_email
      end

      test "does not modify the support email when mailto: is not present at the beginning of the email" do
        @listing.update!(support_url: "supportmailto:@github.com")

        assert_equal "supportmailto:@github.com", transparency_data.support_email
      end
    end

    test "returns nil if the listing's support_url is nil" do
      assert_nil transparency_data.support_email
    end
  end

  context "#business_id" do
    context "when the listing's trader_id_type is one of the default types" do
      test "returns the reformatted trader_id_type with the trader_id" do
        type = Marketplace::Listings::SecurityAndCompliance::STANDARD_BUSINESS_ID_TYPES.first
        @listing.update!(trader_id_type: type)

        assert_equal "#{type&.upcase} #: 1234", transparency_data.business_id
      end
    end

    context "when the listing's trader_id_type is not one of the default types" do
      test "returns the trader_id_type with the trader_id" do
        assert_equal "custom: 1234", transparency_data.business_id
      end
    end

    test "returns nil when the listing's trader_id_type is nil" do
      @listing.update!(trader_id_type: nil)

      assert_nil transparency_data.business_id
    end

    test "returns nil when the listing's trader_id is nil" do
      @listing.update!(trader_id: nil)

      assert_nil transparency_data.business_id
    end
  end

  context "#owner_safe_profile_name" do
    test "returns the listing owner's safe_profile_name" do
      assert_equal @listing.owner.safe_profile_name, transparency_data.owner_safe_profile_name
    end
  end

  context "#eu_trader" do
    test "returns Yes text when the listing's trader_self_certification is trader" do
      @listing.update!(trader_self_certification: :trader)

      assert_equal "Yes - Classifies as a trader in the European Union", transparency_data.eu_trader
    end

    test "returns No text when the listing's trader_self_certification is not trader" do
      @listing.update!(trader_self_certification: :non_trader)

      assert_equal "No - Does not classify as a trader in the European Union", transparency_data.eu_trader
    end

    test "returns nil when the listing's trader_self_certification is nil" do
      assert_nil transparency_data.eu_trader
    end
  end

  context "#repository_url, #support_url, #privacy_policy_url, #tos_url, #status_url" do
    test "does not return blank urls" do
      @listing.update!(
        privacy_policy_url: "",
        repository_url: "",
        status_url: "",
        support_url: "",
        tos_url: ""
      )

      assert_nil transparency_data.repository_url
      assert_nil transparency_data.support_url
      assert_nil transparency_data.privacy_policy_url
      assert_nil transparency_data.tos_url
      assert_nil transparency_data.status_url
    end

    test "does not return invalid urls" do
      @listing.update!(
        privacy_policy_url: "https://javascript:alert(1)",
        repository_url: "https://data:text/html;base64,PHNjcmlw",
        status_url: "https://#\"></a><script>alert(1)</script><a href=\"#\"",
        support_url: "https://{}bad.example.com",
        tos_url: "https:// ;alert(1)"
      )

      assert_nil transparency_data.repository_url
      assert_nil transparency_data.support_url
      assert_nil transparency_data.privacy_policy_url
      assert_nil transparency_data.tos_url
      assert_nil transparency_data.status_url
    end

    test "returns valid urls" do
      @listing.update!(
        privacy_policy_url: "https://www.example.com",
        repository_url: "https://www.example.com/pricing",
        status_url: "https://www.example.com?q=privacy",
        support_url: "https://example.com:8080",
        tos_url: "https://www.example+status.com"
      )

      assert_equal "https://www.example.com/pricing", transparency_data.repository_url
      assert_equal "https://example.com:8080", transparency_data.support_url
      assert_equal "https://www.example.com", transparency_data.privacy_policy_url
      assert_equal "https://www.example+status.com", transparency_data.tos_url
      assert_equal "https://www.example.com?q=privacy", transparency_data.status_url
    end
  end
end
