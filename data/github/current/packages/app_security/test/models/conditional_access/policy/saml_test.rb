# typed: true
# frozen_string_literal: true

require "test_helper"


class ConditionalAccess::TestSamlEnforcer < ConditionalAccess::Enforcer
  include ::ConditionalAccess::Policy::SAML

  def conditional_access_policies
    [:saml]
  end
  alias :registered_policies :conditional_access_policies

  def location
    :test
  end

  def actor
    callback.send(:actor)
  end

  def anonymous?
    callback.send(:anonymous?)
  end

  def web_session
    nil
  end
end

class ConditionalAccess::TestSamlAuthzdEnforcer < ::ConditionalAccess::AuthzdEnforcer
  include ::ConditionalAccess::Policy::SAML

  def conditional_access_policies
    [:saml]
  end
  alias :registered_policies :conditional_access_policies

  def location
    :test
  end

  def authzd_cap_actor
    callback.send(:actor)
  end

  def authzd_cap_request_attributes
    callback.send(:authzd_request_attributes)
  end
end

class SAMLMockCallback
  attr_reader :actor

  def initialize(actor: nil, anonymous: true, websession: nil, visibility: "private")
    @actor = actor
    @anonymous = anonymous
    @websession = websession
    @visibility = visibility
  end

  def anonymous?
    @anonymous
  end

  def session_id
    return 0 if @websession.nil?
    @websession.id
  end

  def authzd_request_attributes
    attrs = {}
    attrs["conditional.access.anonymous"] = anonymous?
    if session_id > 0
      attrs["conditional.access.web_session_id"] = session_id
    end

    attrs["conditional.access.resource.visibility"] = @visibility

    attrs
  end
end

class SamlPolicyEnforcementTest < GitHub::TestCase
  fixtures do
    @user = create :user
    @business_with_saml = create :business, name: "business-with-saml", owners: [create(:user)]
    business_saml_provider = create(:business_saml_provider, business: @business_with_saml)
    business_saml_provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")
    @user_external_identity = create(:external_identity, user: @user, provider: business_saml_provider)
  end

  def assert_result(callback, resource, expected_result)
    enforcer = ENV["TEST_CAP_VIA_AUTHZD"] == "1" ? ConditionalAccess::TestSamlAuthzdEnforcer.new(callback) : ConditionalAccess::TestSamlEnforcer.new(callback)

    results = enforcer.evaluate_conditional_access_policies resource
    assert_equal 1, results.size
    assert_equal :saml, results.keys.first
    assert_equal expected_result, results.values.first
  end

  def assert_satisfied(callback, resource)
    assert_result(callback, resource, :satisfied)
  end

  def assert_unsatisfied(callback, resource)
    assert_result(callback, resource, :unsatisfied)
  end

  def assert_inapplicable(callback, resource)
    assert_result(callback, resource, :inapplicable)
  end

  context "saml_satisfied" do
    test "returns satisfied for private and internal if user belongs to org", skip_enterprise: true do
      org1 = create :organization
      @business_with_saml.add_organization(org1)
      org1.add_member(@user)

      user_with_oauth_via_oauth_app = make_oauth(@user, %w(repo), create(:oauth_application))
      user = User.with_oauth_hashed_token(user_with_oauth_via_oauth_app.hashed_token)
      assert_predicate user, :using_auth_via_oauth_application?
      Organization::CredentialAuthorization.grant organization: org1, credential: user_with_oauth_via_oauth_app, actor: @user

      if ENV["TEST_CAP_VIA_AUTHZD"] == "1"
        callback = SAMLMockCallback.new(actor: user, anonymous: false)
        assert_satisfied(callback, org1)
        callback = SAMLMockCallback.new(actor: user, anonymous: false, visibility: "internal")
        assert_satisfied(callback, org1)
      else
        callback = SAMLMockCallback.new(actor: user, anonymous: false)
        assert_satisfied(callback, org1)
        assert_satisfied(callback, Platform::InternalResource.new(resource: org1))
      end
    end

    test "returns satisfied for internal and unsatisfied for private if user does not belong to org", skip_enterprise: true do
      enable_feature_flag(:saml_scope_private_resources_to_org, @business_with_saml)
      org2 = create :organization
      @business_with_saml.add_organization(org2)
      org3 = create :organization
      @business_with_saml.add_organization(org3)
      org3.add_member(@user)
      pat = make_personal_access_token(@user, scopes = %w(repo))
      Organization::CredentialAuthorization.grant(organization: org3, credential: pat, actor: @user)
      user = User.with_oauth_hashed_token(pat.hashed_token)


      if ENV["TEST_CAP_VIA_AUTHZD"] == "1"
        callback = SAMLMockCallback.new(actor: user, anonymous: false, visibility: "internal")
        assert_satisfied(callback, org2)
        callback = SAMLMockCallback.new(actor: user, anonymous: false)
        assert_unsatisfied(callback, org2)
      else
        callback = SAMLMockCallback.new(actor: user, anonymous: false)
        assert_satisfied(callback, Platform::InternalResource.new(resource: org2))
        assert_unsatisfied(callback, org2)
      end
    end

    test "enforced SAML business is satisfied" do
      session = create :user_session, user: @user
      create :external_identity_session, user_session: session, external_identity: @user_external_identity

      callback = SAMLMockCallback.new(actor: @user, anonymous: false, websession: session)
      @business_with_saml.add_owner(@user, actor: @user)
      assert_satisfied(callback, @business_with_saml)
    end
  end

  context "saml_applicable" do
    test "returns inapplicable for anonymous user" do
      org = create :organization
      @business_with_saml.add_organization(org)
      org.add_member(@user)
      pat = make_personal_access_token(@user, scopes = %w(repo))
      Organization::CredentialAuthorization.grant(organization: org, credential: pat, actor: @user)
      callback = SAMLMockCallback.new(actor: @user, anonymous: true)
      assert_inapplicable(callback, org)
    end

    test "returns inapplicable for orgs without SAML enabled" do
      business_without_saml = @business_with_saml
      business_without_saml.saml_provider&.destroy
      org = create :organization
      business_without_saml.add_organization(org)
      org.add_member(@user)
      pat = make_personal_access_token(@user, scopes = %w(repo))
      Organization::CredentialAuthorization.grant(organization: org, credential: pat, actor: @user)
      callback = SAMLMockCallback.new(actor: @user, anonymous: false)
      assert_inapplicable(callback, org)
    end

    test "user is inapplicable" do
      callback = SAMLMockCallback.new(actor: @user, anonymous: false)
      assert_inapplicable(callback, @user)
    end

    test "organization without SAML-business is not applicable" do
      org = create :organization
      callback = SAMLMockCallback.new(actor: @user, anonymous: false)
      assert_inapplicable(callback, org)
    end

    test "SAML enforced organization is applicable" do
      session = create :user_session, user: @user

      org = create :organization
      @business_with_saml.add_organization(org)
      org.add_member(@user)
      callback = SAMLMockCallback.new(actor: @user, anonymous: false, websession: session)
      assert_unsatisfied(callback, org)
    end

    test "non-enforced SAML business is inapplicable" do
      callback = SAMLMockCallback.new(actor: @user, anonymous: false)
      assert_inapplicable(callback, @business_with_saml)
    end

    test "inapplicable if target is :no_target_for_conditional_access" do
      callback = SAMLMockCallback.new(actor: @user, anonymous: false)
      assert_inapplicable(callback, :no_target_for_conditional_access)
    end
  end
