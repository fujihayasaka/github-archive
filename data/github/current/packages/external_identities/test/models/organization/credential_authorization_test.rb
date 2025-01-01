# typed: false
# frozen_string_literal: true

require "test_helper"

class OrganizationCredentialAuthorizationTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @org_member = create(:user)
    @org.add_member(@org_member)
    @org_member_token = create(:personal_token_oauth_access, user: @org_member)
    @org_member_allowlisted_token = create(:personal_token_oauth_access, user: @org_member)
    grant organization: @org, credential: @org_member_allowlisted_token, actor: @org_member

    @org_member_public_key = create :public_key, user: @org_member
    @org_member_allowlisted_public_key = create :public_key, user: @org_member
    grant organization: @org, credential: @org_member_allowlisted_public_key, actor: @org_member

    @oauth_access = create :oauth_access
    @app = create :oauth_application, user: @org_member
    @app_access = create :oauth_access, user: @org_member, application: @app

    GitHub.flipper[:sso_audit_log_metadata].disable
  end

  def grant(**kwargs)
    Organization::CredentialAuthorization.grant(**kwargs)
  end

  def grant_in_bulk(**kwargs)
    Organization::CredentialAuthorization.grant_in_bulk(**kwargs)
  end

  def revoke(**kwargs)
    Organization::CredentialAuthorization.revoke(**kwargs)
  end

  def authorization(**kwargs)
    Organization::CredentialAuthorization.authorization(**kwargs)
  end

  def by_credential(**kwargs)
    Organization::CredentialAuthorization.by_credential(**kwargs)
  end

  def generate_request(**kwargs)
    Organization::CredentialAuthorization.generate_request(**kwargs)
  end

  def consume_request(**kwargs)
    Organization::CredentialAuthorization.consume_request(**kwargs)
  end

  def is_resource_internal_or_public?(**kwargs)
    Organization::CredentialAuthorization.is_resource_internal_or_public?(**kwargs)
  end

  def by_resource(**kwargs)
    Organization::CredentialAuthorization.by_resource(**kwargs)
  end

  def event_payload_for(organization:, credential:, actor:)
    {
      org: organization.name,
      org_id: organization.id,
      credential_id: credential.id,
      credential_type: credential.class.name,
      actor: actor.login,
      actor_id: actor.id,
      actor_type: actor.class.name,
    }
  end

  context "validations" do
    test "requires organization" do
      auth = Organization::CredentialAuthorization.new
      auth.valid?

      refute_empty auth.errors[:organization]
    end

    test "requires credential" do
      auth = Organization::CredentialAuthorization.new
      auth.valid?

      refute_empty auth.errors[:credential]
    end

    test "requires the credential to be owned by the actor" do
      auth = Organization::CredentialAuthorization.new organization: @org, credential: @org_member_token, actor: create(:user)
      auth.valid?

      refute_empty auth.errors[:credential]
      assert_includes auth.errors[:credential], "must be owned by actor"
    end

    test "requires the credential to be an OauthAccess or PublicKey" do
      auth = Organization::CredentialAuthorization.new organization: @org, credential: @org_member_public_key, actor: @org_member
      assert_predicate auth, :valid?

      auth = Organization::CredentialAuthorization.new organization: @org, credential: @org_member_token, actor: @org_member
      assert_predicate auth, :valid?

      email = create :user_email, user: @org_member
      auth = Organization::CredentialAuthorization.new organization: @org, credential: email, actor: @org_member

      refute_predicate auth, :valid?
      refute_empty auth.errors[:credential_type]
      assert_includes auth.errors[:credential_type], "must be an OauthAccess or PublicKey"
    end

    test "requires actor" do
      auth = Organization::CredentialAuthorization.new
      auth.valid?

      refute_empty auth.errors[:actor]
    end

    test "requires User actors to be a member of the provided organization when being created" do
      token = create :personal_token_oauth_access
      auth = Organization::CredentialAuthorization.new organization: @org, credential: token, actor: token.user
      auth.valid?

      refute_empty auth.errors[:actor]
      assert_includes auth.errors[:actor], "must be a member of organization"
    end

    test "does not require User actor to be a member of the provided organization when revoking" do
      @org.remove_member!(@org_member)
      auth = authorization(organization: @org, credential: @org_member_allowlisted_public_key)
      auth.update(revoked_by_id: @org.admins.first.id, revoked_at: Time.now)

      assert_empty auth.errors[:actor], "unexpected error: %s" % auth.errors[:actor].inspect
    end

    test "prevents PublicKey credentials that were previously revoked" do
      Organization::CredentialAuthorization.grant(organization: @org, credential: @org_member_public_key, actor: @org_member)
      Organization::CredentialAuthorization.revoke(organization: @org, credential: @org_member_public_key, actor: @org.admins.first)

      auth2 = Organization::CredentialAuthorization.new(organization: @org, credential: @org_member_public_key, actor: @org_member)
      auth2.valid?

      refute_empty auth2.errors[:credential]
      assert_includes auth2.errors[:credential], "has been revoked"
    end
  end

  context "#fingerprint" do
    context "GHEC", skip_enterprise: true, skip_in_multitenant_mode: true do
      test "shortcode is not displayed in fingerprint" do
        emu_user = create :emu
        emu_business = emu_user.enterprise_managed_business
        org = create :organization, business: emu_business
        org.add_member(emu_user)
        public_key = create :public_key, user: emu_user

        authorization = grant(organization: org, credential: public_key, actor: emu_user)

        refute_includes authorization.fingerprint_sha256, "#{emu_business.shortcode}"
        refute_includes authorization.fingerprint, "_#{emu_business.shortcode}"
      end
    end

    context "proxima", skip_enterprise: true do
      test "shortcode is not displayed in fingerprint" do
        on_multi_tenant_enterprise do
          emu_user = create :emu
          emu_business = emu_user.enterprise_managed_business
          GitHub::CurrentTenant.set(emu_business)
          public_key = create :public_key, user: emu_user
          org = create :organization
          org.add_member(emu_user)
          authorization = grant(organization: org, credential: public_key, actor: emu_user)

          assert_includes authorization.fingerprint_sha256, "#{emu_business.shortcode}"
          refute_includes authorization.fingerprint, "_#{emu_business.shortcode}"
        end
      end
    end
  end

  context "#grant" do
    test "succeeds for personal access token" do
      grant(organization: @org, credential: @org_member_token, actor: @org_member)
      assert authorization(organization: @org, credential: @org_member_token)
    end

    test "fails when actor is not the owner of the personal access token" do
      grant(organization: @org, credential: @org_member_token, actor: @org_member)
      refute authorization(organization: @org, credential: create(:personal_token_oauth_access))
    end

    test "fails when actor is not a member of the organization" do
      token = create(:personal_token_oauth_access)
      grant(organization: @org, credential: token, actor: token.user)
      refute authorization(organization: @org, credential: token)
    end

    test "succeeds for oauth application tokens" do
      grant(organization: @org, credential: @oauth_access, actor: @oauth_access.application)
      assert authorization(organization: @org, credential: @oauth_access)
    end

    test "by_credential scope returns multiple tokens" do
      second_token = create(:personal_token_oauth_access, user: @org_member)
      grant(organization: @org, credential: second_token, actor: @org_member)

      authorizations = by_credential(credential: @org_member.oauth_accesses.to_a)
      assert_same_elements \
        [@org_member_allowlisted_token, second_token],
        authorizations.map(&:credential)
    end

    test "does nothing when a credential is already authorized" do
      assert_equal 0, by_credential(credential: @org_member_token).size
      grant(organization: @org, credential: @org_member_token, actor: @org_member)
      assert_equal 1, by_credential(credential: @org_member_token).size

      grant(organization: @org, credential: @org_member_token, actor: @org.admin)
      assert_equal 1, by_credential(credential: @org_member_token).size
    end

    test "does nothing when a credential has been revoked" do
      grant(organization: @org, credential: @org_member_token, actor: @org_member)
      assert authorization(organization: @org, credential: @org_member_token)

      revoke(organization: @org, credential: @org_member_token, actor: @org.admin)
      refute authorization(organization: @org, credential: @org_member_token)

      grant(organization: @org, credential: @org_member_token, actor: @org.admin)
      refute authorization(organization: @org, credential: @org_member_token)
    end

    test "instruments grants in audit log" do
      expected_key = "org_credential_authorization.grant"
      events = subscribe(expected_key)
      expected_payload = event_payload_for(organization: @org, credential: @org_member_token, actor: @org_member)

      grant(organization: @org, credential: @org_member_token, actor: @org_member)

      assert_equal 1, events.size
      event = events.pop

      assert_equal expected_payload, event.payload
    end

    test "instruments revocations in audit log" do
      grant(organization: @org, credential: @org_member_token, actor: @org_member)

      events = subscribe "org_credential_authorization.revoke"
      expected_payload = event_payload_for(organization: @org, credential: @org_member_token, actor: @org.admin)
      expected_payload[:owner] = @org_member.login
      expected_payload[:owner_id] = @org_member.id

      revoke(organization: @org, credential: @org_member_token, actor: @org.admin)

      assert_equal 1, events.size
      event = events.pop

      assert_equal expected_payload, event.payload
    end

    test "instruments deauthorization in audit log" do
      authorization = grant(organization: @org, credential: @org_member_token, actor: @org_member)

      events = subscribe "org_credential_authorization.deauthorize"
      expected_payload = event_payload_for(organization: @org, credential: @org_member_token, actor: @org_member)

      authorization.destroy

      assert_equal 1, events.size
      event = events.pop

      assert_equal expected_payload, event.payload
    end

    test "instruments classic PAT metadata in audit log with flag enabled" do
      GitHub.flipper[:sso_audit_log_metadata].enable

      expected_key = "org_credential_authorization.grant"
      events = subscribe(expected_key)
      token = create(:personal_token_oauth_access, user: @org_member)
      token.set_random_token_pair

      expected_payload = event_payload_for(organization: @org, credential: token, actor: @org_member)
      expected_payload[:oauth_credential_type] = "Personal Access Token"
      expected_payload[:oauth_access_id] = token.id
      expected_payload[:oauth_scopes] = token.scopes_string
      expected_payload[:token_id] = token.id
      expected_payload[:token_scopes] = token.scopes_string
      expected_payload[:hashed_token] = token.hashed_token

      grant(organization: @org, credential: token, actor: @org_member)

      assert_equal 1, events.size
      event = events.pop

      assert_equal expected_payload, event.payload
    end

    test "instruments OAuth token metadata in audit log with flag enabled" do
      GitHub.flipper[:sso_audit_log_metadata].enable

      expected_key = "org_credential_authorization.grant"
      events = subscribe(expected_key)
      token = create :oauth_access
      app = create :oauth_application, user: @org_member
      app_access = create :oauth_access, user: @org_member, application: app
      app_access.set_random_token_pair

      expected_payload = event_payload_for(organization: @org, credential: app_access, actor: @org_member)
      expected_payload[:oauth_credential_type] = "OauthAccess"
      expected_payload[:oauth_access_id] = app_access.id
      expected_payload[:oauth_scopes] = app_access.scopes_string
      expected_payload[:token_id] = app_access.id
      expected_payload[:token_scopes] = app_access.scopes_string
      expected_payload[:hashed_token] = app_access.hashed_token

      grant(organization: @org, credential: app_access, actor: @org_member)

      assert_equal 1, events.size
      event = events.pop

      assert_equal expected_payload, event.payload
    end

    test "instruments public key metadata in audit log with flag enabled" do
      GitHub.flipper[:sso_audit_log_metadata].enable

      expected_key = "org_credential_authorization.grant"
      events = subscribe(expected_key)
      public_key = create :public_key, user: @org_member

      expected_payload = event_payload_for(organization: @org, credential: public_key, actor: @org_member)
      expected_payload[:fingerprint] = public_key.fingerprint
      expected_payload.delete(:oauth_credential_type)

      grant(organization: @org, credential: public_key, actor: @org_member)

      assert_equal 1, events.size
      event = events.pop

      assert_equal expected_payload, event.payload
    end

    test "does not instrument classic PAT metadata in audit log with flag disabled" do
      GitHub.flipper[:sso_audit_log_metadata].disable

      expected_key = "org_credential_authorization.grant"
      events = subscribe(expected_key)
      token = create(:personal_token_oauth_access, user: @org_member)
      token.set_random_token_pair

      expected_payload = event_payload_for(organization: @org, credential: token, actor: @org_member)
      grant(organization: @org, credential: token, actor: @org_member)

      assert_equal 1, events.size
      event = events.pop

      assert_equal expected_payload, event.payload
      assert_nil event.payload[:fingerprint]
    end

    test "does not instrument OAuth token metadata in audit log with flag disabled" do
      GitHub.flipper[:sso_audit_log_metadata].disable

      expected_key = "org_credential_authorization.grant"
      events = subscribe(expected_key)
      token = create :oauth_access
      app = create :oauth_application, user: @org_member
      app_access = create :oauth_access, user: @org_member, application: app
      app_access.set_random_token_pair

      expected_payload = event_payload_for(organization: @org, credential: app_access, actor: @org_member)
      grant(organization: @org, credential: app_access, actor: @org_member)

      assert_equal 1, events.size
      event = events.pop

      assert_equal expected_payload, event.payload
      assert_nil event.payload[:fingerprint]
    end

    test "does not instrument public key metadata in audit log with flag disabled" do
      GitHub.flipper[:sso_audit_log_metadata].disable

      expected_key = "org_credential_authorization.grant"
      events = subscribe(expected_key)
      public_key = create :public_key, user: @org_member

      expected_payload = event_payload_for(organization: @org, credential: public_key, actor: @org_member)
      grant(organization: @org, credential: public_key, actor: @org_member)

      assert_equal 1, events.size
      event = events.pop

      assert_equal expected_payload, event.payload
      assert_nil event.payload[:fingerprint]
    end

    test "is_application is set correctly for authorization", skip_enterprise: true do
      token_auth = grant(organization: @org, credential: @org_member_token, actor: @org_member)
      refute token_auth.is_application

      app_auth = grant(organization: @org, credential: @app_access, actor: @org_member)
      assert app_auth.is_application
    end

    test "excluding_applications scope filters applications", skip_enterprise: true do
      app_auth = grant(organization: @org, credential: @app_access, actor: @org_member)
      token_auth = grant(organization: @org, credential: @org_member_token, actor: @org_member)

      credentials_query = Organization::CredentialAuthorization
        .by_organization(organization: @org)
        .active
        .pluck(:id)
      assert_includes credentials_query, app_auth.id
      assert_includes credentials_query, token_auth.id

      credentials_query = Organization::CredentialAuthorization
        .by_organization(organization: @org)
        .active
        .excluding_applications
        .pluck(:id)
      refute_includes credentials_query, app_auth.id
      assert_includes credentials_query, token_auth.id
    end
  end

  context "#grant_in_bulk" do
    test "succeeds for personal access token" do
      org2 = create(:organization)
      org2.add_member(@org_member)

      refute authorization(organization: @org, credential: @org_member_token)
      refute authorization(organization: org2, credential: @org_member_token)

      grant_in_bulk(organizations: [@org, org2], credential: @org_member_token, actor: @org_member)

      assert authorization(organization: @org, credential: @org_member_token)
      assert authorization(organization: org2, credential: @org_member_token)
    end

    test "fails when actor is not the owner of the personal access token" do
      grant_in_bulk(organizations: [@org], credential: @org_member_token, actor: @org_member)
      refute authorization(organization: @org, credential: create(:personal_token_oauth_access))
    end

    test "fails when actor is not a member of the organization" do
      token = create(:personal_token_oauth_access)
      grant_in_bulk(organizations: [@org], credential: token, actor: token.user)
      refute authorization(organization: @org, credential: token)
    end

    test "succeeds for oauth application tokens" do
      grant_in_bulk(organizations: [@org], credential: @oauth_access, actor: @oauth_access.application)
      assert authorization(organization: @org, credential: @oauth_access)
    end

    test "does nothing when a credential is already authorized" do
      assert_equal 0, by_credential(credential: @org_member_token).size
      grant_in_bulk(organizations: [@org], credential: @org_member_token, actor: @org_member)
      assert_equal 1, by_credential(credential: @org_member_token).size

      grant_in_bulk(organizations: [@org], credential: @org_member_token, actor: @org.admin)
      assert_equal 1, by_credential(credential: @org_member_token).size
    end

    test "does nothing when a credential has been revoked" do
      grant_in_bulk(organizations: [@org], credential: @org_member_token, actor: @org_member)
      assert authorization(organization: @org, credential: @org_member_token)

      revoke(organization: @org, credential: @org_member_token, actor: @org.admin)
      refute authorization(organization: @org, credential: @org_member_token)

      grant_in_bulk(organizations: [@org], credential: @org_member_token, actor: @org.admin)
      refute authorization(organization: @org, credential: @org_member_token)
    end

    test "instruments grants in audit log" do
      GitHub.flipper[:use_instrument_bulk_credential_authorization_grants_job].disable
      expected_key = "org_credential_authorization.grant"
      events = subscribe(expected_key)
      expected_payload = event_payload_for(organization: @org, credential: @org_member_token, actor: @org_member)

      grant_in_bulk(organizations: [@org], credential: @org_member_token, actor: @org_member)

      assert_equal 1, events.size
      event = events.pop

      assert_equal expected_payload, event.payload
    end

    test "queues background jobs to handle grant instrumentation when :use_instrument_bulk_credential_authorization_grants_job falg is enabled" do
      GitHub.flipper[:use_instrument_bulk_credential_authorization_grants_job].enable

      expected_key = "org_credential_authorization.grant"
      events = subscribe(expected_key)
      expected_payload = event_payload_for(organization: @org, credential: @org_member_token, actor: @org_member)

      perform_enqueued_jobs(only: [InstrumentBulkCredentialAuthorizationGrantsJob]) do
        grant_in_bulk(organizations: [@org], credential: @org_member_token, actor: @org_member)
      end

      assert_performed_jobs(1, only: InstrumentBulkCredentialAuthorizationGrantsJob)

      assert_equal 1, events.size
      event = events.pop

      assert_equal expected_payload, event.payload
    end

    test "when credential is deleted instrumentation job runs without error" do
      GitHub.flipper[:use_instrument_bulk_credential_authorization_grants_job].enable

      expected_key = "org_credential_authorization.grant"
      events = subscribe(expected_key)

      grant_in_bulk(organizations: [@org], credential: @org_member_token, actor: @org_member)
      perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
        @org_member_token.destroy
      end

      perform_enqueued_jobs(only: InstrumentBulkCredentialAuthorizationGrantsJob)

      assert_performed_jobs(1, only: InstrumentBulkCredentialAuthorizationGrantsJob)
      assert_equal 0, events.size
    end

    test "is_application is set correctly for authorization", skip_enterprise: true do
      grant_in_bulk(organizations: [@org], credential: @org_member_token, actor: @org_member)

      token_auth = authorization(organization: @org, credential: @org_member_token)
      refute_predicate token_auth, :is_application?

      grant_in_bulk(organizations: [@org], credential: @app_access, actor: @org_member)

      app_auth = authorization(organization: @org, credential: @app_access)
      assert_predicate app_auth, :is_application?
    end

    test "fingerprint_sha256 is set correctly for public keys" do
      grant_in_bulk(organizations: [@org], credential: @org_member_public_key, actor: @org_member)

      authorization = authorization(organization: @org, credential: @org_member_public_key)
      refute_nil authorization

      assert_equal @org_member_public_key.fingerprint_sha256, authorization.fingerprint_sha256
    end
  end

  context "#revoke" do
    test "succeeds for personal access token" do
      revoke(organization: @org, credential: @org_member_allowlisted_token, actor: @org_member)
      refute authorization(organization: @org, credential: @org_member_allowlisted_token)
    end

    test "fails when actor is not the owner of the personal access token" do
      revoke(organization: @org, credential: @org_member_allowlisted_token, actor: create(:user))
      assert authorization(organization: @org, credential: @org_member_allowlisted_token)
    end

    test "succeeds when actor is an organization admin" do
      revoke(organization: @org, credential: @org_member_allowlisted_token, actor: @org.admins.first)
      refute authorization(organization: @org, credential: @org_member_allowlisted_token)
    end

    test "succeeds for GitHub App installations with the proper permissions" do
      installation = make_integration_installation(target: @org, permissions: { "organization_administration" => :write })

      revoke(organization: @org, credential: @org_member_allowlisted_token, actor: installation.bot)
      refute authorization(organization: @org, credential: @org_member_allowlisted_token)
    end

    test "fails when the GitHub App installation does not have permission" do
      installation = make_integration_installation(target: @org, permissions: { "organization_administration" => :read })

      revoke(organization: @org, credential: @org_member_allowlisted_token, actor: installation.bot)
      assert authorization(organization: @org, credential: @org_member_allowlisted_token)
    end

    test "succeeds when actor is an organization admin and credential owner has been removed from organization" do
      @org.remove_member! @org_member
      revoke(organization: @org, credential: @org_member_allowlisted_public_key, actor: @org.admins.first)
      refute authorization(organization: @org, credential: @org_member_allowlisted_public_key)
    end

    test "does nothing when the credential has already been revoked" do
      revoke(organization: @org, credential: @org_member_allowlisted_token, actor: @org.admins.first)
      revoke(organization: @org, credential: @org_member_allowlisted_token, actor: @org.admins.first)
      refute authorization(organization: @org, credential: @org_member_allowlisted_token)
    end

    test "succeeds if org is enterprise managed and actor is enterprise admin", skip_enterprise: true do
      emu_owner = create :emu, :owner
      business = emu_owner.enterprise_managed_business
      emu = create :emu, business: business
      org = create :organization, business: business
      org.add_member(emu)

      org_member_token = create :personal_token_oauth_access, user: emu
      org_member_public_key = create :public_key, user: emu

      grant organization: org, credential: org_member_token, actor: emu
      grant organization: org, credential: org_member_public_key, actor: emu

      revoke(organization: org, credential: org_member_token, actor: emu_owner)
      revoke(organization: org, credential: org_member_public_key, actor: emu_owner)

      refute authorization(organization: org, credential: org_member_token)
      refute authorization(organization: org, credential: org_member_public_key)
    end
  end

  context ".generate_request" do
    test "creates a GitHub::Authentication::SignedAuthToken string for OAuth tokens" do
      Timecop.freeze do
        expected_token = @org_member.signed_auth_token(
          scope: "saml:authorized_credential:#{@org.class.name}:#{@org.id}",
          expires: 1.hour.from_now,
          data: {
            organization_id: @org.id,
            credential_id: @org_member_token.id,
            credential_type: @org_member_token.class.name,
          },
        )
        actual_token = generate_request(organization: @org, target: @org, credential: @org_member_token, actor: @org_member)

        assert_equal expected_token, actual_token
      end
    end

    test "creates a GitHub::Authentication::SignedAuthToken string for SSH keys" do
      Timecop.freeze do
        expected_token = @org_member.signed_auth_token(
          scope: "saml:authorized_credential:#{@org.class.name}:#{@org.id}",
          expires: 1.hour.from_now,
          data: {
            organization_id: @org.id,
            credential_id: @org_member_public_key.id,
            credential_type: @org_member_public_key.class.name,
          },
        )
        actual_token = generate_request(organization: @org, target: @org, credential: @org_member_public_key, actor: @org_member)

        assert_equal expected_token, actual_token
      end
    end

    test "creates a GitHub::Authentication::SignedAuthToken string scoped to a business" do
      Timecop.freeze do
        business = create :business, organizations: [@org]
        expected_token = @org_member.signed_auth_token(
          scope: "saml:authorized_credential:#{business.class.name}:#{business.id}",
          expires: 1.hour.from_now,
          data: {
            organization_id: @org.id,
            credential_id: @org_member_public_key.id,
            credential_type: @org_member_public_key.class.name,
          },
        )
        actual_token = generate_request(organization: @org, target: business, credential: @org_member_public_key, actor: @org_member)

        assert_equal expected_token, actual_token
      end
    end
  end

  context ".consume_request" do
    test "parses a GitHub::Authentication::SignedAuthToken to get an OAuth token for allowlisting" do
      token = generate_request(organization: @org, target: @org, credential: @org_member_token, actor: @org_member)
      parsed_token = consume_request(target: @org, token: token, actor: @org_member)

      assert_predicate parsed_token, :valid?
      assert_equal @org_member, parsed_token.user
      assert_equal @org_member_token.id, parsed_token.data["credential_id"]
      assert_equal "OauthAccess", parsed_token.data["credential_type"]
      assert_equal @org.id, parsed_token.data["organization_id"]
    end

    test "parses a GitHub::Authentication::SignedAuthToken to get an SSH key for allowlisting" do
      token = generate_request(organization: @org, target: @org, credential: @org_member_public_key, actor: @org_member)
      parsed_token = consume_request(target: @org, token: token, actor: @org_member)

      assert_predicate parsed_token, :valid?
      assert_equal @org_member, parsed_token.user
      assert_equal @org_member_public_key.id, parsed_token.data["credential_id"]
      assert_equal "PublicKey", parsed_token.data["credential_type"]
      assert_equal @org.id, parsed_token.data["organization_id"]
    end

    test "parses a GitHub::Authentication::SignedAuthToken scoped to a business" do
      business = create :business, organizations: [@org]
      token = generate_request(organization: @org, target: business, credential: @org_member_public_key, actor: @org_member)
      parsed_token = consume_request(target: business, token: token, actor: @org_member)

      assert_predicate parsed_token, :valid?
      assert_equal @org_member, parsed_token.user
      assert_equal @org_member_public_key.id, parsed_token.data["credential_id"]
      assert_equal "PublicKey", parsed_token.data["credential_type"]
      assert_equal @org.id, parsed_token.data["organization_id"]
    end

    test "returns nothing if the token has expired" do
      token = generate_request(organization: @org, target: @org, credential: @org_member_token, actor: @org_member)

      Timecop.travel(61.minutes.from_now) do
        request = consume_request(target: @org, token: token, actor: @org_member)

        assert_nil request
      end
    end

    test "returns nothing if the users don't match up" do
      token = generate_request(organization: @org, target: @org, credential: @org_member_token, actor: @org_member)
      request = consume_request(target: @org, token: token, actor: create(:user))

      assert_nil request
    end

    test "returns nothing if the organizations don't match up" do
      token = generate_request(organization: @org, target: @org, credential: @org_member_token, actor: @org_member)
      request = consume_request(target: create(:organization), token: token, actor: @org_member)

      assert_nil request
    end
  end

  context ".by_resource" do
    test "returns credentials for an internal resource in the same business and another org" do
      business = create(:business)
      business.add_organization(@org)
      org_with_resource = create(:business_plus_organization, business: business)
      internal_repo = create(:internal_repository, owner: org_with_resource, from_example: :simple)

      authorized_credentials = Organization::CredentialAuthorization.by_resource(
        credential: @org_member_allowlisted_token,
        resource: Platform::InternalResource.new(resource: org_with_resource),
        repo: internal_repo,
        org: org_with_resource
      )
      assert_equal 1, authorized_credentials.count
      assert_equal @org.id, authorized_credentials.last.organization_id
    end

    test "does not return credentials for an internal resource on another business", skip_enterprise: true do
      business = create(:business)
      business.add_organization(@org)
      business_with_resource = create(:business)
      org_with_resource = create(:business_plus_organization, business: business_with_resource)
      internal_repo = create(:internal_repository, owner: org_with_resource, from_example: :simple)

      authorized_credentials = Organization::CredentialAuthorization.by_resource(
        credential: @org_member_allowlisted_token,
        resource: Platform::InternalResource.new(resource: org_with_resource),
        repo: internal_repo,
        org: org_with_resource
      )
      assert_equal 0, authorized_credentials.count
    end

    test "Does not return credentials for a private resource in the same business and another org" do
      GitHub.flipper[:sso_same_business_cred_authz_private_repos].disable
      business = create(:business)
      business.add_organization(@org)
      org_with_resource = create(:business_plus_organization, business: business)
      private_repo = create(:private_repository, owner: org_with_resource, from_example: :simple)

      authorized_credentials = Organization::CredentialAuthorization.by_resource(
        credential: @org_member_allowlisted_token,
        resource: private_repo,
        repo: private_repo,
        org: org_with_resource
      )
      assert_equal 0, authorized_credentials.count
    end
  end

  context ".is_resource_internal_or_public?" do
    test "returns true for public repository" do
      public_repo = create(:public_repository, owner: @org)
      assert is_resource_internal_or_public?(resource: public_repo, org: @org)
    end

    test "returns true for internal repository" do
      business = create(:business)
      business.add_organization(@org)
      internal_repo = create(:internal_repository, owner: @org)
      assert is_resource_internal_or_public?(resource: internal_repo, org: @org)
    end

    test "returns false for private repository" do
      private_repo = create(:private_repository, owner: @org)
      assert_not is_resource_internal_or_public?(resource: private_repo, org: @org)
    end

    test "returns true for public integration" do
      integration = create(:integration, name: "super-ci")
      assert integration.public?
      assert is_resource_internal_or_public?(resource: integration, org: @org)
    end

    test "returns false for private integration" do
      integration = create(:integration, visibility: "private_visibility", name: "Great App", owner: @org, url: "http://great-app.com")
      assert_not integration.public?
      assert_not is_resource_internal_or_public?(resource: integration, org: @org)
    end

    test "returns true for public memex project" do
      memex = create(:memex_project, public: true, owner: @org)
      assert is_resource_internal_or_public?(resource: memex, org: @org)
    end

    test "returns true for org-owned memex project owned in same business" do
      business = create(:business)
      business.add_organization(@org)
      memex = create(:memex_project, public: false, owner: @org)
      assert is_resource_internal_or_public?(resource: memex, org: @org)
    end

    test "returns false for not public memex project" do
      memex = create(:memex_project, public: false, owner: @org)
      assert_not is_resource_internal_or_public?(resource: memex, org: @org)
    end

    test "returns true for public platform resource" do
      public_resource = Platform::PublicResource.new(resource: @org)
      assert is_resource_internal_or_public?(resource: public_resource, org: @org)
    end

    test "returns true for internal platform resource" do
      internal_resource = Platform::InternalResource.new(resource: @org)
      assert is_resource_internal_or_public?(resource: internal_resource, org: @org)
    end

    test "returns false for nil resource" do
      assert_not is_resource_internal_or_public?(resource: nil, org: @org)
    end
  end
end
