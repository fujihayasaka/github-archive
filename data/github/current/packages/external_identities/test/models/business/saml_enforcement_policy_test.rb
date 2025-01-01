# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessSamlEnforcementPolicyTest < GitHub::TestCase
  fixtures do
    @provider = create :business_saml_provider
    @business = @provider.business
    @org = create :organization

    @member = create :user, login: "org-member"
    @org.add_member(@member)

    @collaborator = create :user, login: "org-collaborator"
    @org.add_member(@collaborator)

    @business.add_organization @org
    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) { @org.convert_to_outside_collaborator!(@collaborator) }

    @unaffiliated = create :user, login: "unaffiliated"

    unless GitHub.single_business_environment?
      @non_saml_business = create :business
      @org_in_non_saml_business = create :organization
      @non_saml_business.add_organization @org_in_non_saml_business
      @org_in_non_saml_business.add_member(@member)

      @oidc_owner = create :emu, :owner, provider_type: :oidc
      @oidc_business = @oidc_owner.enterprise_managed_business
      @oidc_member = create :emu, business: @oidc_business, provider_type: :oidc
      @oidc_collaborator = create :emu, business: @oidc_business, provider_type: :oidc

      @oidc_org = create :organization, business: @oidc_business, admin: @oidc_owner
      @oidc_org.add_member(@oidc_member)
      @oidc_org.add_member(@oidc_collaborator)

      @another_oidc_org = create :organization, business: @oidc_business, admin: @oidc_owner
      @another_oidc_repo = create(:private_repository, owner: @another_oidc_org)
      create(:collaborator, collaborator: @oidc_collaborator, repository: @another_oidc_repo)
    end
  end

  setup do
    GitHub.stubs(:single_business_environment?).returns(false)
  end

  def enforced?(business:, user:, organization: nil)
    Business::SamlEnforcementPolicy.new(business: business, user: user, organization: organization).enforced?
  end

  def filter_enforced(businesses, actor)
    Business::SamlEnforcementPolicy::filter_enforced businesses, actor
  end

  test "not enforced when in a single business environment" do
    GitHub.stubs(:single_business_environment?).returns(true)
    refute enforced?(business: @business, user: @business.owners.first), "SAML SSO should not be enforced for GHES business account"
  end

  test "not enforced without a business" do
    refute enforced?(business: nil, user: @unaffiliated), "SAML SSO should not be enforced without a business instance"
  end

  test "not enforced without a user" do
    refute enforced?(business: @business, user: nil), "SAML SSO should not be enforced without a user"
  end

  test "not enforced without saml sso" do
    user = create :user
    refute enforced?(business: create(:business, owners: [user]), user: user), "SAML SSO should not be enforced without SAML SSO enabled for business"
  end

  test "not enforced when user is not a member of the business" do
    refute enforced?(business: @business, user: @unaffiliated), "SAML SSO should not be enforced for user who are not member of the business"
  end

  test "not enforced for outside collaborator on accessed organization" do
    refute enforced?(business: @business, user: @collaborator, organization: @org), "SAML SSO should not be enforced for outside colloborators"
  end

  test "enforced for business members" do
    assert enforced?(business: @business, user: @business.owners.first), "SAML SSO should be enforced for user who are members of the business"
  end

  test "enforced for unaffiliated business members" do
    enable_feature_flag(:unaffiliated_user_accounts)
    unaffiliated = create :user
    create :business_user_account, business: @business, user: unaffiliated, business_roles_bitfield: 0
    assert enforced?(business: @business, user: unaffiliated), "SAML SSO should be enforced for user who are unaffiliated members of the business"
  end

  test "enforced for members of accessed organization" do
    assert enforced?(business: @business, user: @member, organization: @org)
  end

  test "enforced for all oidc businesses", skip_enterprise: true do
    assert enforced?(business: @oidc_business, user: @oidc_owner, organization: @oidc_org)
    assert enforced?(business: @oidc_business, user: @oidc_member, organization: @oidc_org)
  end

  test "not enforced when user is not a member of the oidc business", skip_enterprise: true do
    oidc_non_member = create :emu, business: @oidc_business, provider_type: :oidc
    refute enforced?(business: @oidc_business, user: oidc_non_member, organization: @oidc_org), "SAML SSO should not be enforced for user who are not member of the business"
  end

  test "not enforced for outside collaborator on accessed organization of the oidc business", skip_enterprise: true do
    refute enforced?(business: @oidc_business, user: @oidc_collaborator, organization: @another_oidc_org), "SAML SSO should not be enforced for outside colloborators"
  end

  context "filter_enforced" do
    test "is empty in single business environment" do
      GitHub.stubs(:single_business_environment?).returns(true)
      assert_equal [], filter_enforced([@businesss], @member)
    end

    unless GitHub.single_business_environment?
      test "includes only businesses with saml configured" do
        assert_equal [@business], filter_enforced([@business, @non_saml_business], @member)
      end

      test "excludes business where user is outside collaborator" do
        assert_equal [], filter_enforced([@business, @non_saml_business], @collaborator)
      end

      test "excludes business where user is not a member" do
        assert_equal [], filter_enforced([@business, @non_saml_business], @unaffiliated)
      end
    end
  end
end
