# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationSamlSsoEnforcementTest < GitHub::TestCase
  fixtures do
    @admin_without_saml = create(:user)
    @org_without_saml = create :organization, login: "nosaml", admin: @admin_without_saml

    @provider = create(:organization_saml_provider)
    @org = @provider.organization
    @repo = create(:repository, owner: @org)

    @admin = @org.admin
    create :external_identity, provider: @provider, user: @admin

    @unlinked_member = create(:user)
    @org.add_member @unlinked_member
  end

  context "Organization#saml_sso_enabled?" do
    test "returns false when the organization is not on an Orgs Plus plan" do
      org = create(:organization)
      refute_predicate org, :saml_sso_enabled?
    end

    test "returns false when no SAML provider is present for the organization" do
      @org.saml_provider.destroy

      refute_predicate @org, :saml_sso_enabled?
    end

    test "returns true when a SAML provider is present" do
      assert_predicate @org.saml_provider, :present?

      assert_predicate @org, :saml_sso_enabled?
    end
  end

  context "Organization#saml_sso_enforced?" do
    test "returns false when the organization is not on an Orgs Plus plan" do
      org = create(:organization)
      refute_predicate org, :saml_sso_enforced?
    end

    test "returns false when SAML SSO is not enabled for the organization" do
      @org.saml_provider.destroy

      refute_predicate @org, :saml_sso_enabled?

      refute_predicate @org, :saml_sso_enforced?
    end

    test "returns true when SAML SSO is enabled and enforced" do
      @org.saml_provider.enforce!

      assert_predicate @org, :saml_sso_enforced?
    end
  end

  context "Organization#saml_sso_requirement_met_by?" do
    test "returns true when SAML is not enforced" do
      refute_predicate @org, :saml_sso_enforced?

      assert @org.saml_sso_requirement_met_by?(create(:user))
    end

    test "returns false when SAML is enforced and the user does not have an external identity" do
      @org.saml_provider.enforce!
      assert_predicate @org, :saml_sso_enforced?

      user = create(:user, login: "non-saml-member")

      refute @org.saml_sso_requirement_met_by?(user), "User: #{user} should not meet the SAML enforcement requirement"
    end

    test "returns false when SAML is enforced but the user is nil" do
      @org.saml_provider.enforce!
      assert_predicate @org, :saml_sso_enforced?

      user = nil

      refute @org.saml_sso_requirement_met_by?(user), "User: #{user} should not meet the SAML enforcement requirement"
    end

    test "returns true when SAML is enforced and the user has an external identity" do
      @org.saml_provider.enforce!
      assert_predicate @org, :saml_sso_enforced?

      user = create(:user, login: "saml-member")
      create(:external_identity,
        provider: @org.saml_provider,
        user: user,
      )

      assert @org.saml_sso_requirement_met_by?(user), "User: #{user} should meet the SAML enforcement requirement"
    end
  end

  context "Organization#saml_sso_requirement_met_by_users?" do
    test "returns true when SAML is not enforced" do
      refute_predicate @org, :saml_sso_enforced?

      user = create(:user)
      assert @org.saml_sso_requirement_met_by_users?([user].map(&:id))
    end

    test "returns false when SAML is enforced and the user does not have an external identity" do
      @org.saml_provider.enforce!
      assert_predicate @org, :saml_sso_enforced?

      user = create(:user, login: "non-saml-member")

      refute @org.saml_sso_requirement_met_by_users?([user].map(&:id)), "User: #{user} should not meet the SAML enforcement requirement"
    end

    test "returns false when SAML is enforced and one of the users does not have an external identity" do
      @org.saml_provider.enforce!
      assert_predicate @org, :saml_sso_enforced?

      user = create(:user, login: "non-saml-member")
      user2 = create(:user, login: "saml-member")
      create(:external_identity,
        provider: @org.saml_provider,
        user: user2,
      )

      refute @org.saml_sso_requirement_met_by_users?([user, user2].map(&:id)), "User: #{user} should not meet the SAML enforcement requirement"
    end

    test "returns false when SAML is enforced but the user ids are nil" do
      @org.saml_provider.enforce!
      assert_predicate @org, :saml_sso_enforced?

      user = nil

      refute @org.saml_sso_requirement_met_by_users?(nil), "User: #{user} should not meet the SAML enforcement requirement"
    end

    test "returns true when SAML is enforced and the user has an external identity" do
      @org.saml_provider.enforce!
      assert_predicate @org, :saml_sso_enforced?

      user = create(:user, login: "saml-member")
      create(:external_identity,
        provider: @org.saml_provider,
        user: user,
      )

      assert @org.saml_sso_requirement_met_by_users?([user].map(&:id)), "User: #{user} should meet the SAML enforcement requirement"
    end
  end

  context "#unlinked_saml_members" do
    test "returns an empty relation when SAML SSO is disabled" do
      org = create(:organization)
      assert_predicate org.unlinked_saml_members, :empty?
    end

    test "returns all members when there are no external identities" do
      @org.saml_provider.external_identities.destroy_all
      assert_predicate @org.saml_provider.external_identities, :none?

      assert_same_elements [@org.admin, @unlinked_member], @org.unlinked_saml_members
    end

    test "returns unlinked members even if there are unclaimed external identities provisioned" do
      create(:external_identity, :unlinked, provider: @org.saml_provider)

      unlinked_saml_member = create(:user, login: "non-saml-member")
      @org.add_member(unlinked_saml_member)

      saml_member = create(:user, login: "saml-member")
      @org.add_member(saml_member)

      create(:external_identity,
        provider: @org.saml_provider,
        user: saml_member,
      )

      assert_same_elements [@unlinked_member, unlinked_saml_member], @org.unlinked_saml_members
    end

    test "returns all org members if there are no linked identities" do
      # All users in org do not have their identities linked, but there is a
      # pending unlinked identity present.
      ExternalIdentity.unlink(provider: @org.saml_provider, user: @org.admin)

      assert @org.saml_provider.external_identities.none?

      create(:external_identity, :unlinked, provider: @org.saml_provider)

      assert_same_elements @org.reload.members, @org.unlinked_saml_members
    end

    test "returns only members without external identities linked to the provider" do
      unlinked_saml_member = create(:user, login: "non-saml-member")
      @org.add_member(unlinked_saml_member)

      saml_member = create(:user, login: "saml-member")
      @org.add_member(saml_member)

      create(:external_identity,
        provider: @org.saml_provider,
        user: saml_member,
      )

      assert_same_elements [@unlinked_member, unlinked_saml_member], @org.unlinked_saml_members
    end

    test "does not return outside collaborators without external identities" do
      outside_collaborator = create(:user, login: "outside-collab")
      @repo.add_member(outside_collaborator)

      refute_includes @org.unlinked_saml_members, outside_collaborator
    end
  end

  context "#unlinked_external_identities" do
    test "returns an empty relation when SAML SSO is disabled" do
      org = create(:organization)
      refute_predicate org.saml_provider, :present?
      assert_predicate org.unlinked_external_identities, :empty?
    end

    test "returns an emtpry related when there are no external identities" do
      @org.saml_provider.external_identities.destroy_all
      assert_predicate @org.unlinked_external_identities, :empty?
    end

    test "returns unlinked external identities" do
      external_identity = create :external_identity, provider: @provider
      external_identity.update!(user_id: nil)

      assert_same_elements [external_identity], @org.unlinked_external_identities
    end
  end

  context "#external_identity_session_owner" do
    test "returns the orgs business when business SAML provider is configured" do
      business = create :business, organizations: [@org]
      provider = create :business_saml_provider, business: business

      @org.reload

      assert_equal business, @org.external_identity_session_owner
    end

    test "returns self when business SAML provider is not configured" do
      business = create :business, organizations: [@org]

      @org.reload

      assert_equal @org, @org.external_identity_session_owner
    end

    test "returns self when not belonging to a business" do
      assert_equal @org, @org.external_identity_session_owner
    end
  end

  context "#sso_enabled_on_business?" do
    test "returns false if the organization does not belong to a business" do
      assert_nil @org.business
      refute @org.sso_enabled_on_business?
    end

    test "returns false if the organization's business does not have SAML configured" do
      create :business, organizations: [@org]

      assert @org.reload.business.present?
      refute @org.sso_enabled_on_business?
    end

    test "returns true if the organization's business has SAML configured", skip_enterprise: true do
      business = create(:business_saml_provider).business
      business.add_organization(@org)

      assert @org.reload.business.present?
      assert @org.sso_enabled_on_business?
    end
  end

  context "#saml_sso_present?" do
    test "returns true if SAML is enabled on the org" do
      assert @org.saml_sso_present?
    end

    test "returns false for an org without SAML which does not belong to a business" do
      refute @org_without_saml.saml_sso_present?
    end

    unless GitHub.single_business_environment?
      test "returns false if org belongs to a business without SAML" do
        create(:business, organizations: [@org_without_saml])
        refute @org_without_saml.reload.saml_sso_present?
      end

      test "returns true if org belongs to a business with SAML enabled" do
        business = create(:business, organizations: [@org_without_saml])
        create(:business_saml_provider, business: business)
        assert @org_without_saml.reload.saml_sso_present?
      end
    end
  end

  context "#saml_sso_present_enforced?" do
    test "returns false if SAML is enabled, but not enforced on the org" do
      refute @org.saml_sso_present_enforced?
    end

    test "returns true if SAML is enforced on the org" do
      @org.saml_provider.enforce!

      assert @org.saml_sso_present_enforced?
    end

    test "returns false for an org without SAML which does not belong to a business" do
      refute @org_without_saml.saml_sso_present_enforced?
    end

    unless GitHub.single_business_environment?
      test "returns false if org belongs to a business without SAML" do
        create(:business, organizations: [@org_without_saml])
        refute @org_without_saml.reload.saml_sso_present_enforced?
      end

      test "returns true if org belongs to a business with SAML enabled (automatically enforced)" do
        business = create(:business, organizations: [@org_without_saml])
        create(:business_saml_provider, business: business)
        assert @org_without_saml.reload.saml_sso_present_enforced?
      end
    end
  end
end
