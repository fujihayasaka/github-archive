# typed: true
# frozen_string_literal: true

require "test_helper"

module OrganizationSamlProviderAuditLogTestHelper
  def expected_audit_log_payload_for(org)
    {
      org_id: org.id,
      org: org.login,
      sso_url: org.saml_provider.sso_url,
      issuer: org.saml_provider.issuer,
      digest_method: org.saml_provider.digest_method,
      signature_method: org.saml_provider.signature_method,
      enforced: org.saml_provider.enforced?,
      org_created_at: org.created_at,
      seats: org.seats,
      filled_seats: org.filled_seats,
      pending_invites: org.pending_invitations.count,
    }
  end
end

class OrganizationSamlProviderTest < GitHub::TestCase
  include OrganizationSamlProviderAuditLogTestHelper

  fixtures do
    @org_admin      = create(:user)
    @org            = create(:organization, admin: @org_admin)
    @saml_org       = create(:business_plus_org, admin: @org_admin)
    @provider_attrs = {
      sso_url: "https://example.com/sso",
      issuer: "http://example.com",
      idp_certificate: Rails.root.join("test/fixtures/misc/saml/okta.pem").read,
    }
    @issuer = "https://sts.windows.net/a3350e2e-d5fb-4682-b8ed-5cf081a1e841/"
    @new_issuer = "https://sts.windows.net/b2261f3f-d5fb-4682-b8ed-5cf081a1e841/"
    @valid_cert = Rails.root.join("test/fixtures/misc/saml/idp.crt").read
  end

  context "signature_method" do
    test "defaults" do
      provider = @org.create_saml_provider(@provider_attrs.except(:signature_method))

      assert_equal SamlProviderAlgorithms::DEFAULT_SIGNATURE_METHOD, provider.signature_method
      assert_equal 256, provider.read_attribute_before_type_cast(:digest_method)
    end

    test "maps to signature String" do
      provider = @org.create_saml_provider(@provider_attrs)
      provider.signature_method = 512
      assert_equal "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512", provider.signature_method
    end

    # when the value stored is `0`, converts it to the key for the default
    test "resolves default when saving" do
      provider = @org.create_saml_provider(@provider_attrs)
      provider.signature_method = 0
      provider.save

      assert_equal "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256", provider.signature_method
      assert_equal 256, provider.read_attribute_before_type_cast(:digest_method)
    end
  end

  context "signature_method=" do
    test "accepts Integer value" do
      provider = @org.create_saml_provider(@provider_attrs)

      provider.signature_method = 512
      assert provider.save

      assert_equal "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512", provider.signature_method
    end

    test "accepts String value" do
      provider = @org.create_saml_provider(@provider_attrs)

      provider.signature_method = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512"
      assert provider.save

      assert_equal "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512", provider.signature_method
    end
  end

  context "digest_method" do
    test "defaults" do
      provider = @org.create_saml_provider(@provider_attrs.except(:digest_method))

      assert_equal SamlProviderAlgorithms::DEFAULT_DIGEST_METHOD, provider.digest_method
      assert_equal 256, provider.read_attribute_before_type_cast(:digest_method)
    end

    test "maps to signature String" do
      provider = @org.create_saml_provider(@provider_attrs)
      provider.digest_method = 512
      assert_equal "http://www.w3.org/2001/04/xmlenc#sha512", provider.digest_method
    end

    # when the value stored is `0`, converts it to the key for the default
    test "resolves default when saving" do
      provider = @org.create_saml_provider(@provider_attrs)
      provider.digest_method = 0
      provider.save

      assert_equal "http://www.w3.org/2001/04/xmlenc#sha256", provider.digest_method
      assert_equal 256, provider.read_attribute_before_type_cast(:digest_method)
    end
  end

  context "digest_method=" do
    test "accepts Integer value" do
      provider = @org.create_saml_provider(@provider_attrs)

      provider.digest_method = 512
      assert provider.save

      assert_equal "http://www.w3.org/2001/04/xmlenc#sha512", provider.digest_method
    end

    test "accepts String value" do
      provider = @org.create_saml_provider(@provider_attrs)

      provider.digest_method = "http://www.w3.org/2001/04/xmlenc#sha512"
      assert provider.save

      assert_equal "http://www.w3.org/2001/04/xmlenc#sha512", provider.digest_method
    end
  end

  context "audit log" do
    test "instruments enabling SAML" do
      events = subscribe "org.enable_saml"

      @org.create_saml_provider(@provider_attrs)

      expected_payload = expected_audit_log_payload_for(@org)

      assert event = events.pop, "an event was expected"
      assert_equal "org.enable_saml", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments disabling SAML" do
      @org.create_saml_provider(@provider_attrs)

      events = subscribe "org.disable_saml"

      @org.saml_provider.destroy

      expected_payload = expected_audit_log_payload_for(@org)

      assert event = events.pop, "an event was expected"
      assert_equal "org.disable_saml", event.name
      assert_equal expected_payload.merge(reason: nil), event.payload
    end

    test "instruments disabling SAML with reason" do
      @org.create_saml_provider(@provider_attrs)

      events = subscribe "org.disable_saml"
      reason = "Testing 1234"

      @org.saml_provider.destroy(reason)

      expected_payload = expected_audit_log_payload_for(@org)

      assert event = events.pop, "an event was expected"
      assert_equal "org.disable_saml", event.name
      assert_equal expected_payload.merge(reason: reason), event.payload
    end

    test "instruments updating SAML provider settings" do
      @org.create_saml_provider(@provider_attrs)

      events = subscribe "org.update_saml_provider_settings"

      @org.saml_provider.update({
        sso_url: "http://other.example.com",
        issuer: "http://other.example.com",
      })

      expected_payload = expected_audit_log_payload_for(@org)

      assert event = events.pop, "an event was expected"
      assert_equal "org.update_saml_provider_settings", event.name
      assert_equal expected_payload, event.payload.except(:changes, :changed)
      assert event.payload.key?(:changes)
      assert event.payload.key?(:changed)
    end

    test "instruments recovery codes generated after generate_recovery! save" do
      @org.create_saml_provider(@provider_attrs)

      events = subscribe "org.recovery_codes_generated"

      @org.saml_provider.generate_recovery!
      @org.saml_provider.save

      assert event = events.pop, "an event was expected"
      assert_equal "org.recovery_codes_generated", event.name
    end

    test "instruments recovery codes generated when saml provider created" do
      events = subscribe "org.recovery_codes_generated"

      @org.create_saml_provider(@provider_attrs)

      assert event = events.pop, "an event was expected"
      assert_equal "org.recovery_codes_generated", event.name
    end
  end

  context "#enforced?" do
    test "returns true when enforced" do
      @org.create_saml_provider(@provider_attrs)

      @org.saml_provider.enforce!

      assert_predicate @org.saml_provider, :enforced?
    end

    test "returns false when not enforced" do
      @org.create_saml_provider(@provider_attrs)

      refute_predicate @org.saml_provider, :enforced?
    end
  end

  test "removes linked external identities when it is destroyed" do
    create(:organization_saml_provider, organization: @org)
    member = create(:user)
    @org.add_member(member)

    create(:external_identity,
      provider: @org.saml_provider,
      user: @org_admin,
    )

    create(:external_identity,
      provider: @org.saml_provider,
      user: member,
    )

    assert ExternalIdentity.linked?(provider: @org.saml_provider, user: @org_admin)
    assert ExternalIdentity.linked?(provider: @org.saml_provider, user: member)

    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
      @org.saml_provider.destroy
    end

    refute ExternalIdentity.linked?(provider: @org.saml_provider, user: @org_admin)
    refute ExternalIdentity.linked?(provider: @org.saml_provider, user: member)
  end

  context "recovery codes" do
    test "generates recovery codes on creation" do
      provider = create(:organization_saml_provider, organization: @org)

      refute_nil provider.secret
      refute_nil provider.recovery_secret
      refute_nil provider.recovery_used_bitfield
      refute_predicate provider, :recovery_codes_viewed?
    end

    test "unused recovery codes can be verified" do
      provider = create(:organization_saml_provider, organization: @org)
      code = provider.recovery_code(0)
      refute provider.recovery_code_used?(0)

      assert_equal true, provider.verify_recovery_code!(code), "Recovery code '#{code}' should be valid"
      assert provider.recovery_code_used?(0)
    end

    test "used recovery codes cannot be verified" do
      provider = create(:organization_saml_provider, organization: @org)
      code = provider.recovery_code(0)
      refute provider.recovery_code_used?(0)

      assert_equal true, provider.verify_recovery_code!(code), "Unused recovery code '#{code}' should be valid"
      assert_equal false, provider.verify_recovery_code!(code), "Used recovery code '#{code}' should NOT be valid"
    end

    test "formatted recovery codes can be verified" do
      provider = create(:organization_saml_provider, organization: @org)
      code = provider.formatted_recovery_codes.first
      refute provider.recovery_code_used?(0)

      assert_equal true, provider.verify_recovery_code!(code), "Recovery code '#{code}' should be valid"
      assert provider.recovery_code_used?(0)
    end
  end

  context "#target" do
    test "finds the associated business account" do
      provider = create(:organization_saml_provider, organization: @org)
      assert_equal @org, provider.target
    end

    test "aliasses to 'organization'" do
      provider = create(:organization_saml_provider, organization: @org)
      provider.reload

      # loading `#organization` should use the same association cache
      # and object as `#target`
      refute provider.association_cached?(:target)
      assert_equal @org, provider.organization
      assert provider.association_cached?(:target)
      assert_equal provider.target, provider.organization
    end
  end

  context "team sync saml settings changed", team_synchronization_available: true do
    test "notifies tenant that saml settings have changed" do
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
                                     idp_certificate: @valid_cert, issuer: @issuer)
      tenant = create(:team_sync_tenant, organization: @saml_org, status: "enabled")

      tenant.expects(:saml_settings_changed).with(provider)
      provider.update(issuer: @new_issuer)
    end

    test "notifies the tenant to disable a tenant that is in pending state" do
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
                                     idp_certificate: @valid_cert, issuer: @issuer)
      create(:team_sync_tenant, organization: @saml_org, status: "pending")
      assert_enqueued_with(job: UpdateTeamSyncTenantJob) do
        provider.update(issuer: @new_issuer)
      end
    end

    test "updates tenant when saml settings are removed" do
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
                                     idp_certificate: @valid_cert, issuer: @issuer)
      create(:team_sync_tenant, organization: @saml_org, status: "enabled")
      assert_enqueued_with(job: UpdateTeamSyncTenantJob) do
        provider.destroy
      end
    end
  end

  context "#scim_provisioning_enabled?" do
    test "returns false" do
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer)
      refute_predicate provider, :scim_provisioning_enabled?
    end
  end

  context "#enterprise_server_scim_enabled?" do
    test "returns false" do
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer)
      refute_predicate provider, :enterprise_server_scim_enabled?
    end
  end

  context "#default_session_expiration" do
    test "returns 1 day from now if FF disabled" do
      GitHub.flipper[:org_saml_session_length_configurable].disable
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer)

      Timecop.freeze do
        assert_equal 1.day.from_now, provider.default_session_expiration
      end
    end

    test "returns 1 day from now if FF enabled and session length not set" do
      GitHub.flipper[:org_saml_session_length_configurable].enable
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer)

      Timecop.freeze do
        assert_equal 1.day.from_now, provider.default_session_expiration
      end
    end

    test "returns session length from now if FF enabled and session length set" do
      GitHub.flipper[:org_saml_session_length_configurable].enable
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer, session_length_in_minutes: 6000)

      Timecop.freeze do
        assert_equal 6000.minutes.from_now, provider.default_session_expiration
      end
    end
  end

  context "session_length_in_minutes validation" do
    test "valid if session_length_in_minutes is integer in bounds" do
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer, session_length_in_minutes: 60)
      assert_predicate provider, :valid?
      assert_equal 60, provider.session_length_in_minutes
    end

    test "valid if session_length_in_minutes is nil" do
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer, session_length_in_minutes: nil)
      assert_predicate provider, :valid?
      assert_nil provider.session_length_in_minutes
    end

    test "valid if session_length_in_minutes is string that can be converted to integer" do
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer, session_length_in_minutes: "60")
      assert_predicate provider, :valid?
      assert_equal 60, provider.session_length_in_minutes
    end

    test "valid if session_length_in_minutes is empty string" do
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer, session_length_in_minutes: "")
      assert_predicate provider, :valid?
      assert_nil provider.session_length_in_minutes
    end

    test "errors if session_length_in_minutes is not an integer" do
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer, session_length_in_minutes: "60not an integer")
      refute_predicate provider, :valid?
      assert_equal ["is not a number"], provider.errors[:session_length_in_minutes]
    end

    test "errors if session_length_in_minutes is less than SESSION_LENGTH_IN_MINUTES_MIN" do
      session_length = Organization::SamlProvider::SESSION_LENGTH_IN_MINUTES_MIN - 1
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer, session_length_in_minutes: session_length)
      refute_predicate provider, :valid?
      assert_equal ["must be greater than or equal to 30"], provider.errors[:session_length_in_minutes]
    end

    test "errors if session_length_in_minutes is greater than SESSION_LENGTH_IN_MINUTES_MAX" do
      session_length = Organization::SamlProvider::SESSION_LENGTH_IN_MINUTES_MAX + 1
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer, session_length_in_minutes: session_length)
      refute_predicate provider, :valid?
      assert_equal ["must be less than or equal to 10080"], provider.errors[:session_length_in_minutes]
    end

    test "errors if session_length_in_minutes is negative" do
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer, session_length_in_minutes: -1)
      refute_predicate provider, :valid?
      assert_equal ["must be greater than or equal to 30"], provider.errors[:session_length_in_minutes]
    end
  end

  context "#session_length_in_minutes?" do
    test "returns false if session_length_in_minutes is nil" do
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer, session_length_in_minutes: nil)
      refute_predicate provider, :session_length_in_minutes?
    end

    test "returns true if session_length_in_minutes is set" do
      provider = @saml_org.create_saml_provider(sso_url: "http://example.com",
        idp_certificate: @valid_cert, issuer: @issuer, session_length_in_minutes: 60)
      assert_predicate provider, :session_length_in_minutes?
    end
  end
end
