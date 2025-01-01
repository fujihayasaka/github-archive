# typed: true
# frozen_string_literal: true

require "test_helper"

class OauthAccess::ProviderTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @integration = create(:integration, owner: @user)
    @application = create(:oauth_application, user: @user)
  end

  context "#access_for_code" do
    test "clears the code on successful find when the feature is enabled" do
      Timecop.freeze do
        access = @integration.grant(@user, entry_point: :test_case)
        refute_nil access.code

        found_record = @integration.access_for_code(access.code)
        access.reload

        assert_equal access, found_record
        assert_nil access.code
      end
    end

    test "does not raise an error if an emoji is provided as part of the code" do
      assert_nothing_raised do
        @integration.access_for_code("foo 🤪")
      end
    end
  end

  context "OauthApplication" do
    test "creates an access for the user, with a code" do
      access = @application.grant(@user, entry_point: :test_case)
      assert_equal @user, access.user
      assert_equal @application, access.application
      assert_nil access.hashed_token
      assert_nil access.token_last_eight
      assert_empty access.scopes
      assert access.code
    end

    test "doesn't change an old access" do
      old_access = @application.grant(@user, entry_point: :test_case)
      access = @application.grant(@user, entry_point: :test_case)

      refute_equal old_access, access
    end

    test "canset scopes for an Integration access" do
      access = @application.grant(@user, scope: "user", entry_point: :test_case)

      assert_equal @user, access.user
      assert_equal @application, access.application
      assert_equal ["user"], access.scopes
    end

    test "persists redirect_uri when its passed" do
      access = @application.grant(@user, redirect_uri: "http://redirect.me", entry_point: :test_case)
      assert_equal "http://redirect.me", access.requested_redirect_uri
    end
  end

  context "Integration" do
    context "#grant" do
      test "creates an access for the user, with a code" do
        access = @integration.grant(@user, entry_point: :test_case)
        assert_equal @user, access.user
        assert_equal @integration, access.application
        assert_nil access.hashed_token
        assert_nil access.token_last_eight
        assert_empty access.scopes
        assert access.code
      end

      test "doesn't change an old access" do
        old_access = @integration.grant(@user, entry_point: :test_case)
        access = @integration.grant(@user, entry_point: :test_case)

        refute_equal old_access, access
      end

      test "cannot set scopes for an Integration access" do
        access = @integration.grant(@user, scope: "user", entry_point: :test_case)

        assert_equal @user, access.user
        assert_equal @integration, access.application
        assert_empty access.scopes
      end

      test "persists redirect_uri when its passed" do
        access = @integration.grant(@user, redirect_uri: "http://redirect.me", entry_point: :test_case)
        assert_equal "http://redirect.me", access.requested_redirect_uri
      end
    end

    context "#grant_scoped_access_from" do
      test "returns an :invalid_token error if a scoped access tries to make another scoped access" do
        integration = create(:integration, default_permissions: { "metadata" => :read })
        make_integration_installation(integration: integration, target: @user)

        access = integration.grant(@user, entry_point: :test_case)

        new_access, error_response = integration.grant_scoped_access_from(access, @user, entry_point: :test_case)
        assert_nil error_response

        _, error_response = integration.grant_scoped_access_from(new_access, @user, entry_point: :test_case)

        assert_equal :invalid_token,                                                  error_response[:error]
        assert_equal "A scoped token cannot create another scoped token.",            error_response[:error_description]
        assert_equal "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/", error_response[:error_uri]
      end

      test "returns a :sso_required error if the target is SAML protected" do
        external_identity_session = create(:external_identity_session)
        organization = external_identity_session.external_identity.provider.organization
        session      = external_identity_session.user_session
        user         = session.user

        repo = create(:repository, :minimal, owner: organization)

        integration  = create(:integration, default_permissions: { "metadata" => :read })
        make_integration_installation(integration: integration, repository: repo)

        access = integration.grant(user, entry_point: :test_case)
        assert_nil Organization::CredentialAuthorization.find_by(organization: organization, credential: access, actor: user)

        new_access, error_response = integration.grant_scoped_access_from(access, organization, entry_point: :test_case)

        assert_nil new_access

        assert_equal :sso_required,                                                   error_response[:error]
        assert_equal "Resource protected by Organization SAML enforcement",           error_response[:error_description]
        assert_equal "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/", error_response[:error_uri]
      end

      test "does not return a :sso_required error if the app ignores SAML protection" do
        external_identity_session = create(:external_identity_session)
        organization = external_identity_session.external_identity.provider.organization
        session      = external_identity_session.user_session
        user         = session.user

        repo = create(:repository, :minimal, owner: organization)

        integration = create_internal_app_with_capabilities(capabilities: { saml_sso_required: false })
        make_integration_installation(integration: integration, repository: repo)

        access = integration.grant(user, entry_point: :test_case)
        assert_nil Organization::CredentialAuthorization.find_by(organization: organization, credential: access, actor: user)

        _, error_response = integration.grant_scoped_access_from(access, organization, entry_point: :test_case)
        assert_nil error_response
      end

      test "creates credentials authorization for authorized SAML organization" do
        user = create(:user)
        session = create(:user_session, user: user)

        org = create(:organization, billing_type: "invoice", plan: "business_plus")
        org.add_member(user)

        saml_provider = create(:organization_saml_provider, organization: org)
        saml_provider.enforce!
        assert_equal saml_provider, org.saml_provider
        assert_predicate org, :saml_sso_enabled?

        external_identity = create(:external_identity, user: user, provider: saml_provider)
        create(:external_identity_session, user_session: session, external_identity: external_identity)

        repo = create(:repository, :minimal, owner: org)

        integration  = create_internal_app_with_capabilities(capabilities: { per_repo_user_to_server_tokens: true })
        make_integration_installation(integration: integration, repository: repo)

        assert_difference "Organization::CredentialAuthorization.count", 1 do
          integration.grant(user, user_session: session, entry_point: :test_case)
        end
      end

      test "does not create credentials authorization when SAML policy is not met" do
        user = create(:user)
        session = create(:user_session, user: user)

        org = create(:organization, billing_type: "invoice", plan: "business_plus")
        org.add_member(user)

        saml_provider = create(:organization_saml_provider, organization: org)
        saml_provider.enforce!
        assert_equal saml_provider, org.saml_provider
        assert_predicate org, :saml_sso_enabled?

        repo = create(:repository, :minimal, owner: org)

        integration  = create_internal_app_with_capabilities(capabilities: { per_repo_user_to_server_tokens: true })
        make_integration_installation(integration: integration, repository: repo)

        assert_difference "Organization::CredentialAuthorization.count", 0 do
          integration.grant(user, user_session: session, entry_point: :test_case)
        end
      end

      test "does not create credentials if organization does not have SAML enabled" do
        user = create(:user)
        session = create(:user_session, user: user)

        org = create(:organization, billing_type: "invoice", plan: "business_plus")
        org.add_member(user)

        repo = create(:repository, :minimal, owner: org)

        integration  = create_internal_app_with_capabilities(capabilities: { per_repo_user_to_server_tokens: true })
        make_integration_installation(integration: integration, repository: repo)

        assert_difference "Organization::CredentialAuthorization.count", 0 do
          integration.grant(user, user_session: session, entry_point: :test_case)
        end
      end

      context "ScopedIntegrationInstallation" do
        test "returns a :missing_installation error if there isn't a parent installaton on the target" do
          rando = create(:user)
          integration = create(:integration, default_permissions: { "metadata" => :read })

          access = integration.grant(rando, entry_point: :test_case)
          _, error_response = integration.grant_scoped_access_from(access, rando, entry_point: :test_case)

          assert_equal :installation_missing_access,                                    error_response[:error]
          assert_equal "Your app does not have access to the given target.",            error_response[:error_description]
          assert_equal "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/", error_response[:error_uri]
        end

        test "sets an installation on the access" do
          repo = create(:repository, :minimal, owner: @user)

          integration  = create(:integration, default_permissions: { "metadata" => :read })
          installation = make_integration_installation(integration: integration, target: @user)

          access = integration.grant(@user, entry_point: :test_case)
          new_access, error_response = integration.grant_scoped_access_from(access, @user, entry_point: :test_case)

          assert_nil error_response

          assert_kind_of ScopedIntegrationInstallation, new_access.installation
          assert_equal installation, new_access.installation.parent
          assert_equal [repo], installation.repositories.to_a
        end

        test "sets the expiry to match the access refresh token" do
          Timecop.freeze do
            repo = create(:repository, :minimal, owner: @user)

            integration  = create_internal_app_with_capabilities(capabilities: { per_repo_user_to_server_tokens: true })
            integration.update(user_token_expiration: true); integration.reload

            installation = make_integration_installation(integration: integration, target: @user)

            access = integration.grant(@user, entry_point: :test_case)
            new_access, error_response = integration.grant_scoped_access_from(access, @user, entry_point: :test_case)

            assert_nil error_response

            new_access.redeem; new_access.reload

            new_installation = new_access.installation
            refresh_token = new_access.refresh_token

            assert_kind_of ScopedIntegrationInstallation, new_installation
            assert_equal installation, new_installation.parent
            assert_equal [repo], new_installation.repositories.to_a

            assert_in_delta refresh_token.expires_at, new_installation.expires_at

            new_installation.abilities.each do |record|
              assert_in_delta refresh_token.expires_at, record.expires_at
            end
          end
        end

        test "does not change the expiry when the access does not expire" do
          Timecop.freeze do
            repo = create(:repository, :minimal, owner: @user)

            integration = create_internal_app_with_capabilities(capabilities: { per_repo_user_to_server_tokens: true })
            integration.update(user_token_expiration: false); integration.reload

            installation = make_integration_installation(integration: integration, target: @user)

            access = integration.grant(@user, entry_point: :test_case)
            new_access, error_response = integration.grant_scoped_access_from(access, @user, entry_point: :test_case)

            assert_nil error_response

            new_installation = new_access.installation

            assert_equal 0, new_installation.expires_at.to_i

            new_access.redeem; new_access.reload
            new_installation.reload

            assert_kind_of ScopedIntegrationInstallation, new_installation
            assert_equal installation, new_installation.parent
            assert_equal [repo], new_installation.repositories.to_a

            assert_equal 0, new_installation.expires_at.to_i

            new_installation.abilities.each do |record|
              assert_equal 0, record.expires_at.to_i
            end
          end
        end

        test "returns an :installation_creation_failed if unauthorized permissions were requested" do
          integration  = create(:integration, default_permissions: { "metadata" => :read })
          make_integration_installation(integration: integration, target: @user)

          access = integration.grant(@user, entry_point: :test_case)
          scoped_installation, error_response = integration.grant_scoped_access_from(access, @user, permissions: { "metadata" => :read, "issues" => :write }, entry_point: :test_case)

          assert_nil scoped_installation

          assert_equal :installation_creation_failed,                                     error_response[:error]
          assert_equal "The permissions requested are not granted to this installation.", error_response[:error_description]
          assert_equal "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/",   error_response[:error_uri]
        end

        test "returns an :installation_creation_failed when unauthorized repositories were requested" do
          integration  = create(:integration, default_permissions: { "metadata" => :read })

          repo1 = create(:repository, :minimal, owner: @user)
          repo2 = create(:repository, :minimal, owner: @user)

          make_integration_installation(integration: integration, repository: repo1)

          access = integration.grant(@user, entry_point: :test_case)
          scoped_installation, error_response = integration.grant_scoped_access_from(access, @user, resources: { repository_ids: [repo1.id, repo2.id] }, entry_point: :test_case)

          assert_nil scoped_installation

          assert_equal :installation_creation_failed,                                                                           error_response[:error]
          assert_equal "There is at least one repository that does not exist or is not accessible to the parent installation.", error_response[:error_description]
          assert_equal "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/",      error_response[:error_uri]
        end
      end

      context "SiteScopedIntegrationInstallation" do
        test "creates a new access and sets an installation" do
          integration = create_unlimited_global_integration
          GitHub.flipper[:disabled_global_apps].disable(integration)

          access = integration.grant(@user, entry_point: :test_case)
          new_access, error_response = integration.grant_scoped_access_from(access, @user, entry_point: :test_case)

          assert_nil error_response

          refute_nil new_access.installation
          assert_kind_of SiteScopedIntegrationInstallation, new_access.installation
          assert_predicate new_access.installation, :installed_on_all_repositories?
        end

        test "sets the expiry to match the access if the access expires" do
          Timecop.freeze do
            integration = create_unlimited_global_integration(capabilities: { per_repo_user_to_server_tokens: true })
            GitHub.flipper[:disabled_global_apps].disable(integration)

            integration.update(user_token_expiration: true); integration.reload

            access = integration.grant(@user, entry_point: :test_case)
            new_access, error_response = integration.grant_scoped_access_from(access, @user, entry_point: :test_case)

            assert_nil error_response

            new_access.redeem; new_access.reload

            new_installation = new_access.installation
            refresh_token = new_access.refresh_token

            assert_kind_of SiteScopedIntegrationInstallation, new_installation
            assert_predicate new_access.installation, :installed_on_all_repositories?

            assert_in_delta refresh_token.expires_at, new_installation.expires_at

            new_installation.abilities.each do |record|
              assert_in_delta refresh_token.expires_at, record.expires_at
            end
          end
        end

        test "does not change the expiry if the access does not expire" do
          Timecop.freeze do
            integration = create_unlimited_global_integration(capabilities: { per_repo_user_to_server_tokens: true })
            GitHub.flipper[:disabled_global_apps].disable(integration)

            integration.update(user_token_expiration: false); integration.reload

            access = integration.grant(@user, entry_point: :test_case)
            new_access, error_response = integration.grant_scoped_access_from(access, @user, entry_point: :test_case)

            assert_nil error_response

            new_installation = new_access.installation

            # By default we set the expiration so that if the token does not get redeemed it gets cleaned up.
            assert_equal 0, new_access.installation.expires_at.to_i

            new_access.redeem; new_access.reload
            new_installation.reload

            assert_kind_of SiteScopedIntegrationInstallation, new_installation
            assert_predicate new_installation, :installed_on_all_repositories?

            assert_equal 0, new_installation.expires_at.to_i

            new_installation.abilities.each do |record|
              assert_equal 0, record.expires_at.to_i
            end
          end
        end

        test "returns a :installation_creation_failed if unauthorized permissions were requested" do
          integration = create_unlimited_global_integration
          GitHub.flipper[:disabled_global_apps].disable(integration)

          access = integration.grant(@user, entry_point: :test_case)
          scoped_installation, error_response = integration.grant_scoped_access_from(access, @user, permissions: { "metadata" => :read, "issues" => :read }, entry_point: :test_case)

          assert_nil scoped_installation

          assert_equal :installation_creation_failed,                                    error_response[:error]
          assert_equal "The permissions requested are not granted to this integration.", error_response[:error_description]
          assert_equal "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/",  error_response[:error_uri]
        end
      end
    end

    context "#grant_repository_scoped_installation_on" do
      test "returns an :bad_verification_code error if the access is missing" do
        integration = create_internal_app_with_capabilities(capabilities: { per_repo_user_to_server_tokens_required: true })
        _, error_response = integration.grant_repository_scoped_installation_on(nil, entry_point: :test_case)

        assert_equal :bad_verification_code, error_response[:error]
        assert_equal "The code passed is incorrect or expired.", error_response[:error_description]
        assert_equal "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-oauth-app-access-token-request-errors/#bad-verification-code", error_response[:error_uri]
      end

      test "returns a :missing_repository error if a repository id was not provided and is required" do
        integration = create_internal_app_with_capabilities(capabilities: { per_repo_user_to_server_tokens_required: true })

        access = integration.grant(@user, entry_point: :test_case)
        scoped_installation, error_response = integration.grant_repository_scoped_installation_on(access, entry_point: :test_case)

        assert_nil scoped_installation

        assert_equal :missing_repository,                                                                  error_response[:error]
        assert_equal "This application requires that a repository is provided to redeem the OAuth token.", error_response[:error_description]
        assert_equal "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/",                      error_response[:error_uri]
      end

      test "returns a :repository_not_found error if the repo was not found" do
        repo = create(:repository, :minimal, owner: @user)
        repo.destroy!

        integration = create(:integration, default_permissions: { "metadata" => :read })

        access = integration.grant(@user, entry_point: :test_case)
        scoped_installation, error_response = integration.grant_repository_scoped_installation_on(access, repository_id: repo.id, entry_point: :test_case)

        assert_nil scoped_installation

        assert_equal :repository_not_found,                                           error_response[:error]
        assert_equal "The repository requested could not be found.",                  error_response[:error_description]
        assert_equal "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/", error_response[:error_uri]
      end

      test "returns a :repository_not_found error if the user cannot see the repository" do
        rando_repo  = create(:private_repository, :minimal)
        integration = create(:integration, default_permissions: { "metadata" => :read })

        access = integration.grant(@user, entry_point: :test_case)
        scoped_installation, error_response = integration.grant_repository_scoped_installation_on(access, repository_id: rando_repo.id, entry_point: :test_case)

        assert_nil scoped_installation

        assert_equal :repository_not_found,                                           error_response[:error]
        assert_equal "The repository requested could not be found.",                  error_response[:error_description]
        assert_equal "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/", error_response[:error_uri]
      end
    end
  end

  context "#grant_repository_codespace_scoped_installation_on", skip_enterprise: true do
    test "doesn't require SAML if the billable owner of the codespace doesn't need SAML" do
      business = if GitHub.single_business_environment?
        GitHub::Enterprise.ensure_business!
        GitHub.global_business
      else
        create :business
      end

      biz_org = create :enterprise_linked_organization, business: business
      biz_saml_org = create :enterprise_linked_organization, business: business
      biz_saml_provider = create :business_saml_provider, :scim_provisioning_enabled, business: business
      create :external_identity, provider: biz_saml_provider, user: @user
      biz_saml_org.add_member @user
      repo = create(:repository, owner: biz_org)
      integration  = create(:integration, default_permissions: { "metadata" => :read })
      make_integration_installation(integration: integration, repository: repo)
      oauth_access = integration.grant(@user, entry_point: :test_case)

      codespace = create(:codespace, owner: @user, repository: repo, enable_org_access: false, make_collaborator: false)

      installation, error = oauth_access.application.grant_repository_codespace_scoped_installation_on(oauth_access, codespace, entry_point: :test_case)
      refute_nil installation
    end

    test "for a business-owned org uses a credential from any org for the business" do
      business = if GitHub.single_business_environment?
        GitHub::Enterprise.ensure_business!
        GitHub.global_business
      else
        create :business
      end

      biz_org = create :enterprise_linked_organization, business: business
      biz_saml_org = create :enterprise_linked_organization, business: business
      biz_saml_provider = create :business_saml_provider, :scim_provisioning_enabled, business: business
      create :external_identity, provider: biz_saml_provider, user: @user
      biz_saml_org.add_member @user
      repo = create(:repository, owner: biz_org)
      integration  = create(:integration, default_permissions: { "metadata" => :read })
      make_integration_installation(integration: integration, repository: repo)
      oauth_access = integration.grant(@user, entry_point: :test_case)
      GitHub.flipper[:codespaces_user_limit_sync_update].disable

      codespace = create(:codespace, owner: @user, repository: repo)

      _, error = oauth_access.application.grant_repository_codespace_scoped_installation_on(oauth_access, codespace, entry_point: :test_case)
      assert_equal :sso_required, error[:error]

      Organization::CredentialAuthorization.grant organization: biz_saml_org,
        credential: oauth_access,
        actor: @user

      installation, _ = oauth_access.application.grant_repository_codespace_scoped_installation_on(oauth_access, codespace, entry_point: :test_case)
      refute_nil installation
    end
  end
