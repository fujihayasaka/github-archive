# typed: false
# frozen_string_literal: true

require "test_helper"

class SamlFilterTestController < ApplicationController

  def authorize_org_repos
    target = User.find_by(id: params[:target])
    resources = cap_filter.authorized_resource_ids(target.repositories)
    msg = { resources: resources }
    render json: msg
  end

  def authorized_orgs
    resources = cap_filter.authorized_resource_ids(current_user.organizations)
    msg = { resources: resources }
    render json: msg
  end

  def authorized_businesses
    resources = cap_filter.authorized_resource_ids(current_user.businesses)
    msg = { resources: resources }
    render json: msg
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def cap_filter
    f = super
    f.expects(:conditional_access_policies).returns([:saml]).at_least_once
    f
  end
end

class SamlFilterTest < GitHub::IntegrationTestCase
  include AuthenticationHelpers::SAML
  fixtures do
    @no_saml_user = create(:verified_user)
    @saml_user = create(:verified_user)
    @saml_org = create(:business_plus_org)
    @saml_identity = create(:external_identity, user: @saml_user, org: @saml_org)
    @saml_org.add_member @no_saml_user
    @saml_org.saml_provider.enforce!
    @saml_repo1 = create(:private_repository, :minimal, owner: @saml_org)
    @saml_repo2 = create(:private_repository, :minimal, owner: @saml_org)
    @saml_public_repo = create(:repository, :minimal, owner: @saml_org)

    membership = create(:business_organization_membership)
    @saml_org2 = membership.organization
    @saml_business = membership.business
    @saml_business_provider = create(:business_saml_provider, business: @saml_business)
  end

  setup do
    TestRoutes.draw do
      get "/authorize_org_repos/:target", to: "saml_filter_test#authorize_org_repos"
      get "/authorized_orgs", to: "saml_filter_test#authorized_orgs"
      get "/authorized_businesses", to: "saml_filter_test#authorized_businesses"
    end
  end

  test "authorized returns all resources for anon user" do
    # SAML doesn't apply to anon requests, it's up to a different part of the stack to check for visibility rules
    get "/authorize_org_repos/#{@saml_org.id}"
    authorized_resources = JSON.parse(response.body)["resources"]
    assert_same_elements [@saml_repo1.id, @saml_repo2.id, @saml_public_repo.id], authorized_resources
  end

  test "authorized returns all resources for non-org member" do
    # SAML doesn't apply to non-member requests, it's up to a different part of the stack to check for visibility rules
    as create(:verified_user)
    get "/authorize_org_repos/#{@saml_org.id}"
    authorized_resources = JSON.parse(response.body)["resources"]
    assert_same_elements [@saml_repo1.id, @saml_repo2.id, @saml_public_repo.id], authorized_resources
  end

  test "authorized returns public resources for user belonging to a different org without valid SAML session" do
    # SAML doesn't apply to non-member requests, it's up to a different part of the stack to check for visibility rules
    another_org = create(:organization)
    user = create(:verified_user)
    another_org.add_member(user)
    as user
    get "/authorize_org_repos/#{@saml_org.id}"
    authorized_resources = JSON.parse(response.body)["resources"]
    assert_same_elements [@saml_repo1.id, @saml_repo2.id, @saml_public_repo.id], authorized_resources
  end

  test "authorized returns all resources for member with valid SAML session" do
    as @saml_user, external_identities: @saml_identity
    get "/authorize_org_repos/#{@saml_org.id}"
    authorized_resources = JSON.parse(response.body)["resources"]
    assert_same_elements [@saml_repo1.id, @saml_repo2.id, @saml_public_repo.id], authorized_resources
  end

  test "authorized returns no resources for member without valid SAML session" do
    as @no_saml_user
    get "/authorize_org_repos/#{@saml_org.id}"
    authorized_resources = JSON.parse(response.body)["resources"]
    assert_empty authorized_resources
  end

  context "business" do
    test "authorized returns all resources for a member with a valid session" do
      business_saml_user = create(:verified_user)
      saml_identity = create :external_identity, provider: @saml_business_provider, user: business_saml_user
      @saml_org2.add_member(business_saml_user)

      as business_saml_user, external_identities: saml_identity
      get "/authorized_businesses"
      authorized_resources = JSON.parse(response.body)["resources"]
      assert_same_elements [@saml_business.id], authorized_resources
    end

    test "authorized returns no resources for member without a valid SAML session" do
      business_saml_user = create(:verified_user)
      saml_identity = create :external_identity, provider: @saml_business_provider, user: business_saml_user
      @saml_org2.add_member(business_saml_user)

      as business_saml_user
      get "/authorized_businesses"
      authorized_resources = JSON.parse(response.body)["resources"]
      assert_empty authorized_resources
    end

    test "authorized does not return orgs if the user does not have an external identity with the business" do
      business_saml_user = create(:verified_user)
      saml_identity = create :external_identity, provider: @saml_business_provider, user: business_saml_user
      @saml_org2.add_member(business_saml_user)
      # simulate user not having just yet SSOed
      saml_identity.delete

      as business_saml_user
      get "/authorized_orgs"
      authorized_resources = JSON.parse(response.body)["resources"]
      refute_includes authorized_resources, @saml_org2.id
    end
  end unless GitHub.single_business_environment?
end
