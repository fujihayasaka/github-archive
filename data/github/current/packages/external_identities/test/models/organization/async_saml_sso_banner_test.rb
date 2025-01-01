# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationAsyncSamlSsoBannerTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @admin = create(:user)
    @org.add_admin(@admin)
    @user = create(:user)
    @org.add_member(@user)

    @saml_provider = create(:organization_saml_provider)
    @saml_org = @saml_provider.organization
    @saml_admin = create(:user)
    @saml_org.add_admin(@saml_admin)

    @saml_sso_banner = User::NoticesDependency::ORGANIZATION_NOTICES[:saml_sso_banner]
  end

  test "it returns saml_sso_banner" do
    assert_equal(@saml_org.async_saml_sso_banner(viewer: @saml_admin).sync, @saml_sso_banner)
  end

  test "it does not return saml_sso_banner if saml is not enabled" do
    refute_equal(@org.async_saml_sso_banner(viewer: @user).sync, @saml_sso_banner)
  end

  test "it does not return saml_sso_banner if user is not a member" do
    non_member = create(:user)
    refute_equal(@saml_org.async_saml_sso_banner(viewer: non_member).sync, @saml_sso_banner)
  end

  test "it does not return saml_sso_banner if ExternalIdentity is linked" do
    billing_manager = create :user
    create :external_identity, provider: @saml_provider, user: billing_manager
    @saml_org.billing.add_manager(billing_manager, actor: @saml_admin)
    @saml_org.add_member(billing_manager)

    assert ExternalIdentity.linked? \
      provider: @saml_provider,
      user: billing_manager

    refute_equal(@saml_org.async_saml_sso_banner(viewer: billing_manager).sync, @saml_sso_banner)
  end

  test "it does not return saml_sso_banner if banner was already dismissed" do
    viewer = @saml_admin
    viewer.stubs(:dismissed_organization_notice?).returns(true)
    refute_equal(@saml_org.async_saml_sso_banner(viewer: viewer).sync, @saml_sso_banner)
  end

  test "shows org SAML SSO notice to new organization member" do
    owner = create(:user)
    saml_org = create(:business_plus_org, login: "saml-org", admin: owner)
    saml_provider = create(:organization_saml_provider, organization: saml_org)

    unlinked = create(:user, login: "direct-member")
    linked = create(:user, login: "another-direct-member")
    saml_org.add_member(unlinked)
    saml_org.add_member(linked)
    saml_org.reload
    create(:external_identity, provider: saml_org.external_identity_session_owner.saml_provider, user: linked)

    results = saml_org.async_notices_for(viewer: nil).sync
    refute_includes results, @saml_sso_banner

    results = saml_org.async_notices_for(viewer: linked).sync
    refute_includes results, @saml_sso_banner

    results = saml_org.async_notices_for(viewer: unlinked).sync
    assert_includes results, @saml_sso_banner
  end

  test "hides org SAML SSO notice if the org belongs to a business with SAML configured" do
    saml_business = create(:business_saml_provider).business
    saml_org = create(:business_plus_org, login: "saml-org")
    saml_business.add_organization(saml_org)

    unlinked = create(:user, login: "direct-member")
    linked = create(:user, login: "another-direct-member")
    saml_org.add_member(unlinked)
    saml_org.add_member(linked)
    saml_org.reload
    create(:external_identity, provider: saml_org.external_identity_session_owner.saml_provider, user: linked)

    results = saml_org.async_notices_for(viewer: nil).sync
    refute_includes results, @saml_sso_banner

    results = saml_org.async_notices_for(viewer: linked).sync
    refute_includes results, @saml_sso_banner

    results = saml_org.async_notices_for(viewer: unlinked).sync
    refute_includes results, @saml_sso_banner
  end
end
