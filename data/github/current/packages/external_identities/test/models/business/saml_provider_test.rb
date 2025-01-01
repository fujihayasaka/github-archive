# typed: true
# frozen_string_literal: true

require "test_helper"

module BusinessSamlProviderAuditLogTestHelper
  def expected_audit_log_payload_for(business)
    if GitHub.flipper[:saml_encrypted_assertions].enabled?(business)
      {
        business_id: business.id,
        business: business.slug,
        name: business.name,
        sso_url: business.saml_provider.sso_url,
        issuer: business.saml_provider.issuer,
        digest_method: business.saml_provider.digest_method,
        signature_method: business.saml_provider.signature_method,
        encrypted_assertions: business.saml_provider.encrypted_assertions,
        encryption_method: business.saml_provider.encryption_method,
        key_transport_method: business.saml_provider.key_transport_method,
        business_created_at: business.created_at,
        seats: business.seats,
      }
    else
      {
        business_id: business.id,
        business: business.slug,
        name: business.name,
        sso_url: business.saml_provider.sso_url,
        issuer: business.saml_provider.issuer,
        digest_method: business.saml_provider.digest_method,
        signature_method: business.saml_provider.signature_method,
        business_created_at: business.created_at,
        seats: business.seats,
      }
    end
  end
end

class BusinessSamlProviderTest < GitHub::TestCase
  include BusinessSamlProviderAuditLogTestHelper
  extend EncryptedColumnTestHelper

  test_encrypted_column(:business_saml_provider, :encrypted_key) do
    Business.all.each do |business|
      business.destroy
    end
  end

  fixtures do
    @business_admin = create :user
    @business = create :business, owners: [@business_admin]
    @provider_attrs = {
      sso_url: "https://example.com/sso",
      issuer: "http://example.com",
      idp_certificate: Rails.root.join("test/fixtures/misc/saml/okta.pem").read,
    }
  end

  context "#sso_url" do
    test "cannot exceed 255 characters" do
      provider = build :business_saml_provider, business: @business, sso_url: "https://#{"e" * 300}.ee/hello"
      refute_predicate provider, :valid?
      assert_includes provider.errors[:sso_url], "is too long (maximum is 255 characters)"
    end
  end

  context "#issuer" do
    test "cannot exceed 255 characters" do
      provider = build :business_saml_provider, business: @business, issuer: "https://#{"e" * 300}.ee/hello"
      refute_predicate provider, :valid?
      assert_includes provider.errors[:issuer], "is too long (maximum is 255 characters)"
    end
  end

  context "signature_method" do
    test "defaults" do
      provider = @business.create_saml_provider(@provider_attrs.except(:signature_method))

      assert_equal SamlProviderAlgorithms::DEFAULT_SIGNATURE_METHOD, provider.signature_method
      assert_equal 256, provider.read_attribute_before_type_cast(:digest_method)
    end

    test "maps to signature String" do
      provider = @business.create_saml_provider(@provider_attrs)
      provider.signature_method = 512
      assert_equal "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512", provider.signature_method
    end

    # when the value stored is `0`, converts it to the key for the default
    test "resolves default when saving" do
      provider = @business.create_saml_provider(@provider_attrs)
      provider.signature_method = 0
      provider.save

      assert_equal "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256", provider.signature_method
      assert_equal 256, provider.read_attribute_before_type_cast(:digest_method)
    end
  end

  context "signature_method=" do
    test "accepts Integer value" do
      provider = @business.create_saml_provider(@provider_attrs)

      provider.signature_method = 512
      assert provider.save

      assert_equal "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512", provider.signature_method
    end

    test "accepts String value" do
      provider = @business.create_saml_provider(@provider_attrs)

      provider.signature_method = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512"
      assert provider.save

      assert_equal "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512", provider.signature_method
    end
  end

  context "digest_method" do
    test "defaults" do
      provider = @business.create_saml_provider(@provider_attrs.except(:digest_method))

      assert_equal SamlProviderAlgorithms::DEFAULT_DIGEST_METHOD, provider.digest_method
      assert_equal 256, provider.read_attribute_before_type_cast(:digest_method)
    end

    test "maps to signature String" do
      provider = @business.create_saml_provider(@provider_attrs)
      provider.digest_method = 512
      assert_equal "http://www.w3.org/2001/04/xmlenc#sha512", provider.digest_method
    end

    # when the value stored is `0`, converts it to the key for the default
    test "resolves default when saving" do
      provider = @business.create_saml_provider(@provider_attrs)
      provider.digest_method = 0
      provider.save

      assert_equal "http://www.w3.org/2001/04/xmlenc#sha256", provider.digest_method
      assert_equal 256, provider.read_attribute_before_type_cast(:digest_method)
    end
  end

  context "digest_method=" do
    test "accepts Integer value" do
      provider = @business.create_saml_provider(@provider_attrs)

      provider.digest_method = 512
      assert provider.save

      assert_equal "http://www.w3.org/2001/04/xmlenc#sha512", provider.digest_method
    end

    test "accepts String value" do
      provider = @business.create_saml_provider(@provider_attrs)

      provider.digest_method = "http://www.w3.org/2001/04/xmlenc#sha512"
      assert provider.save

      assert_equal "http://www.w3.org/2001/04/xmlenc#sha512", provider.digest_method
    end
  end

  context "audit log" do
    test "instruments enabling SAML" do
      events = subscribe "business.enable_saml"

      @business.create_saml_provider(@provider_attrs)

      expected_payload = expected_audit_log_payload_for(@business)

      assert event = events.pop, "an event was expected"

      assert_equal "business.enable_saml", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments disabling SAML" do
      @business.create_saml_provider(@provider_attrs)

      events = subscribe "business.disable_saml"

      @business.saml_provider.destroy

      expected_payload = expected_audit_log_payload_for(@business)

      assert event = events.pop, "an event was expected"
      assert_equal "business.disable_saml", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments updating SAML provider settings" do
      @business.create_saml_provider(@provider_attrs)

      events = subscribe "business.update_saml_provider_settings"

      @business.saml_provider.update({
        sso_url: "http://other.example.com",
        issuer: "http://other.example.com",
      })

      expected_payload = expected_audit_log_payload_for(@business)

      assert event = events.pop, "an event was expected"
      assert_equal "business.update_saml_provider_settings", event.name
      assert_equal expected_payload, event.payload.except(:changes, :changed)
      assert event.payload.key?(:changes)
      assert event.payload.key?(:changed)
    end

    test "instruments recovery codes generated after generate_recovery! save" do
      @business.create_saml_provider(@provider_attrs)

      events = subscribe "business.recovery_codes_generated"

      @business.saml_provider.generate_recovery!
      @business.saml_provider.save

      assert event = events.pop, "an event was expected"
      assert_equal "business.recovery_codes_generated", event.name
    end

    test "instruments recovery codes generated when saml provider created" do
      events = subscribe "business.recovery_codes_generated"

      @business.create_saml_provider(@provider_attrs)

      assert event = events.pop, "an event was expected"
      assert_equal "business.recovery_codes_generated", event.name
    end
  end

  context "recovery codes" do
    test "generates recovery codes on creation" do
      provider = create(:business_saml_provider, business: @business)

      refute_nil provider.secret
      refute_nil provider.recovery_secret
      refute_nil provider.recovery_used_bitfield
      refute_predicate provider, :recovery_codes_viewed?
    end

    test "unused recovery codes can be verified" do
      provider = create(:business_saml_provider, business: @business)
      code = provider.recovery_code(0)
      refute provider.recovery_code_used?(0)

      assert_equal true, provider.verify_recovery_code!(code), "Recovery code '#{code}' should be valid"
      assert provider.recovery_code_used?(0)
    end

    test "used recovery codes cannot be verified" do
      provider = create(:business_saml_provider, business: @business)
      code = provider.recovery_code(0)
      refute provider.recovery_code_used?(0)

      assert_equal true, provider.verify_recovery_code!(code), "Unused recovery code '#{code}' should be valid"
      assert_equal false, provider.verify_recovery_code!(code), "Used recovery code '#{code}' should NOT be valid"
    end

    test "formatted recovery codes can be verified" do
      provider = create(:business_saml_provider, business: @business)
      code = provider.formatted_recovery_codes.first
      refute provider.recovery_code_used?(0)

      assert_equal true, provider.verify_recovery_code!(code), "Recovery code '#{code}' should be valid"
      assert provider.recovery_code_used?(0)
    end
  end

  context "target" do
    test "finds the associated business account" do
      provider = @business.create_saml_provider(@provider_attrs)
      assert_equal @business, provider.target
    end

    test "aliasses to 'business'" do
      provider = @business.create_saml_provider(@provider_attrs)
      provider.reload

      # loading `#business` should use the same association cache
      # and object as `#target`
      refute provider.association_cached?(:target)
      assert_equal @business, provider.business
      assert provider.association_cached?(:target)
      assert_equal provider.target, provider.business
    end
  end

  context "user provisioning validations" do
    test "does not allow SAML deprovisioning to be enabled if SAML provisioning is not enabled" do
      provider = create(:business_saml_provider, business: @business)
      refute_predicate provider, :saml_provisioning_enabled?
      refute_predicate provider, :saml_deprovisioning_enabled?

      provider.update(saml_deprovisioning_enabled: true)

      refute_predicate provider, :valid?
      assert_match "enable SAML user provisioning before", provider.errors.full_messages.join
    end

    test "allows SAML deprovisioning to be enabled if user provisioning is enabled" do
      GitHub.flipper[:enterprise_idp_provisioning].enable(@business)
      provider = create(:business_saml_provider, business: @business, provisioning_enabled: true)
      assert_predicate provider, :saml_provisioning_enabled?
      refute_predicate provider, :saml_deprovisioning_enabled?

      provider.update(saml_deprovisioning_enabled: true)

      assert_predicate provider, :valid?
      assert_empty provider.errors
      assert_predicate provider, :saml_deprovisioning_enabled?
    end
  end

  context "#saml_groups_valid_for_deprovisioning?" do
    test "invalid if provisioning is disabled" do
      GitHub.flipper[:enterprise_idp_provisioning].enable(@business)
      provider = create(:business_saml_provider, business: @business, provisioning_enabled: false)
      refute_predicate provider, :saml_provisioning_enabled?
      refute_predicate provider, :saml_deprovisioning_enabled?

      refute provider.saml_groups_valid_for_deprovisioning?(@business_admin)
    end

    test "valid if the current user doesn't exist and provisioning is enabled" do
      GitHub.flipper[:enterprise_idp_provisioning].enable(@business)
      provider = create(:business_saml_provider, business: @business, provisioning_enabled: true)
      assert_predicate provider, :saml_provisioning_enabled?
      refute_predicate provider, :saml_deprovisioning_enabled?

      assert provider.saml_groups_valid_for_deprovisioning?(nil)
    end

    test "valid if provisioning enabled and current_user has SAML metadata groups" do
      GitHub.flipper[:enterprise_idp_provisioning].enable(@business)
      provider = create(:business_saml_provider, business: @business, provisioning_enabled: true)
      assert_predicate provider, :saml_provisioning_enabled?
      refute_predicate provider, :saml_deprovisioning_enabled?

      org = create(:organization)
      @business.add_organization(org)
      saml_user_data = Platform::Provisioning::SamlUserData.new
      saml_user_data.append "NameID", "admino-raptor"
      saml_user_data.append "groups", org.login
      admin_identity = create(:external_identity, user: org.admin,
      provider: provider, saml_user_data: saml_user_data)

      assert provider.saml_groups_valid_for_deprovisioning?(org.admin)
    end

    test "valid if provisioning enabled and current_user has a different kind of SAML metadata groups" do
      GitHub.flipper[:enterprise_idp_provisioning].enable(@business)
      provider = create(:business_saml_provider, business: @business, provisioning_enabled: true)
      assert_predicate provider, :saml_provisioning_enabled?
      refute_predicate provider, :saml_deprovisioning_enabled?

      org = create(:organization)
      @business.add_organization(org)
      saml_user_data = Platform::Provisioning::SamlUserData.new
      saml_user_data.append "NameID", "admino-raptor"
      saml_user_data.append "http://schemas.microsoft.com/ws/2008/06/identity/claims/groups", org.login
      admin_identity = create(:external_identity, user: org.admin,
      provider: provider, saml_user_data: saml_user_data)

      assert provider.saml_groups_valid_for_deprovisioning?(org.admin)
    end

    test "invalid if provisioning enabled and current user is missing SAML metadata groups" do
      GitHub.flipper[:enterprise_idp_provisioning].enable(@business)
      provider = create(:business_saml_provider, business: @business, provisioning_enabled: true)
      assert_predicate provider, :saml_provisioning_enabled?
      refute_predicate provider, :saml_deprovisioning_enabled?

      org = create(:organization)
      @business.add_organization(org)
      saml_user_data = Platform::Provisioning::SamlUserData.new
      saml_user_data.append "NameID", "admino-raptor"
      admin_identity = create(:external_identity, user: org.admin,
      provider: provider, saml_user_data: saml_user_data)

      refute provider.saml_groups_valid_for_deprovisioning?(org.admin)
    end
  end

  context "team sync saml settings changed", team_synchronization_available: true do
    test "notifies tenant that saml settings have changed" do
      tenant = create(:business_team_sync_tenant, :azuread)
      provider = tenant.business.saml_provider

      tenant.expects(:saml_settings_changed).with(provider)
      provider.update(issuer: "https://enterprise-saml.example.com")
    end

    test "notifies the tenant to disable a tenant that is in pending state" do
      tenant = create(:business_team_sync_tenant, :azuread, status: :pending)
      provider = tenant.business.saml_provider
      assert_enqueued_with(job: UpdateTeamSyncTenantJob) do
        provider.update(issuer: "https://enterprise-saml.example.com")
      end
    end

    test "updates tenant when saml settings are removed" do
      tenant = create(:business_team_sync_tenant, :azuread, status: :pending)
      provider = tenant.business.saml_provider
      assert_enqueued_with(job: UpdateTeamSyncTenantJob) do
        provider.destroy
      end
    end
  end

  context "#external_identities_for_organization" do
    test "retrieves all ExternalIdentity's if provisioning is enabled for the enterprise" do
      GitHub.flipper[:enterprise_idp_provisioning].enable(@business)
      saml_provider = create(:business_saml_provider, :full_user_provisioning, business: @business)
      org = create(:organization)
      @business.add_organization(org)
      saml_user_data = Platform::Provisioning::SamlUserData.new
      saml_user_data.append "NameID", "admino-raptor"
      saml_user_data.append "groups", org.login
      admin_identity = create(:external_identity, user: org.admin,
        provider: saml_provider, saml_user_data: saml_user_data)

      invited_user_data = Platform::Provisioning::ScimUserData.new
      invited_user_data.append "userName", "friend"
      invited_user_data.append "groups", org.login
      invited_identity = create(:external_identity, :unlinked, :scim, provider: saml_provider,
        organization_invitation: create(:organization_invitation, :email, organization: org),
        scim_user_data: invited_user_data)

      non_member_user_data = Platform::Provisioning::ScimUserData.new
      non_member_user_data.append "userName", "not-an-org-member"
      non_member_user_data.append "groups", org.login
      non_member_identity = create(:external_identity, :scim, provider: saml_provider,
                                   scim_user_data: non_member_user_data, user: nil)

      assert_same_elements [admin_identity, invited_identity, non_member_identity],
                           saml_provider.external_identities_for_organization(org)
    end

    test "does not retrieve non-member identities if provisioning is not enabled" do
      saml_provider = create(:business_saml_provider, business: @business)
      refute_predicate saml_provider, :saml_provisioning_enabled?
      org = create(:organization)
      @business.add_organization(org)
      saml_user_data = Platform::Provisioning::SamlUserData.new
      saml_user_data.append "NameID", "admino-raptor"
      saml_user_data.append "groups", org.login
      admin_identity = create(:external_identity, user: org.admin,
                              provider: saml_provider, saml_user_data: saml_user_data)

      invited_user_data = Platform::Provisioning::ScimUserData.new
      invited_user_data.append "userName", "friend"
      invited_user_data.append "groups", org.login
      invited_identity = create(:external_identity, :unlinked, :scim, provider: saml_provider,
                                organization_invitation: create(:organization_invitation, :email, organization: org),
                                scim_user_data: invited_user_data)

      non_member_user_data = Platform::Provisioning::ScimUserData.new
      non_member_user_data.append "userName", "not-an-org-member"
      non_member_user_data.append "groups", org.login
      non_member_identity = create(:external_identity, :scim, provider: saml_provider,
                                   scim_user_data: non_member_user_data, user: nil)

      assert_same_elements [admin_identity, invited_identity],
                           saml_provider.external_identities_for_organization(org)
    end

    unless GitHub.single_business_environment?
      test "returns no results if organization doesn't belong to the provider's enterprise" do
        GitHub.flipper[:enterprise_idp_provisioning].enable(@business)
        saml_provider = create(:business_saml_provider, business: @business)
        org = create(:organization)
        @business.add_organization(org)
        saml_user_data = Platform::Provisioning::SamlUserData.new
        saml_user_data.append "NameID", "admino-raptor"
        saml_user_data.append "groups", org.login
        create(:external_identity, user: org.admin,
          provider: saml_provider, saml_user_data: saml_user_data)

        business2 = create(:business_saml_provider).business
        GitHub.flipper[:enterprise_idp_provisioning].enable(business2)
        assert_empty business2.saml_provider.external_identities_for_organization(org)
      end
    end
  end

  context "#default_session_expiration" do
    test "returns 1 day for Business SAML provider" do
      provider = @business.create_saml_provider(@provider_attrs)

      Timecop.freeze do
        assert_equal 1.day.from_now, provider.default_session_expiration
      end
    end
  end

  test "when saml_provider is destroyed external identity is destroyed, but existing saml_mapping is not on GHES with scim", enterprise_only: true do
    provider = @business.create_saml_provider(@provider_attrs)
    provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")

    user = create :ghes_scim_user, business: @business
    create(:user_saml_mapping, user: user)

    assert_equal user.external_identities.first.provider, @business.saml_provider

    refute_empty user.external_identities
    refute_nil user.saml_mapping
    refute_predicate user.emails, :empty?
    refute_nil user.emails.primary.first
    refute_predicate user, :suspended?

    assert_difference ["ExternalIdentity.count"], -1 do
      perform_enqueued_jobs only: [DestroyExternalProviderDependentsJob] do
        @business.saml_provider.destroy
      end
    end

    user.reload

    assert_empty user.external_identities
    refute_nil user.saml_mapping
    refute_predicate user.emails, :empty?
    refute_nil user.emails.primary.first
    refute_predicate user, :suspended?
  end

  context "#enterprise_server_scim_enabled?", enterprise_only: true do
    test "returns true on GHES with scim_provisioning_state_enabled" do
      provider = @business.create_saml_provider(@provider_attrs)
      provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")
      assert_predicate provider, :enterprise_server_scim_enabled?
    end

    test "returns false on GHES with scim_provisioning_state_disabled" do
      provider = @business.create_saml_provider(@provider_attrs)
      provider.update(scim_provisioning_state: "scim_provisioning_state_disabled")
      refute_predicate provider, :enterprise_server_scim_enabled?
    end
  end

  context "destroy under emu scenario", skip_enterprise: true do
    test "cascade destroy when provider destroyed" do
      external_group = create :external_group, :with_members, :with_team

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

    context "#enterprise_server_scim_enabled?" do
      test "returns false on GHEC with scim_provisioning_state_enabled" do
        provider = @business.create_saml_provider(@provider_attrs)
        provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")
        refute_predicate provider, :enterprise_server_scim_enabled?
      end

      test "returns false on GHEC with scim_provisioning_state_disabled" do
        provider = @business.create_saml_provider(@provider_attrs)
        provider.update(scim_provisioning_state: "scim_provisioning_state_disabled")
        refute_predicate provider, :enterprise_server_scim_enabled?
      end
    end
  end
end