end

class OauthAccess::SamlScopeBugProviderTest < GitHub::TestCase
  include GitHub::LoggerHelper
  # The tests in this class do not apply to EMU or Multi-Tenant
  # as they cover a Bug where a token/app that is minted for one org in a business
  # can access data from another org in the business

  fixtures do
    @business = create :business
    @org1 = create :business_plus_organization, business: @business
    @org2 = create :business_plus_organization, business: @business

    saml_provider1 = create :organization_saml_provider, organization: @org1
    saml_provider2 = create :organization_saml_provider, organization: @org2

    @user = create :user
    create :external_identity, user: @user, provider: saml_provider1
    create :external_identity, user: @user, provider: saml_provider2

    @org1.add_member @user
    @org2.add_member @user

    @org1_repo = create(:private_repository, owner: @org1)
    @integration  = create(:integration, default_permissions: { "metadata" => :read })
  end

  setup do
    GitHub.flipper[:saml_scope_private_resources_to_org].enable
    GitHub.flipper[:saml_scope_private_resources_to_org_experiment].enable

    make_integration_installation(integration: @integration, repository: @org1_repo)
    @oauth_access = @integration.grant(@user, entry_point: :test_case)
  end

  context "#scoping resources to orgs", skip_with_all_emus: true, skip_in_multitenant_mode: true do
    test "refutes creating installation when the credential auth org doesn't match the resource org, and there's no auth for target" do
      GitHub.flipper[:saml_scope_private_resources_to_org].enable
      Organization::CredentialAuthorization.grant organization: @org2, credential: @oauth_access, actor: @user

      _, error = @oauth_access.application.grant_repository_scoped_installation_on(@oauth_access, repository_id: @org1_repo.id, entry_point: :test_case)
      assert_equal :sso_required, error[:error]
    end

    test "create installation when there is an auth for target and another org" do
      GitHub.flipper[:saml_scope_private_resources_to_org].enable
      Organization::CredentialAuthorization.grant organization: @org1, credential: @oauth_access, actor: @user
      Organization::CredentialAuthorization.grant organization: @org2, credential: @oauth_access, actor: @user

      installation, _ = @oauth_access.application.grant_repository_scoped_installation_on(@oauth_access, repository_id: @org1_repo.id, entry_point: :test_case)
      refute_nil installation
    end

    test "refute creating installation when accessing a public repo and the credential auth org doesn't match the resource org" do
      GitHub.flipper[:saml_scope_private_resources_to_org].enable
      repo = create(:public_repository, :minimal, owner: @org2)
      make_integration_installation(integration: @integration, repository: repo)
      oauth_access = @integration.grant(@user, entry_point: :test_case)

      Organization::CredentialAuthorization.grant organization: @org1, credential: oauth_access, actor: @user

      _, error = oauth_access.application.grant_repository_scoped_installation_on(oauth_access, repository_id: repo.id, entry_point: :test_case)
      assert_equal :sso_required, error[:error]
    end
  end

  context "#scoping resources to orgs experiment", skip_with_all_emus: true, skip_in_multitenant_mode: true do
    test "mismatch and log when the credential auth org doesn't match the resource org, and there's no auth for target" do
      GitHub.flipper[:saml_scope_private_resources_to_org].disable

      Organization::CredentialAuthorization.grant organization: @org2, credential: @oauth_access, actor: @user

      entries = {
        namespace: "Platform::Authorization",
        function: "get_credential_authorization_experiment",
        Body: "SAML Scope experiment mismatch",
        "gh.business.id": @org1.business.id,
        "gh.organization.id": @org1.id,
        "gh.oauth_access.id": @oauth_access.id,
        "gh.oauth_application.type": "Integration",
        "gh.saml_credential.experiment.candidate": "nil"
      }

      assert_logged(**entries) do
        installation, _ = @oauth_access.application.grant_repository_scoped_installation_on(@oauth_access, repository_id: @org1_repo.id, entry_point: :test_case)
        refute_nil installation
      end
    end

    test "mismatch log internally but not audit log when the feature flag is off" do
      GitHub.flipper[:saml_scope_private_resources_to_org].disable
      GitHub.flipper[:saml_scope_private_resources_to_org_audit_log].disable
      Organization::CredentialAuthorization.grant organization: @org2, credential: @oauth_access, actor: @user

      entries = {
        namespace: "Platform::Authorization",
        function: "get_credential_authorization_experiment",
        Body: "SAML Scope experiment mismatch",
        "gh.business.id": @org1.business.id,
        "gh.organization.id": @org1.id,
        "gh.oauth_access.id": @oauth_access.id,
        "gh.oauth_application.type": "Integration",
        "gh.saml_credential.experiment.candidate": "nil"
      }

      assert_logged(**entries) do
        installation, _ = @oauth_access.application.grant_repository_scoped_installation_on(@oauth_access, repository_id: @org1_repo.id, entry_point: :test_case)
        refute_nil installation
      end
    end

    test "match when there is an auth for target and another org" do
      # if the candidate is part of the control we don't need to log and count it as a mismatch
      # customers won't be impacted by the candidate behaviour
      GitHub.flipper[:saml_scope_private_resources_to_org].disable

      Organization::CredentialAuthorization.grant organization: @org2, credential: @oauth_access, actor: @user
      Organization::CredentialAuthorization.grant organization: @org1, credential: @oauth_access, actor: @user

      refute_logged("Body" => "SAML Scope experiment mismatch") do
        installation, _ = @oauth_access.application.grant_repository_scoped_installation_on(@oauth_access, repository_id: @org1_repo.id, entry_point: :test_case)
        refute_nil installation
      end
    end

    test "match when there is only a matching credential authorization of the target org" do
      GitHub.flipper[:saml_scope_private_resources_to_org].disable
      Organization::CredentialAuthorization.grant organization: @org1, credential: @oauth_access, actor: @user

      refute_logged("Body" => "SAML Scope experiment mismatch") do
        installation, _ = @oauth_access.application.grant_repository_scoped_installation_on(@oauth_access, repository_id: @org1_repo.id, entry_point: :test_case)
        refute_nil installation
      end
    end
  end
end
