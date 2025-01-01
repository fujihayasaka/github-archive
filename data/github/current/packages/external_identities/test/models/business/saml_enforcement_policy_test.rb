# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessSamlEnforcementPolicyTest < GitHub::TestCase
  fixtures do
    @provider = create :business_saml_provider
    @business = @provider.business
    @org = create :organization
    @business.add_organization @org

    @member = create :user, login: "org-member"
    @org.add_member(@member)

    @collaborator = create :user, login: "org-collaborator"
    @org.add_member(@collaborator)
    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) { @org.convert_to_outside_collaborator!(@collaborator) }

    @unaffiliated = create :user, login: "unaffiliated"

    unless GitHub.single_business_environment?
      @non_saml_business = create :business
      @org_in_non_saml_business = create :organization
      @non_saml_business.add_organization @org_in_non_saml_business
      @org_in_non_saml_business.add_member(@member)
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
    GitHub.flipper[:unaffiliated_user_accounts].enable
    unaffiliated = create :user
    create :business_user_account, business: @business, user: unaffiliated, business_roles_bitfield: 0
    assert enforced?(business: @business, user: unaffiliated), "SAML SSO should be enforced for user who are unaffiliated members of the business"
  end

  test "enforced for members of accessed organization" do
    assert enforced?(business: @business, user: @member, organization: @org)
  end

  test "enforced for all oidc businesses", skip_enterprise: true do
    emu_owner = create :emu, :owner, provider_type: :oidc, login: "owner"
    emu_business = emu_owner.enterprise_managed_business
    org = create :organization, business: emu_business, admin: emu_owner

    member = create :emu, login: "user1", business: emu_business, provider_type: :oidc
    org.add_member(member)
    not_member = create :emu, login: "user2", business: emu_business, provider_type: :oidc

    assert enforced?(business: emu_business, user: member, organization: org)
    assert enforced?(business: emu_business, user: emu_owner, organization: org)
    assert enforced?(business: emu_business, user: not_member, organization: org)
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
