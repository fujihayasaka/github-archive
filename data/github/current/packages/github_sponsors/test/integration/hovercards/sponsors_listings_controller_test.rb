# typed: true
# frozen_string_literal: true

require "test_helper"

class HovercardsSponsorsListingsControllerHttpTest < GitHub::IntegrationTestCase
  fixtures do
    @viewer = create(:user)
    @sponsorable = create(:user, :sponsorable)

    setup_staff_user
  end

  if GitHub.sponsors_enabled?
    test "loads successfully" do
      as @viewer
      get "/sponsors/#{@sponsorable}/hovercard", xhr: true

      assert_response :ok
      assert_select "[data-test-selector=sponsors-listing-hovercard]", text: /#{@sponsorable.sponsors_listing.short_description}/
      refute_select "[data-test-selector=sponsors-goals-progress-bar]"
    end

    test "falls back to full description when short description is blank" do
      full_description = "full description"
      sponsors_listing = create(:sponsors_listing,
        :approved,
        short_description: " ",
        full_description: full_description
      )

      as @viewer
      get "/sponsors/#{sponsors_listing.sponsorable}/hovercard", xhr: true

      assert_response :ok
      assert_select "[data-test-selector=sponsors-listing-hovercard]", text: /#{full_description}/
    end

    test "includes progress toward active goal when one exists" do
      create(:sponsors_goal, :active, listing: @sponsorable.sponsors_listing)

      as @viewer
      get "/sponsors/#{@sponsorable}/hovercard", xhr: true

      assert_response :ok
      assert_select "[data-test-selector=sponsors-goals-progress-bar]"
    end

    test "404s for a non-sponsorable user" do
      as @viewer
      get "/sponsors/#{create(:user)}/hovercard", xhr: true

      assert_response :not_found
    end
  end
end

if GitHub.external_identity_session_enforcement_enabled? && GitHub.sponsors_enabled?
  class HovercardsSponsorsListingsControllerActiveExternalIdentitySessionEnforcementHttpTest < GitHub::IntegrationTestCase
    include AuthenticationHelpers::SAML

    fixtures do
      @saml_admin = create(:verified_user)
      create(:sponsors_listing, :approved, sponsorable: @saml_admin)

      @saml_org = create(:business_plus_org, admin: @saml_admin)
      create(:sponsors_listing, :approved, sponsorable: @saml_org)
      provider = create(:organization_saml_provider, :enforced, organization: @saml_org)
      @saml_identity = create(:external_identity, provider: provider, user: @saml_admin)

      @non_saml_org = create(:organization)
      create(:sponsors_listing, :approved, sponsorable: @non_saml_org)
      @non_saml_admin = @non_saml_org.admin

      setup_staff_user
    end

    context "GET :show" do
      test "without valid session, requires SAML session" do
        as @saml_admin
        get "/sponsors/#{@saml_org.display_login}/hovercard", xhr: true
        assert_saml_sso_required
      end

      test "with valid session, does not require SAML session" do
        as @saml_admin, external_identities: @saml_identity
        get "/sponsors/#{@saml_org.display_login}/hovercard", xhr: true
        refute_saml_sso_required
      end

      test "does not require SAML session if listing is owned by non-SAML org" do
        as @non_saml_admin
        get "/sponsors/#{@saml_org.display_login}/hovercard", xhr: true
        refute_saml_sso_required
      end

      test "does not require SAML session if listing is owned by individual user" do
        as @saml_admin
        get "/sponsors/#{@saml_admin}/hovercard", xhr: true
        refute_saml_sso_required
      end
    end
  end
end
