# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessOIDCProviderTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @vanilla_emu_enterprise = create :business, business_type: "enterprise_managed", shortcode: "abc"

    @external_group = create(:external_group, :with_team, :with_members, number_of_members: 5)
    @emu_enterprise_with_saml_enabled = @external_group.provider.business

    @non_emu_enterprise = create :business
    @tenant_id = "03cb14c6-f6c7-49aa-95f7-2fc62c16a5c2"
  end

  setup do
    unstub_vso
  end

  context "validations" do
    test "create succeeds" do
      VCR.use_cassette("oidc/azure-configuration", erb: { tenant_id: "TenantID", access_token: "AccessToken" }) do
        business_oidc_provider = Business::OIDCProvider.create(business: @vanilla_emu_enterprise, oidc_provider: :azure, tenant_id: @tenant_id)

        refute_nil business_oidc_provider
        assert_predicate business_oidc_provider, :valid?
        assert_equal @vanilla_emu_enterprise.id, business_oidc_provider.business_id
        assert_equal "azure", business_oidc_provider.oidc_provider
        assert_equal @tenant_id, business_oidc_provider.tenant_id
        refute_nil business_oidc_provider.sso_url
      end
    end

    test "create fails with saml attached emu enterprise" do
      business_oidc_provider = Business::OIDCProvider.create(business: @emu_enterprise_with_saml_enabled, oidc_provider: :azure, tenant_id: @tenant_id)

      refute_predicate business_oidc_provider, :valid?
      assert_includes business_oidc_provider.errors[:business_id], "cannot enable both SAML and OIDC single sign-on"
    end

    test "create succeeds with saml attached emu enterprise and migrate_to_oidc is set" do
      VCR.use_cassette("oidc/azure-configuration", erb: { tenant_id: "TenantID", access_token: "AccessToken" }) do
        business_oidc_provider = Business::OIDCProvider.create(business: @emu_enterprise_with_saml_enabled, oidc_provider: :azure,
          tenant_id: @tenant_id, migrate_to_oidc: true)

        assert_predicate business_oidc_provider, :persisted?
        assert_predicate business_oidc_provider, :valid?
        assert_equal @emu_enterprise_with_saml_enabled.id, business_oidc_provider.business_id
        assert_equal "azure", business_oidc_provider.oidc_provider
        assert_equal @tenant_id, business_oidc_provider.tenant_id
        refute_nil business_oidc_provider.sso_url
      end
    end

    test "create fails with non emu enterprise" do
      business_oidc_provider = Business::OIDCProvider.create(business: @non_emu_enterprise, oidc_provider: :azure, tenant_id: @tenant_id)

      refute_predicate business_oidc_provider, :valid?
      assert_includes business_oidc_provider.errors[:business_id], "must be an enterprise-managed enterprise account"
    end
  end

  context "external identities" do
    test "associates with external identity and session" do
      user = create :user
      business_oidc_provider = Business::OIDCProvider.create(business: @vanilla_emu_enterprise, oidc_provider: :azure, tenant_id: @tenant_id)
      user_identity = create(:external_identity, provider: business_oidc_provider, user: user)
      user_session = create(:user_session, user: user)
      external_identity_session = create :external_identity_session, external_identity: user_identity, user_session: user_session

      assert_equal user_identity, business_oidc_provider.reload.external_identities.first
      assert_equal external_identity_session, business_oidc_provider.reload.external_identity_sessions.first
    end
  end

  context "external groups" do
    test "associates with external groups" do
      business_oidc_provider = Business::OIDCProvider.create(business: @vanilla_emu_enterprise, oidc_provider: :azure, tenant_id: @tenant_id)
      external_group = create :external_group, business: business_oidc_provider.business

      assert_equal external_group, business_oidc_provider.reload.external_groups.first
    end
  end

  context "migrate_from_saml!" do
    test "migrates external identities from saml to oidc" do
      business_oidc_provider = Business::OIDCProvider.create(business: @emu_enterprise_with_saml_enabled, oidc_provider: :azure,
        tenant_id: @tenant_id, migrate_to_oidc: true)

      refute_nil business_oidc_provider

      display_name = @emu_enterprise_with_saml_enabled.saml_provider.external_identities.first.scim_user_data.display_name
      group_display_name = @emu_enterprise_with_saml_enabled.saml_provider.external_groups.first.display_name
      number_of_members = @emu_enterprise_with_saml_enabled.saml_provider.external_identities.count
      number_of_groups = @emu_enterprise_with_saml_enabled.saml_provider.external_groups.count

      business_oidc_provider.migrate_from_saml!

      assert_equal number_of_members, business_oidc_provider.reload.external_identities.count
      assert_equal number_of_groups, business_oidc_provider.external_groups.count

      external_identity = T.must(business_oidc_provider.external_identities.first).reload
      profile = external_identity.user.find_or_create_profile

      assert_equal display_name + Business::OIDCProvider::MIGRATION_SUFFIX, external_identity.scim_user_data.display_name
      assert_equal display_name + Business::OIDCProvider::MIGRATION_SUFFIX, profile.name
      assert_equal group_display_name + Business::OIDCProvider::MIGRATION_SUFFIX, T.must(business_oidc_provider.external_groups.first).display_name

      assert_nil @emu_enterprise_with_saml_enabled.reload.saml_provider
    end

    test "does not update but migrates disabled external identities from saml to oidc" do
      business_oidc_provider = Business::OIDCProvider.create(business: @emu_enterprise_with_saml_enabled, oidc_provider: :azure,
        tenant_id: @tenant_id, migrate_to_oidc: true)

      refute_nil business_oidc_provider

      external_identity = @emu_enterprise_with_saml_enabled.saml_provider.external_identities.first
      external_identity.disable
      external_identity.save

      profile = external_identity.user.find_or_create_profile
      display_name = external_identity.scim_user_data.display_name
      profile_name = profile.name

      business_oidc_provider.migrate_from_saml!

      assert_equal display_name, external_identity.scim_user_data.display_name
      assert_equal profile_name, profile.name
      assert_includes business_oidc_provider.external_identities.pluck(:id), external_identity.id
    end

    test "does not update but migrates deleted external identities from saml to oidc" do
      business_oidc_provider = Business::OIDCProvider.create(business: @emu_enterprise_with_saml_enabled, oidc_provider: :azure,
        tenant_id: @tenant_id, migrate_to_oidc: true)

      refute_nil business_oidc_provider

      external_identity = @emu_enterprise_with_saml_enabled.saml_provider.external_identities.first
      profile = external_identity.user.find_or_create_profile
      profile_name = profile.name

      external_identity.mark_deleted
      external_identity.save

      business_oidc_provider.migrate_from_saml!

      assert_nil external_identity.scim_user_data.display_name
      assert_equal profile_name, profile.name
      assert_includes business_oidc_provider.external_identities.pluck(:id), external_identity.id
    end

    test "does not update but migrates deleted external group from saml to oidc" do
      business_oidc_provider = Business::OIDCProvider.create(business: @emu_enterprise_with_saml_enabled, oidc_provider: :azure,
        tenant_id: @tenant_id, migrate_to_oidc: true)

      refute_nil business_oidc_provider

      deleted_group = create(:external_group, business: @emu_enterprise_with_saml_enabled)
      display_name = deleted_group.display_name
      deleted_group.mark_group_deleted
      deleted_group.save

      business_oidc_provider.migrate_from_saml!

      assert_equal display_name, deleted_group.display_name
      assert_includes business_oidc_provider.external_groups.pluck(:id), deleted_group.id
    end
  end

  context "#enterprise_server_scim_enabled?" do
    test "returns false" do
      VCR.use_cassette("oidc/azure-configuration", erb: { tenant_id: "TenantID", access_token: "AccessToken" }) do
        business_oidc_provider = Business::OIDCProvider.create(business: @vanilla_emu_enterprise, oidc_provider: :azure, tenant_id: @tenant_id)
        refute_predicate business_oidc_provider, :enterprise_server_scim_enabled?
      end
    end
  end

  context "#find_provider_type" do
    test "returns azure_ad as provider type when azure ad is the provider for business" do
      VCR.use_cassette("oidc/azure-configuration", erb: { tenant_id: "TenantID", access_token: "AccessToken" }) do
        business_oidc_provider = Business::OIDCProvider.create(business: @vanilla_emu_enterprise, oidc_provider: :azure, tenant_id: @tenant_id)
        assert_equal :azure_ad, business_oidc_provider.find_provider_type
      end
    end
  end

  context "audit log" do
    test "instruments recovery codes generated after generate_recovery! save" do
      business_oidc_provider = Business::OIDCProvider.create(business: @vanilla_emu_enterprise, oidc_provider: :azure, tenant_id: @tenant_id)

      events = subscribe "business.recovery_codes_generated"

      business_oidc_provider.generate_recovery!
      business_oidc_provider.save

      assert event = events.pop, "an event was expected"
      assert_equal "business.recovery_codes_generated", event.name
    end

    test "instruments recovery codes generated when saml provider created" do
      events = subscribe "business.recovery_codes_generated"

      Business::OIDCProvider.create(business: @vanilla_emu_enterprise, oidc_provider: :azure, tenant_id: @tenant_id)

      assert event = events.pop, "an event was expected"
      assert_equal "business.recovery_codes_generated", event.name
    end
  end

  context "#default_session_expiration" do
    test "returns 1 day for Business OIDC provider" do
      business_oidc_provider = Business::OIDCProvider.create(business: @vanilla_emu_enterprise, oidc_provider: :azure, tenant_id: @tenant_id)

      Timecop.freeze do
        assert_equal 1.day.from_now, business_oidc_provider.default_session_expiration
      end
    end
  end

  context "destroy under emu scenario", skip_enterprise: true do
    test "cascade destroy when provider destroyed" do
      owner = create(:emu, :owner, provider_type: :oidc)
      business = owner.enterprise_managed_business

      assert_predicate business.oidc_provider, :present?

      external_group = create :external_group, :with_members, :with_team, business: business

      external_group.reload
      member = external_group.external_identity_group_memberships.first.external_identity.user
      team = external_group.external_group_teams.first.team

      assert team.members.include?(member)
      assert team.organization.members.include?(member)
      refute_predicate member, :suspended?

      differences = {
        "ExternalGroup.count" => -1,
        "ExternalIdentityGroupMembership.count" => -5,
        "ExternalGroupTeam.count" => -1,
        "ExternalIdentity.count" => -6,
        "Ability.count" => -10,
      }
      refute_predicate external_group.target, :removing_external_provider?

      assert_difference(differences) do
        external_group.provider.destroy
        assert_predicate external_group.target, :removing_external_provider?

        perform_enqueued_jobs only: DestroyExternalProviderDependentsJob
        perform_enqueued_jobs only: DestroyTeamDependantsJob
        perform_enqueued_jobs only: RemoveOrgMemberJob
        perform_enqueued_jobs only: RevokeOrgMembershipAbilitiesJob
      end

      refute_predicate external_group.target, :removing_external_provider?

      refute team.members.include?(member)
      refute team.organization.members.include?(member)
      assert_predicate member.reload, :suspended?
    end
  end
end
