# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"
require "test_helpers/permissions_helper"
require "test_helpers/query_identifier_helper"

class CodespacesTokensTest < GitHub::TestCase
  include DogstatsTestHelpers
  include ConditionalAccess::FilterTestHelper
  include PermissionsHelper
  include QueryIdentifierHelper
  include HydroTestHelpers

  fixtures do
    make_trusted_oauth_apps_owner
    @integration = create(:codespaces_integration)

    @user = create(:user)
    @codespace = create(:codespace, owner: @user)

    @session = create(:user_session, user: @user)

    @vscode_app = create(:vscode_oauth_app)
  end

  def grant_repository_access(user, codespace, entry_point: :test_case, dc: nil)
    credential, _ = Codespaces::Tokens.grant_repository_access(user, codespace, dc:, entry_point:)
    OauthAccess.with_active_token(credential)
  end

  context ".mint_github_token" do
    test "can mint tokens" do
      token = Codespaces::Tokens.mint_github_token(@user, @codespace)
      refute_nil token
    end

    test "throws if the token cannot be minted" do
      GitHub.flipper[:disabled_global_apps].enable

      assert_raises Codespaces::Tokens::Error do
        Codespaces::Tokens.mint_github_token(@user, @codespace)
      end
    end

    test "sets datadog tags" do
      token = Codespaces::Tokens.mint_github_token(@user, @codespace)
      timings = GitHub.dogstats.distributions("codespaces.tokens.latency")
      assert_equal 2, timings.count
      expected_tags = Set.new(["action:mint_github_token"])
      assert_equal timings[1].tags, expected_tags
    end
  end

  context ".mint_github_token_with_estimated_validity" do
    test "returns token valid_after" do
      token, valid_after = Codespaces::Tokens.mint_github_token_with_estimated_validity(@user, @codespace)
      refute_nil token
      assert valid_after.is_a?(Float)
    end
  end

  context ".mint_encrypted_github_token", skip_enterprise: true do
    test "can mint tokens that are encrypted" do
      refute_nil Codespaces::Tokens.mint_encrypted_github_token(@user, @codespace)
    end

    test "sets datadog tags" do
      token = Codespaces::Tokens.mint_encrypted_github_token(@user, @codespace)
      timings = GitHub.dogstats.distributions("codespaces.tokens.latency")
      assert_equal 3, timings.count
      expected_tags = Set.new(["action:mint_encrypted_github_token"])
      assert_equal timings[2].tags, expected_tags
    end
  end

  context ".mint_web_editor_oauth_token", skip_enterprise: true do
    test "can mint oauth tokens against the expected app" do
      app = create(:lwe_oauth_app)
      token = Codespaces::Tokens.mint_web_editor_oauth_token(user: @user, session: @session)
      relation = @user.oauth_accesses.where(application: app)
      assert_predicate relation, :exists?, "token was not created"
      access_record = relation.first!
      assert_same_elements access_record.scopes, Codespaces::Tokens::WEB_EDITOR_SCOPE, "incorrect scopes created"
      assert_includes(token, access_record.token_last_eight, "got token that differs from db record")
    end

    test "token can access SAML-required org resources if a valid SAML session exists when it is minted" do
      app = create(:lwe_oauth_app)
      org = create(:organization, billing_type: "invoice", plan: "business_plus")
      org.add_member(@user)
      saml_provider = create(:organization_saml_provider, organization: org)
      saml_provider.enforce!
      external_identity = create(:external_identity, user: @user, provider: saml_provider)
      create(:external_identity_session, user_session: @session, external_identity: external_identity)

      refute_predicate Organization::CredentialAuthorization.where(organization: org), :exists?
      token = Codespaces::Tokens.mint_web_editor_oauth_token(user: @user, session: @session)
      credential = @user.oauth_accesses.where(application: app).first!
      assert_predicate \
        Organization::CredentialAuthorization.where(organization: org, credential: credential, actor: @user),
        :exists?,
        "expected token to be SAML-authorized"
    end

    test "token cannot access SAML-required org resources if no SAML session exists when it is minted" do
      app = create(:lwe_oauth_app)
      org = create(:organization, billing_type: "invoice", plan: "business_plus")
      org.add_member(@user)
      saml_provider = create(:organization_saml_provider, organization: org)
      saml_provider.enforce!

      token = Codespaces::Tokens.mint_web_editor_oauth_token(user: @user, session: @session)
      refute_predicate \
        Organization::CredentialAuthorization.where(organization: org),
        :exists?,
        "expected token not to be SAML-authorized"
    end

    test "token minted will have org permissions" do
      app = create(:lwe_oauth_app)
      org = create(:organization, billing_type: "invoice", plan: "business_plus")
      repo = create(:private_repository, owner: org)

      assert_predicate app, :third_party_oap_exempt?, "expected app to be exempt from organization policy"
      assert_includes Repository.oauth_app_policy_approved_repository_ids(app: app, repository_scope: org.repositories), repo.id, "expected list of allowed apps in org to include our app"
    end

    test "sets datadog tags" do
      app = create(:lwe_oauth_app)
      token = Codespaces::Tokens.mint_web_editor_oauth_token(user: @user, session: @session)
      timings = GitHub.dogstats.distributions("codespaces.tokens.latency")
      assert_equal 1, timings.count
      assert_equal Set["action:mint_web_editor_oauth_token"], timings[0].tags
    end

    test "fails if the internal app does not exist" do
      exception = assert_raises do
        Codespaces::Tokens.mint_web_editor_oauth_token(user: @user, session: @session)
      end
      assert_equal "missing :lightweight_web_editor internal app, configuration error?", exception.message
    end

    test "fails with a nil user" do
      ex = assert_raises(ArgumentError) { Codespaces::Tokens.mint_web_editor_oauth_token(user: nil, session: @session) }
      assert_equal("user required", ex.message)
    end

    test "fails with a nil session (need this for SAML)" do
      ex = assert_raises(ArgumentError) { Codespaces::Tokens.mint_web_editor_oauth_token(user: @user, session: nil) }
      assert_equal("session required", ex.message)
    end
  end

  context ".decrypt_github_token", skip_enterprise: true do
    test "can decrypt tokens that are encrypted" do
      nonsense_token = "thisisnonsenseforsure"
      Codespaces::Tokens.expects(:mint_github_token).returns(nonsense_token)
      encrypted_token, key_version = Codespaces::Tokens.mint_encrypted_github_token(@user, @codespace)
      decrypted_token = Codespaces::Tokens.decrypt_github_token(encrypted_token, key_version: key_version)
      refute_equal encrypted_token, decrypted_token
      assert_equal nonsense_token, decrypted_token
    end
  end

  context ".mint_codespace_token", skip_enterprise: true do
    test "can mint tokens" do
      token = Codespaces::Tokens.mint_codespace_token(scope: Codespaces::Tokens::GPG_AUTHORIZATION_SCOPE, user: @user, codespace: @codespace)
      refute_nil token
    end

    test "user is added to the token" do
      token = Codespaces::Tokens.mint_codespace_token(scope: Codespaces::Tokens::GPG_AUTHORIZATION_SCOPE, user: @user, codespace: @codespace)
      parsed_token = GitHub::Authentication::SignedAuthToken.verify(scope: Codespaces::Tokens::GPG_AUTHORIZATION_SCOPE, token: token)
      assert_equal @user, parsed_token.user
    end

    test "codespace id added to the token as data" do
      token = Codespaces::Tokens.mint_codespace_token(scope: Codespaces::Tokens::GPG_AUTHORIZATION_SCOPE, user: @user, codespace: @codespace)
      parsed_token = GitHub::Authentication::SignedAuthToken.verify(scope: Codespaces::Tokens::GPG_AUTHORIZATION_SCOPE, token: token)
      data         = { "id" => @codespace.id }
      assert_equal data, parsed_token.data
    end
  end

  context ".grant_repository_access" do
    test "sets datadog tags" do
      grant_repository_access(@user, @codespace)
      timings = GitHub.dogstats.distributions("codespaces.tokens.latency")
      assert_equal 1, timings.count

      assert_equal timings[0].tags, Set.new(["action:grant_repository_access"])
    end

    test "it grants limited set of permissions to the parent repository if repo is a fork and public" do
      parent_repo = create(:repository)
      forker = create(:user)
      forked_repo = create(:fork_repository, forker: forker, fork_repo: parent_repo)
      codespace = create(:codespace, owner: forker, repository: forked_repo)
      access = grant_repository_access(forker, codespace)
      assert parent_repo.resources.pull_requests_from_forks.writable_by?(access.installation)
      assert parent_repo.resources.pull_requests_comment_only_reviews.writable_by?(access.installation)
      refute parent_repo.resources.contents.writable_by?(access.installation)
    end

    test "instruments the Permissions entry-point for the fork operation", skip_with_all_emus: true do
      GitHub.flipper[:permissions_service_actor_level_metrics].enable
      Permissions::EntryPoint::ActorContext.stubs(:digest_from_rows).returns("fake-digest")

      parent_repo = create(:repository)
      forker = create(:user)
      forked_repo = create(:fork_repository, forker: forker, fork_repo: parent_repo)
      codespace = create(:codespace, owner: forker, repository: forked_repo)
      session = create(:user_session, user: forker)

      entry_point = :codespaces_controller_show
      access = grant_repository_access(forker, codespace, entry_point: entry_point)
      assert access.persisted?

      integration = ::Apps::Privileged.integration(:codespaces_production)
      site_scoped_installation = SiteScopedIntegrationInstallation.where(
        integration: integration, target: codespace.repository.owner,
      ).last

      expected_message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        entry_point: "codespaces_controller_show",
        actor_id: access.authorization_id,
        actor_type: :ACTOR_TYPE_OAUTH_AUTHORIZATION,
        target_id: forker.id,
        target_type: :TARGET_TYPE_USER,
        total: 1,
        owner_id: integration.id,
        owner_type: :ACTOR_OWNER_TYPE_INTEGRATION,
        owner_name: integration.name,
        write_type: :WRITE_TYPE_CREATE,
        digest: "fake-digest",
        subject_type_total: {
          "User/codespaces_user_secrets" => 1,
        }
      }

      assert_hydro_published(expected_message, schema: "github.permissions.v0.Created")
    end

    test "it grants full set of permissions to the parent repository if repo is a fork and private" do
      org = create(:organization)
      org.allow_private_repository_forking(actor: org.admins.first)
      parent_repo = create(:private_repository, owner: org)
      forker = create(:user)
      parent_repo.add_member_without_validation_or_notifications(forker)
      forked_repo = create(:fork_repository, forker: forker, fork_repo: parent_repo)
      codespace = create(:codespace, owner: forker, repository: forked_repo)
      session = create(:user_session, user: forker)
      access = grant_repository_access(forker, codespace)
      assert parent_repo.resources.pull_requests.writable_by?(access.installation)
      assert parent_repo.resources.contents.writable_by?(access.installation)
    end

    test "it writes a permission record for the codespace itself" do
      access = grant_repository_access(@user, @codespace)
      refute_nil access

      assert_equal [@codespace.id], access.installation.codespace_ids
    end

    test "it grants access to dotfiles repository" do
      dotfiles_repo = create(:private_repository, name: "dotfiles", owner: @user)
      access = grant_repository_access(@user, @codespace)
      refute dotfiles_repo.resources.contents.readable_by?(access.installation)

      access = grant_repository_access(@user, @codespace)
      refute dotfiles_repo.resources.contents.readable_by?(access.installation)

      @user.update_codespace_dotfiles_repository(dotfiles_repo.id, actor: @user)
      access = grant_repository_access(@user, @codespace)
      refute dotfiles_repo.resources.contents.readable_by?(access.installation)

      @user.enable_codespace_dotfiles(actor: @user)
      access = grant_repository_access(@user, @codespace)
      assert dotfiles_repo.resources.contents.readable_by?(access.installation)
      refute dotfiles_repo.resources.contents.writable_by?(access.installation)
    end

    test "instruments the Permissions entry-point for the dotfiles inserts", skip_with_all_emus: true do
      GitHub.flipper[:permissions_service_actor_level_metrics].enable
      Permissions::EntryPoint::ActorContext.stubs(:digest_from_rows).returns("fake-digest")

      dotfiles_repo = create(:private_repository, name: "dotfiles", owner: @user)
      @user.update_codespace_dotfiles_repository(dotfiles_repo.id, actor: @user)
      @user.enable_codespace_dotfiles(actor: @user)
      entry_point = :codespaces_controller_show
      access = grant_repository_access(
        @user, @codespace, entry_point: entry_point,
      )
      assert access.persisted?

      integration = ::Apps::Privileged.integration(:codespaces_production)
      site_scoped_installation = SiteScopedIntegrationInstallation.where(
        integration: integration, target: @codespace.repository.owner,
      ).last
      target = @user

      # These attributes are different because the feature enables writing all
      # permissions at once instead of in groups.
      message_attributes = {
        total: 1,
        subject_type_total: {
          "User/codespaces_user_secrets" => 1,
        }
      }

      expected_message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        entry_point: "codespaces_controller_show",
        actor_id: access.authorization_id,
        actor_type: :ACTOR_TYPE_OAUTH_AUTHORIZATION,
        target_id: target.id,
        target_type: :TARGET_TYPE_USER,
        owner_id: integration.id,
        owner_type: :ACTOR_OWNER_TYPE_INTEGRATION,
        owner_name: integration.name,
        write_type: :WRITE_TYPE_CREATE,
        digest: "fake-digest",
      }.merge(message_attributes)

      assert_hydro_published(expected_message, schema: "github.permissions.v0.Created")
    end

    context "with a user session" do
      test "with SAML not enforced" do
        saml_org = create_saml_org
        public_repo = create(:repository, owner: saml_org)
        public_codespace = create(:codespace, repository: public_repo, owner: @user)

        repository_access = grant_repository_access(@user, public_codespace)

        refute_nil repository_access
        assert_equal [public_repo.id], repository_access.installation.repository_ids
        refute_nil Organization::CredentialAuthorization.authorization(organization: saml_org, credential: repository_access)
      end

      test "with SAML enforced" do
        saml_org = create_saml_org(enforced: true)
        public_repo = create(:repository, owner: saml_org)
        public_codespace = create(:codespace, repository: public_repo, owner: @user)

        repository_access = grant_repository_access(@user, public_codespace)

        refute_nil repository_access
        assert_equal [public_repo.id], repository_access.installation.repository_ids
        refute_nil Organization::CredentialAuthorization.authorization(organization: saml_org, credential: repository_access)
      end

      test "transferring existing access for oauth access with saml orgs only transfers relevant access" do
        test_saml_orgs = []
        10.times do
          org = create_saml_org(enforced: true)
          org.update_organization_codespaces_ownership_setting(Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, actor: @user)
          test_saml_orgs << org
        end

        public_repo = create(:repository, owner: test_saml_orgs.first)
        public_codespace = create(:codespace, repository: public_repo, owner: @user, enable_org_access: true)
        assert_equal test_saml_orgs.first, public_codespace.billable_owner

        assert_difference -> { Organization::CredentialAuthorization.count }, 1 do
          grant_repository_access(@user, public_codespace)
        end
      end
    end

    context "with pre-validated access" do
      test "without SAML in use we don't create the authorization" do
        user = create(:user)
        org = create(:codespaces_organization, plan: GitHub::Plan.business)
        private_repo = create(:private_repository, owner: org)
        org.add_member(user)
        codespace = create(:codespace, repository: private_repo, owner: user)

        repository_access = grant_repository_access(user, codespace)

        refute_nil repository_access
        assert_equal [private_repo.id], repository_access.installation.repository_ids
        assert_nil Organization::CredentialAuthorization.authorization(organization: org, credential: repository_access)
      end

      test "with SAML in use but not enforced and an external identity for the user" do
        saml_org = create_saml_org
        public_repo = create(:repository, owner: saml_org)
        public_codespace = create(:codespace, repository: public_repo, owner: @user)

        repository_access = grant_repository_access(@user, public_codespace)

        refute_nil repository_access
        assert_equal [public_repo.id], repository_access.installation.repository_ids
        refute_nil Organization::CredentialAuthorization.authorization(organization: saml_org, credential: repository_access)
      end

      test "with SAML enforced" do
        saml_org = create_saml_org(enforced: true)
        public_repo = create(:repository, owner: saml_org)
        public_codespace = create(:codespace, repository: public_repo, owner: @user)

        repository_access = grant_repository_access(@user, public_codespace)

        refute_nil repository_access
        assert_equal [public_repo.id], repository_access.installation.repository_ids
        refute_nil Organization::CredentialAuthorization.authorization(organization: saml_org, credential: repository_access)
      end

      test "only transfers relevant access" do
        test_saml_orgs = []
        10.times do
          org = create_saml_org(enforced: true)
          org.update_organization_codespaces_ownership_setting(Configurable::OrganizationCodespacesOwnershipSetting::ORGANIZATION, actor: @user)
          test_saml_orgs << org
        end

        saml_org = test_saml_orgs.first
        public_repo = create(:repository, owner: saml_org)
        public_codespace = create(:codespace, repository: public_repo, owner: @user, enable_org_access: true)
        assert_equal test_saml_orgs.first, public_codespace.billable_owner

        assert_difference -> { Organization::CredentialAuthorization.count }, 1 do
          repository_access = grant_repository_access(@user, public_codespace)
          refute_nil Organization::CredentialAuthorization.authorization(organization: saml_org, credential: repository_access)
        end
      end
    end

    context "requesting elevated read access (org setting)" do
      test "overwrites elevated access when user has devcontainer permissions" do
        example_repo :simple, @codespace.repository

        Codespaces::UpdateTrustedRepositoryAccess.call(
          actor: @user,
          target: @codespace.repository.owner,
          trusted_repo_setting: Configurable::CodespaceTrustedRepositories::ALL_REPOS,
          entry_point: :test_case
        )

        another_repo = create(:private_repository, name: "another_repo", owner: @codespace.repository.owner)
        access = grant_repository_access(@user, @codespace)
        assert another_repo.resources.contents.readable_by?(access.installation)
        repo = @codespace.repository
        dc_contents = %{
          {
            "customizations": {
              "codespaces": {
                "repositories": {
                  "#{repo.owner}/*": {
                    "permissions": {
                      "contents": "write"
                    }
                  },
                }
              }
            }
          }
        }
        repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
          files.add(".devcontainer/devcontainer.json", dc_contents)
        end

        codespace = create(:codespace, repository: repo, owner: @user, oid: repo.refs.find("master").target_oid, devcontainer_path: ".devcontainer/devcontainer.json")

        # mimic user accepting org/* contents:write permissions
        perms = Codespaces::AllowedPermission.new(user: @user, repository: repo, target_id: repo.owner.id, target_type: "User", resource: "contents", action: "write")
        perms.save!

        access = grant_repository_access(@user, codespace)
        assert another_repo.resources.contents.writable_by?(access.installation)
      end
    end

    context "with multiple repositories" do
      context "missing devcontainer" do
        test "it doesn't blow up if we fail to find the codespace's devcontaine" do
          repo = create(:repository)

          dc = Codespaces::DevContainer.new(repository: repo, oid: nil, filepath: nil, user: nil)
          dc.expects(:has_custom_permissions?).raises(Codespaces::DevContainer::ReadError, "whoops")
          assert_nothing_raised do
            grant_repository_access(@user, @codespace, dc: dc)
          end
        end
      end

      context "with requesting all org repositories" do
        test "it grants access to repositories which the user can access and has accepted permissions" do
          org = create(:team_org)

          perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { org.update_default_repository_permission(:none, actor: org.admins.first) }

          org.add_member(@user)

          repo = create(:repository, owner: org, from_example: :simple)
          repo.add_member(@user)

          another_repo = create(:repository, owner: org, from_example: :simple)
          another_repo.add_member(@user)

          dc_contents = %{
            {
              "customizations": {
                "codespaces": {
                  "repositories": {
                    "#{org.login}/*": {
                      "permissions": {
                        "contents": "write"
                      }
                    }
                  }
                }
              }
            }
          }

          repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
            files.add(".devcontainer/devcontainer.json", dc_contents)
          end

          codespace = create(:codespace, repository: repo, owner: @user, oid: repo.refs.find("master").target_oid, devcontainer_path: ".devcontainer/devcontainer.json")

          # mimic user accepting org/* contents:write permissions
          perms = Codespaces::AllowedPermission.new(user: @user, repository: repo, target_id: org.id, target_type: "User", resource: "contents", action: "write")
          perms.save!

          access = grant_repository_access(@user, codespace)

          # codespace repo
          assert repo.resources.contents.readable_by?(access.installation)
          assert repo.resources.contents.writable_by?(access.installation)

          # specified repo in devcontainer
          assert another_repo.resources.contents.readable_by?(access.installation)
          assert another_repo.resources.contents.writable_by?(access.installation)
        end

        test "it doesn't grant access to all repositories if a user has not accepted permissions" do
          org = create(:team_org)
          org.add_member(@user)

          repo = create(:repository, owner: org, from_example: :simple)
          repo.add_member(@user)

          another_repo = create(:repository, owner: org, from_example: :simple)
          another_repo.add_member(@user)

          dc_contents = %{
            {
              "customizations": {
                "codespaces": {
                  "repositories": {
                    "#{org.login}/*": {
                      "permissions": {
                        "contents": "write"
                      }
                    }
                  }
                }
              }
            }
          }

          repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
            files.add(".devcontainer/devcontainer.json", dc_contents)
          end

          codespace = create(:codespace, repository: repo, owner: @user, oid: repo.refs.find("master").target_oid, devcontainer_path: ".devcontainer/devcontainer.json")

          access = grant_repository_access(@user, codespace)

          # codespace repo
          assert repo.resources.contents.readable_by?(access.installation)
          assert repo.resources.contents.writable_by?(access.installation)

          # specified repo in devcontainer
          assert another_repo.resources.contents.readable_by?(access.installation)
          refute another_repo.resources.contents.writable_by?(access.installation)
        end

        test "it only grants permissions to all repositories for which user has accepted permissions" do
          org = create(:team_org)

          perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { org.update_default_repository_permission(:none, actor: org.admins.first) }

          org.add_member(@user)

          repo = create(:repository, owner: org, from_example: :simple)
          repo.add_member(@user)

          another_repo = create(:repository, owner: org, from_example: :simple)
          another_repo.add_member(@user)

          dc_contents = %{
            {
              "customizations": {
                "codespaces": {
                  "repositories": {
                    "#{org.login}/*": {
                      "permissions": {
                        "contents": "write",
                        "issues": "write",
                      }
                    },
                  }
                }
              }
            }
          }

          repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
            files.add(".devcontainer/devcontainer.json", dc_contents)
          end

          codespace = create(:codespace, repository: repo, owner: @user, oid: repo.refs.find("master").target_oid, devcontainer_path: ".devcontainer/devcontainer.json")

          # mimic user accepting org/* issues:write permissions
          # note: they don't accept org/* contents:write permissions
          perms = Codespaces::AllowedPermission.new(user: @user, repository: repo, target_id: org.id, target_type: "User", resource: "issues", action: "write")
          perms.save!

          access = grant_repository_access(@user, codespace)

          # codespace repo
          assert repo.resources.contents.readable_by?(access.installation)
          assert repo.resources.contents.writable_by?(access.installation)

          # specified repo in devcontainer
          assert another_repo.resources.contents.readable_by?(access.installation)
          refute another_repo.resources.contents.writable_by?(access.installation)
          assert another_repo.resources.issues.readable_by?(access.installation)
          assert another_repo.resources.issues.writable_by?(access.installation)
        end
      end

      context "with requesting specific repositories" do
        test "it grants access to repositories which the user can access and has accepted permissions" do
          org = create(:team_org)

          perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { org.update_default_repository_permission(:none, actor: org.admins.first) }

          org.add_member(@user)

          repo = create(:repository, owner: org, from_example: :simple)
          repo.add_member(@user)

          another_repo = create(:repository, owner: org, from_example: :simple)
          another_repo.add_member(@user)

          private_repo = create(:private_repository, owner: org, from_example: :simple)

          dc_contents = %{
            {
              "customizations": {
                "codespaces": {
                  "repositories": {
                    "#{another_repo.nwo}": {
                      "permissions": {
                        "packages": "write"
                      }
                    }
                  }
                }
              }
            }
          }

          repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
            files.add(".devcontainer/devcontainer.json", dc_contents)
          end

          codespace = create(:codespace, repository: repo, owner: @user, oid: repo.refs.find("master").target_oid, devcontainer_path: ".devcontainer/devcontainer.json")

          # mimic user accepting org/another_repo packages write permissions
          perms = Codespaces::AllowedPermission.new(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "packages", action: "write")
          perms.save!

          access = grant_repository_access(@user, codespace)

          # codespace repo
          assert repo.resources.contents.readable_by?(access.installation)
          assert repo.resources.contents.writable_by?(access.installation)

          # specified repo in devcontainer
          assert another_repo.resources.contents.readable_by?(access.installation)
          refute another_repo.resources.contents.writable_by?(access.installation)
          assert another_repo.resources.packages.writable_by?(access.installation)

          # repo user should not have access to
          refute private_repo.resources.contents.readable_by?(access.installation)
          refute private_repo.resources.contents.writable_by?(access.installation)
        end

        test "it doesn't grant access to repositories which the user did not accept permissions" do
          org = create(:team_org)
          org.add_member(@user)

          repo = create(:repository, owner: org, from_example: :simple)
          repo.add_member(@user)

          another_repo = create(:repository, owner: org, from_example: :simple)
          another_repo.add_member(@user)

          another_other_repo = create(:repository, owner: org, from_example: :simple)
          another_other_repo.add_member(@user)

          dc_contents = %{
            {
             "customizations": {
              "codespaces": {
                "repositories": {
                  "#{another_repo.nwo}": {
                    "permissions": {
                      "packages": "write"
                    }
                  },
                  "#{another_other_repo.nwo}": {
                    "permissions": {
                      "packages": "write"
                    }
                  },
                }
              }
             }
            }
          }

          repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
            files.add(".devcontainer/devcontainer.json", dc_contents)
          end

          codespace = create(:codespace, repository: repo, owner: @user, oid: repo.refs.find("master").target_oid, devcontainer_path: ".devcontainer/devcontainer.json")

          # mimic user accepting org/another_repo packages write permissions
          # note: they don't accept org/another_other_repo packages write permissions
          perms = Codespaces::AllowedPermission.new(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "packages", action: "write")
          perms.save!

          access = grant_repository_access(@user, codespace)

          # codespace repo
          assert repo.resources.contents.readable_by?(access.installation)
          assert repo.resources.contents.writable_by?(access.installation)

          # specified repo in devcontainer
          assert another_repo.resources.contents.readable_by?(access.installation)
          refute another_repo.resources.contents.writable_by?(access.installation)
          assert another_repo.resources.packages.readable_by?(access.installation)
          assert another_repo.resources.packages.writable_by?(access.installation)

          # repo user should not have packages write access to because they didnt accept permissions
          assert another_other_repo.resources.packages.readable_by?(access.installation)
          refute another_other_repo.resources.packages.writable_by?(access.installation)
        end
      end

      context "with specific repositories and elevated access (all repositories)" do
        test "it grants access successfully" do
          org = create(:team_org)

          perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { org.update_default_repository_permission(:none, actor: org.admins.first) }

          org.add_member(@user)

          repo = create(:repository, owner: org, from_example: :simple)
          repo.add_member(@user)

          another_repo = create(:repository, owner: org, from_example: :simple)
          another_repo.add_member(@user)

          dc_contents = %{
            {
              "customizations": {
                "codespaces": {
                  "repositories": {
                    "#{org.login}/*": {
                      "permissions": {
                        "contents": "write"
                      }
                    },
                    "#{another_repo.nwo}": {
                      "permissions": {
                        "packages": "write"
                      }
                    },
                  }
                }
              }
            }
          }

          repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
            files.add(".devcontainer/devcontainer.json", dc_contents)
          end

          codespace = create(:codespace, repository: repo, owner: @user, oid: repo.refs.find("master").target_oid, devcontainer_path: ".devcontainer/devcontainer.json")

          # mimic user accepting org/* contents:write permissions
          Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: org.id, target_type: "User", resource: "contents", action: "write")
          Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "packages", action: "write")

          access = grant_repository_access(@user, codespace)

          # codespace repo
          assert repo.resources.contents.readable_by?(access.installation)
          assert repo.resources.contents.writable_by?(access.installation)

          # specified repo in devcontainer
          assert another_repo.resources.contents.readable_by?(access.installation)
          assert another_repo.resources.contents.writable_by?(access.installation)
          assert another_repo.resources.packages.writable_by?(access.installation)
        end
      end
    end
  end

  context "#mint_prebuild_github_token" do
    test "returns a token capable of reading repository contents but not writing" do
      branch = "master"
      org = create(:team_org)
      org.add_member(@user)
      repo = create(:repository, owner: org, from_example: :simple)
      repo.add_member(@user)

      another_repo = create(:repository, owner: org, from_example: :simple)
      another_repo.add_member(@user)

      token, installation = Codespaces::Tokens::PrebuildTokens.mint_prebuild_github_token(repo, branch)
      assert token

      subject = repo.resources.contents

      refute another_repo.resources.contents.writable_by?(installation)
    end

    test "returns a token based on the allowed permissions - all required permissiones granted" do
      branch = "master"
      org = create(:team_org)
      org.add_member(@user)

      repo = create(:repository, owner: org, from_example: :simple)
      repo.add_member(@user)

      another_repo = create(:private_repository, owner: org, from_example: :simple)
      another_repo.add_member(@user)

      another_other_repo = create(:private_repository, owner: org, from_example: :simple)
      another_other_repo.add_member(@user)

      dc_contents = %{
        {
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{another_repo.nwo}": {
                  "permissions": {
                    "contents": "read",
                    "packages": "read",
                  }
                },
                "#{another_other_repo.nwo}": {
                  "permissions": {
                    "contents": "read",
                    "packages": "read",
                  }
                }
              }
            }
          }
        }
      }

      repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      dev_container_path = ".devcontainer/devcontainer.json"
      configuration = create(:codespace_prebuild_configuration, repository: repo, branch: branch, devcontainer_path: dev_container_path)

      # mimic user accepting org/another_repo packages content read permissions
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "metadata", action: "read",  is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_other_repo.id, target_type: "Repository", resource: "metadata", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)

      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "contents", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "packages", action: "read",  is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)

      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_other_repo.id, target_type: "Repository", resource: "contents", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_other_repo.id, target_type: "Repository", resource: "packages", action: "read",  is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)

      token, installation = Codespaces::Tokens::PrebuildTokens.mint_prebuild_github_token(repo, branch)
      assert token

      # prebuild repo
      subject = repo.resources.contents
      assert repo.resources.contents.readable_by?(installation)


      # mandatory permissions are granted
      assert another_repo.resources.metadata.readable_by?(installation)
      assert another_other_repo.resources.metadata.readable_by?(installation)

      # specified repo in devcontainer
      assert another_repo.resources.contents.readable_by?(installation)
      refute another_repo.resources.contents.writable_by?(installation)
      assert another_repo.resources.packages.readable_by?(installation)
      refute another_repo.resources.packages.writable_by?(installation)
    end

    test "it downgrades `write` to `read`" do
      branch = "master"
      org = create(:team_org)
      org.add_member(@user)

      repo = create(:repository, owner: org, from_example: :simple)
      repo.add_member(@user)

      another_repo = create(:private_repository, owner: org, from_example: :simple)
      another_repo.add_member(@user)

      dc_contents = %{
        {
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{another_repo.nwo}": {
                  "permissions": {
                    "contents": "write",
                  }
                }
              }
            }
          }
        }
      }

      repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      dev_container_path = ".devcontainer/devcontainer.json"
      configuration = create(:codespace_prebuild_configuration, repository: repo, branch: branch, devcontainer_path: dev_container_path)

      # mimic user accepting org/another_repo packages content read permissions
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "metadata", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "contents", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)

      token, installation = Codespaces::Tokens::PrebuildTokens.mint_prebuild_github_token(repo, branch)
      assert token

      assert repo.resources.metadata.readable_by?(installation)
      assert repo.resources.contents.readable_by?(installation)

      assert another_repo.resources.metadata.readable_by?(installation)
      assert another_repo.resources.contents.readable_by?(installation)
      refute another_repo.resources.contents.writable_by?(installation)
    end

    test "returns a token based on the allowed permissions - after repo admin accepts permissions they have access to" do

      branch = "master"
      org = create(:team_org)
      user2 = create(:user, login: "user2")

      repo = create(:repository, owner: org, name: "repo", from_example: :simple)
      GitHub.flipper[:codespaces_prebuild_admin_repo_access].enable(repo)
      repo.add_member(@user)
      repo.add_member(user2, action: :admin)

      another_repo = create(:repository, owner: org, name: "another_repo", from_example: :simple)
      another_repo.add_member(@user)
      another_repo.add_member(user2)

      private_repo = create(:private_repository, owner: org, name: "private_repo", from_example: :simple)
      private_repo.add_member(@user)

      dc_contents = %{
        {
         "customizations": {
          "codespaces": {
            "repositories": {
              "#{another_repo.nwo}": {
                "permissions": {
                  "contents": "read",
                  "issues": "write"
                }
              },
              "#{private_repo.nwo}": {
                "permissions": {
                  "pull_requests": "read",
                }
              }
            }
          }
         }
        }
      }

      repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      dev_container_path = ".devcontainer/devcontainer.json"
      configuration = create(:codespace_prebuild_configuration, repository: repo, branch: branch, devcontainer_path: dev_container_path)

      # mimic user accepting org/another_repo packages content read permissions
      Codespaces::AllowedPermission.create!(user: user2, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "metadata", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: user2, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "issues", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: user2, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "contents", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)

      token, installation = Codespaces::Tokens::PrebuildTokens.mint_prebuild_github_token(repo, branch)
      assert token

      # prebuild repo
      subject = repo.resources.contents
      assert repo.resources.contents.readable_by?(installation)

      refute another_repo.resources.pull_requests.writable_by?(installation)

      # specified repo in devcontainer
      assert another_repo.resources.contents.readable_by?(installation)
      refute another_repo.resources.contents.writable_by?(installation)
      refute another_repo.resources.issues.writable_by?(installation)

      # should not have access to
      refute private_repo.resources.contents.readable_by?(installation)
      refute private_repo.resources.contents.writable_by?(installation)
      refute private_repo.resources.pull_requests.readable_by?(installation)

    end

    test "returns a token based on the allowed permissions - not all required permissions granted" do
      branch = "master"
      org = create(:team_org)
      org.add_member(@user)

      repo = create(:repository, owner: org, from_example: :simple)
      repo.add_member(@user)

      another_repo = create(:repository, owner: org, from_example: :simple)
      another_repo.add_member(@user)

      another_other_repo = create(:repository, owner: org, from_example: :simple)
      another_other_repo.add_member(@user)

      private_repo = create(:private_repository, owner: org, from_example: :simple)

      another_private_repo = create(:private_repository, owner: org, from_example: :simple)

      another_other_private_repo = create(:private_repository, owner: org, from_example: :simple)

      dc_contents = %{
        {
         "customizations": {
          "codespaces": {
            "repositories": {
              "#{another_repo.nwo}": {
                "permissions": {
                  "pull_requests": "read",
                  "issues": "write"
                }
              },
              "#{another_other_repo.nwo}": {
                "permissions": {
                  "pull_requests": "read",
                }
              },
              "#{another_private_repo.nwo}": {
                "permissions": {
                  "pull_requests": "read",
                }
              },
              "#{another_other_private_repo.nwo}": {
                "permissions": {
                  "pull_requests": "read",
                }
              }
            }
          }
         }
        }
      }

      repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
        files.add(".devcontainer/devcontainer.json", dc_contents)
      end

      dev_container_path = ".devcontainer/devcontainer.json"
      configuration = create(:codespace_prebuild_configuration, repository: repo, branch: branch, devcontainer_path: dev_container_path)

      # mimic user accepting org/another_repo content read permissions and not packages
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "packages", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_private_repo.id, target_type: "Repository", resource: "pull_requests", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)

      token, installation = Codespaces::Tokens::PrebuildTokens.mint_prebuild_github_token(repo, branch)
      assert token

      # prebuild repo
      subject = repo.resources.contents
      assert repo.resources.contents.readable_by?(installation)

      refute another_repo.resources.pull_requests.writable_by?(installation)

      # specified repo in devcontainer
      assert another_repo.resources.contents.readable_by?(installation)
      refute another_repo.resources.contents.writable_by?(installation)
      refute another_repo.resources.issues.writable_by?(installation)
      assert another_private_repo.resources.pull_requests.readable_by?(installation)

      # should not have access to
      refute private_repo.resources.contents.readable_by?(installation)
      refute private_repo.resources.contents.writable_by?(installation)
      refute another_other_private_repo.resources.pull_requests.readable_by?(installation)

    end

    test "returns a token based on the allowed permissions multiple repos with multiple devcontainer configurations " do
      branch = "master"
      org = create(:team_org)
      org.add_member(@user)

      repo = create(:repository, owner: org, from_example: :simple)
      repo.add_member(@user)

      another_repo = create(:private_repository, owner: org, from_example: :simple)
      another_repo.add_member(@user)

      another_other_repo = create(:private_repository, owner: org, from_example: :simple)
      another_other_repo.add_member(@user)

      # want to test the combination of multiple devcontainer configurations
      dc_contents = %{
        {
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{another_repo.nwo}": {
                  "permissions": {
                    "packages": "read",
                    "contents": "read"
                  }
                }
              }
            }
          }
        }
      }

      another_dc_contents = %{
        {
          "customizations": {
            "codespaces": {
              "repositories": {
                "#{another_other_repo.nwo}": {
                  "permissions": {
                    "packages": "read",
                    "contents": "read"
                  }
                },
                "#{another_repo.nwo}": {
                  "permissions": {
                    "packages": "read",
                    "pull_requests": "read"
                  }
                }
              }
            }
          }
        }
      }

      dev_container_path = ".devcontainer/devcontainer.json"
      another_dev_container_path = ".devcontainer/one/devcontainer.json"

      repo.refs.find("master").append_commit({ message: "add devcontainer json file", committer: repo.owner }, repo.owner) do |files|
        files.add(dev_container_path, dc_contents)
      end

      repo.refs.find("master").append_commit({ message: "add devcontainer2 json file", committer: repo.owner }, repo.owner) do |files|
        files.add(another_dev_container_path, another_dc_contents)
      end

      configuration = create(:codespace_prebuild_configuration, repository: repo, branch: branch, devcontainer_path: dev_container_path)

      another_configuration = create(:codespace_prebuild_configuration, repository: repo, branch: branch, devcontainer_path: another_dev_container_path)

      # mimic user accepting org/another_repo in the first devcontainer configuration
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "metadata", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_other_repo.id, target_type: "Repository", resource: "metadata", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: another_configuration.id)

      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "packages", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "contents", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_repo.id, target_type: "Repository", resource: "pull_requests", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: another_configuration.id)

      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_other_repo.id, target_type: "Repository", resource: "packages", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: another_configuration.id)
      Codespaces::AllowedPermission.create!(user: @user, repository: repo, target_id: another_other_repo.id, target_type: "Repository", resource: "contents", action: "read", is_prebuild: true, codespace_prebuild_configuration_id: another_configuration.id)

      token, installation = Codespaces::Tokens::PrebuildTokens.mint_prebuild_github_token(repo, branch)
      assert token

      # prebuild repo
      subject = repo.resources.contents
      assert repo.resources.contents.readable_by?(installation)

      # mandatory permissions
      assert another_repo.resources.metadata.readable_by?(installation)
      assert another_other_repo.resources.metadata.readable_by?(installation)

      # specified repo in devcontainer
      assert another_repo.resources.packages.readable_by?(installation)
      refute another_repo.resources.packages.writable_by?(installation)
      assert another_repo.resources.contents.readable_by?(installation)
      refute another_repo.resources.contents.writable_by?(installation)

      assert another_other_repo.resources.packages.readable_by?(installation)
      refute another_other_repo.resources.packages.writable_by?(installation)
      assert another_other_repo.resources.contents.readable_by?(installation)
      refute another_other_repo.resources.contents.writable_by?(installation)
    end

    test "only writes one AuthenticationToken when minting a prebuild token" do
      branch = "master"
      org = create(:team_org)
      org.add_member(@user)
      repo = create(:repository, owner: org, from_example: :simple)
      repo.add_member(@user)

      another_repo = create(:repository, owner: org, from_example: :simple)
      another_repo.add_member(@user)

      _, installation = Codespaces::Tokens::PrebuildTokens.mint_prebuild_github_token(repo, branch)

      assert_equal 1, AuthenticationToken.where(authenticatable: installation).count
    end
  end

  context "mint_read_access_token" do
    test "validate private repository" do
      org = create(:organization)
      repo = create(:private_repository, owner: org)
      token = Codespaces::Tokens.mint_read_access_token(repo)
      assert token
    end

    test "validate internal repository" do
      org = create(:enterprise_linked_organization)
      repo = create(:internal_repository, owner: org)
      token = Codespaces::Tokens.mint_read_access_token(repo)
      assert token
    end

    test "validate public repository" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      token = Codespaces::Tokens.mint_read_access_token(repo)
      assert token
    end

    test "nil" do
      token = Codespaces::Tokens.mint_read_access_token(nil)
      refute token
    end
  end

  def create_saml_org(enforced: false, create_saml_session: true)
    saml_org = create(:business_plus_org, admin: @user)
    saml_provider = enforced ? create(:organization_saml_provider, :enforced, organization: saml_org) : create(:organization_saml_provider, organization: saml_org)
    external_identity = create(:external_identity, user: @user, provider: saml_provider)
    create(:external_identity_session, external_identity: external_identity, user_session: @session) if create_saml_session

    saml_org
  end

  # expects token produced by Codespaces::Tokens.grant_multi_repository_access
  # and a hash that's like repo.nwo => permissions
  def assert_repo_permissions(token, repo_permissions)
    repo_permissions.each do |nwo, permissions_outer|
      permissions = permissions_outer["permissions"]
      repo = Repository.nwo(nwo)
      permissions.each do |resource, action|
        permission_checked = false

        case resource
        when "contents"
          case action
          when "write"
            assert repo.resources.contents.writable_by?(token.installation)
            permission_checked = true
          when "read"
            assert repo.resources.contents.readable_by?(token.installation)
            permission_checked = true
          end
        when "packages"
          case action
          when "write"
            assert repo.resources.packages.writable_by?(token.installation)
            permission_checked = true
          when "read"
            assert repo.resources.packages.readable_by?(token.installation)
            permission_checked = true
          end
        when "pull_requests"
          case action
          when "write"
            assert repo.resources.pull_requests.writable_by?(token.installation)
            permission_checked = true
          when "read"
            assert repo.resources.pull_requests.readable_by?(token.installation)
            permission_checked = true
          end
        end

        assert permission_checked, "No permission checked for #{resource} #{action} on #{nwo}"
      end
    end
  end
end unless GitHub.enterprise?
