# typed: true
# frozen_string_literal: true

require "test_helper"

class CapSamlPolicyTest < GitHub::TestCase
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
      user = create :user
      identities = create_list(:external_identity, 10, user: user)
      organizations = identities.map { |i| i.provider.organization }
      filter = ConditionalAccess::Model::Filter::new(nil, actor: user, location: :test)

      GitHub::MysqlInstrumenter.with_track do
        assert_equal organizations, filter.multiple_saml_applicable(organizations, filter.target_provider)
      end

      queries = GitHub::MysqlInstrumenter.queries
      assert_equal 7, queries.count
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

        GitHub::MysqlInstrumenter.with_track do
          assert_equal businesses, Business::SamlEnforcementPolicy.filter_enforced(businesses, owner)
        end

        queries = GitHub::MysqlInstrumenter.queries
        assert_equal 4, queries.count
      end

      test "Business is applicable if it enforces SAML and user is member" do
        business_with_saml = create :business, owners: [create(:user)]
        create :business_saml_provider, business: business_with_saml
        org = create :organization
        business_with_saml.add_organization(org)
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
end