end

class SamlPolicyFilterTest < GitHub::TestCase
  fixtures do
    @admin = create :user
    @user = create :user

    @org_enforced_saml = create :business_plus_org, admin: @admin
    provider = create :organization_saml_provider, organization: @org_enforced_saml
    provider.enforce!
    create :external_identity, user: @user, provider: provider
    @org_enforced_saml.add_member(@user)
  end

  setup do
    @filter = ConditionalAccess::Model::Filter::new(nil, actor: @user, location: :test)
  end

  context "multiple_saml_applicable" do
    test "User targets are not applicable" do
      inputs = [@admin, @user]
      assert_equal [], @filter.multiple_saml_applicable(inputs, @filter.target_provider)
    end

    test "SAML enforced organizations are applicable" do
      assert_equal [@org_enforced_saml], @filter.multiple_saml_applicable(@user.organizations, @filter.target_provider)
    end

    test "returns no organizations for anonymous user" do
      filter = ConditionalAccess::Model::Filter::new(nil, actor: nil, location: :test)
      results = filter.multiple_saml_applicable(Organization.all, filter.target_provider)
      assert_equal [], results
    end

    test "issues constant number of queries for Organizations" do
      skip "if test environment is already tracking queries, tracking queries will be off" if TestEnv.test_tracking_queries?
      disable_feature_flag(:cap_filter_consider_outside_collabs) # unfortunately feature results in necessary additional queries, delete test when rolling out
      user = create :user
      identities = create_list(:external_identity, 10, user: user)
      organizations = identities.map { |i| i.provider.organization }
      filter = ConditionalAccess::Model::Filter::new(nil, actor: user, location: :test)

      GitHub::MysqlInstrumenter.with_instrument_and_track do
        assert_equal organizations, filter.multiple_saml_applicable(organizations, filter.target_provider)
      end

      queries = GitHub::MysqlInstrumenter.queries
      # modify back when saml_enforcement_policy_experiment removed
      assert_equal TestEnv.test_all_features? ? 8 : 10, queries.count
    end

    unless GitHub.single_business_environment?
      test "issues constant number of queries for Businesses" do
        skip "if test environment is already tracking queries, tracking queries will be off" if TestEnv.test_tracking_queries?
        owner = create :user
        businesses = 10.times.map do |_|
          biz = create :business, owners: [owner]
          create :business_saml_provider, business: biz
          biz
        end

        GitHub::MysqlInstrumenter.with_instrument_and_track do
          assert_equal businesses, Business::SamlEnforcementPolicy.filter_enforced(businesses, owner)
        end

        queries = GitHub::MysqlInstrumenter.queries
        assert_equal 4, queries.count
      end

      test "Business is applicable if it enforces SAML and user is member" do
        business_with_saml = create :business, owners: [create(:user)]
        provider = create :business_saml_provider, business: business_with_saml
        org = create :organization
        business_with_saml.add_organization(org)
        create :external_identity, user: @user, provider: provider
        org.add_member(@user)

        business_with_no_saml = create :business, owners: [create(:user)]
        org = create :organization
        business_with_no_saml.add_organization(org)
        org.add_member(@user)

        business_with_billing_manager_with_saml = create :business, owners: [create(:user)]
        provider = create :business_saml_provider, business: business_with_billing_manager_with_saml
        create :external_identity, user: business_with_billing_manager_with_saml.owners.first, provider: provider
        create :external_identity, user: @user, provider: provider
        billing = Business::BillingManagement.new(business_with_billing_manager_with_saml)
        billing.add_manager(@user, actor: business_with_billing_manager_with_saml.owners.first)

        business_with_billing_manager_without_saml = create :business, owners: [create(:user)]
        billing = Business::BillingManagement.new(business_with_billing_manager_without_saml)
        billing.add_manager(@user, actor: business_with_billing_manager_without_saml.owners.first)

        business_without_member = create :business, owners: [create(:user)]

        inputs = [
          business_with_saml, business_with_no_saml, business_with_billing_manager_without_saml,
          business_with_billing_manager_with_saml, business_without_member
        ]
        assert_equal [business_with_saml, business_with_billing_manager_with_saml], @filter.multiple_saml_applicable(inputs, @filter.target_provider)
      end
    end
  end

  context "multiple_saml_satisfied" do
    context "when SAML scope private resources to org is enabled" do
      test "returns correct visibility decisions for internal and private", skip_enterprise: true do
        enable_feature_flag(:saml_scope_private_resources_to_org)

        business_with_saml = create :business, name: "business-with-saml", owners: [create(:user)]
        org1 = create :organization
        business_with_saml.add_organization(org1)
        org1.add_member(@user)

        business_with_no_saml = create :business, name: "business-with-no-saml", owners: [create(:user)]
        org2 = create :organization
        business_with_no_saml.add_organization(org2)
        org2.add_member(@user)
        @filter.stubs(:authorized_saml_businesses).returns([business_with_saml])

        inputs = [org1.reload, org2.reload]
        results = @filter.multiple_saml_satisfied(inputs, @filter.target_provider)
        assert_equal :satisfied, results[org1][:internal]
        assert_equal :unsatisfied, results[org2][:internal]
        assert_equal :satisfied, results[org1][:private]
        assert_equal :satisfied, results[org2][:private]
      end
    end

    context "when SAML scope private resources to org is disabled" do
      test "returns correct visibility decisions for private only", skip_enterprise: true do
        disable_feature_flag(:saml_scope_private_resources_to_org)

        business_with_saml = create :business, name: "business-with-saml", owners: [create(:user)]
        org1 = create :organization
        business_with_saml.add_organization(org1)
        org1.add_member(@user)

        business_with_no_saml = create :business, name: "business-with-no-saml", owners: [create(:user)]
        org2 = create :organization
        business_with_no_saml.add_organization(org2)
        org2.add_member(@user)
        @filter.stubs(:authorized_saml_businesses).returns([business_with_saml])

        inputs = [org1.reload, org2.reload]
        results = @filter.multiple_saml_satisfied(inputs, @filter.target_provider)
        refute results[org1][:internal]
        refute results[org2][:internal]
        assert_equal :satisfied, results[org1][:private]
        assert_equal :satisfied, results[org2][:private]
      end
    end
  end
end unless ENV["TEST_CAP_VIA_AUTHZD"] == "1"
