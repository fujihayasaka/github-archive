# typed: true
# frozen_string_literal: true

require "github/launch_client"
require "test_helper"
require "test_helpers/fake_kredz"
require "test_helpers/secrets_test_helpers"

module Codespaces
  class SecretTest < GitHub::TestCase
    include SecretsTestHelper
    include DogstatsTestHelpers

    fixtures do
      make_trusted_oauth_apps_owner
      @integration = create(:codespaces_integration)
      @vm_secrets_integration = create(:codespaces_vm_secrets_integration)
      @user = create(:user)
      @enterprise = create(:business)
      @org = create(:team_org, admin: @user, business: @enterprise)
      @enterprise.add_organization(@org)
      @repo = create(:repository, owner: @org, from_example: :refs_test)

      @codespace = create(:codespace, owner: @user, repository: @repo, billable_owner: @org, billable_owner_override: true)
      @other_org = create(:organization)
      @other_org_repo = create(:repository, owner: @other_org, from_example: :refs_test)
    end

    setup do
      @test_secret_value = "super secret string"
      GitHub.flipper[:disable_codespaces_secrets].disable
      GitHub.flipper[:codespaces_prebuilds_readyonly_access_check].disable

      @user_secret = {
        app: @integration,
        name: "USER_SECRET",
        value: encrypt_with_owner_next_global_id(@test_secret_value, @user),
        owner: @user,
        selected_repositories: [@repo.next_global_id, @other_org_repo.next_global_id],
      }

      @repo_secret = {
        app: @integration,
        name: "REPO_SECRET",
        value: encrypt_with_owner_next_global_id(@test_secret_value, @repo),
        owner: @repo,
      }

      @readonly_repo_secret = {
        app: @integration,
        name: "READONLY_REPO_SECRET",
        value: encrypt_with_owner_next_global_id(@test_secret_value, @repo),
        owner: @other_org_repo,
      }

      @org_secret = {
        app: @integration,
        name: "ORG_SECRET",
        value: encrypt_with_owner_next_global_id(@test_secret_value, @org),
        owner: @org,
        selected_repositories: [@repo.next_global_id],
      }

      @readonly_org_secret = {
        app: @integration,
        name: "READONLY_ORG_SECRET",
        value: encrypt_with_owner_next_global_id(@test_secret_value, @other_org),
        owner: @other_org,
        selected_repositories: [@other_org_repo.next_global_id],
      }

      @org_repo_override_secret = {
        app: @integration,
        name: "ORG_REPO_OVERRIDE_SECRET",
        value: encrypt_with_owner_next_global_id("org version of org repo override secret", @org),
        owner: @org,
        selected_repositories: [@repo.next_global_id],
      }

      @repo_override_secret = {
        app: @integration,
        name: "ORG_REPO_OVERRIDE_SECRET",
        value: encrypt_with_owner_next_global_id("repo version of org repo override secret", @repo),
        owner: @repo,
      }

      @org_repo_user_override_secret = {
        app: @integration,
        name: "ORG_REPO_USER_OVERRIDE_SECRET",
        value: encrypt_with_owner_next_global_id("org version of org repo user override secret", @org),
        owner: @org,
        selected_repositories: [@repo.next_global_id],
      }

      @repo_user_override_secret = {
        app: @integration,
        name: "ORG_REPO_USER_OVERRIDE_SECRET",
        value: encrypt_with_owner_next_global_id("repo version of org repo user override secret", @repo),
        owner: @repo,
      }

      @user_override_secret = {
        app: @integration,
        name: "ORG_REPO_USER_OVERRIDE_SECRET",
        value: encrypt_with_owner_next_global_id("user version of org repo user override secret", @user),
        owner: @user,
        selected_repositories: [@repo.next_global_id],
      }

      @actions_org_secret = {
        app: @integration,
        name: "ACTIONS_ORG_SECRET",
        value: encrypt_with_owner_next_global_id("some secret we shouldn't see", @org, key_name: Platform::EncryptionKeys::CUSTOM_TASKS),
        owner: @org,
        selected_repositories: [@repo.next_global_id],
      }

      @filtered_repo_secret = {
        app: @integration,
        name: Codespaces::GetPrebuildSecrets::PREBUILD_PAT_SECRET_KEY,
        value: encrypt_with_owner_next_global_id(@test_secret_value, @repo),
        owner: @repo,
      }

      @filtered_org_secret = {
        app: @integration,
        name: Codespaces::GetPrebuildSecrets::PREBUILD_PAT_SECRET_KEY,
        value: encrypt_with_owner_next_global_id(@test_secret_value, @org),
        owner: @org,
        selected_repositories: [@repo.next_global_id],
      }

      @another_filtered_repo_secret = {
        app: @integration,
        name: Codespaces::GetPrebuildSecrets::LEGACY_PREBUILD_PAT_SECRET_KEY,
        value: encrypt_with_owner_next_global_id(@test_secret_value, @repo),
        owner: @repo,
      }

      @another_filtered_org_secret = {
        app: @integration,
        name: Codespaces::GetPrebuildSecrets::LEGACY_PREBUILD_PAT_SECRET_KEY,
        value: encrypt_with_owner_next_global_id(@test_secret_value, @org),
        owner: @org,
        selected_repositories: [@repo.next_global_id],
      }

      @host_setup_secret = {
        app: @vm_secrets_integration,
        name: "HOST_SETUP_SECRET_1",
        owner: @org,
        value: encrypt_with_owner_next_global_id(@test_secret_value, @org, key_name: Platform::EncryptionKeys::CODESPACES_VM_SECRETS),
        selected_repositories: [],
      }

      @another_host_setup_secret = {
        app: @vm_secrets_integration,
        name: "HOST_SETUP_SECRET_2",
        owner: @org,
        value: encrypt_with_owner_next_global_id(@test_secret_value, @org, key_name: Platform::EncryptionKeys::CODESPACES_VM_SECRETS),
        selected_repositories: [],
      }
    end

    context "secret instance type" do
      test "defaults to env var" do
        assert_equal Codespaces::Secret::TYPE_ENV_VAR, Codespaces::Secret.new("foo", "bar", @user).type
      end

      test "raises if not already defined" do
        assert_raises(ArgumentError) { Codespaces::Secret.new("foo", "bar", @user, "CUSTOM_TYPE") }

        assert_equal Codespaces::Secret::TYPE_HOST_SETUP, Codespaces::Secret.new("foo", "bar", @user, Codespaces::Secret::TYPE_HOST_SETUP).type
      end
    end

    context "Secret.assemble", skip_enterprise: true do
      test "returns secrets for user" do
        FakeKredz.with_secrets(@user_secret) do
          secrets = Codespaces::Secret.assemble(@codespace)

          assert_equal 1, secrets.count
          assert_equal @user_secret[:name], secrets.first.name
          assert_equal @user_secret[:value], secrets.first.encrypted_value
        end
      end

      test "returns secrets for repo" do
        FakeKredz.with_secrets(@repo_secret) do
          secrets = Codespaces::Secret.assemble(@codespace)

          assert_equal 1, secrets.count
          assert_equal @repo_secret[:name], secrets.first.name
          assert_equal @repo_secret[:value], secrets.first.encrypted_value
        end
      end

      test "returns secrets for org" do
        FakeKredz.with_secrets(@org_secret) do
          secrets = Codespaces::Secret.assemble(@codespace)

          assert_equal 1, secrets.count
          assert_equal @org_secret[:name], secrets.first.name
          assert_equal @org_secret[:value], secrets.first.encrypted_value
        end
      end

      test "returns secrets for all three: user, repo, and org" do
        FakeKredz.with_secrets(@user_secret, @repo_secret, @org_secret) do
          secrets = Codespaces::Secret.assemble(@codespace)

          assert_equal 3, secrets.count
          assert secrets.map(&:name).include? @user_secret[:name]
          assert secrets.map(&:name).include? @repo_secret[:name]
          assert secrets.map(&:name).include? @org_secret[:name]
        end
      end

      test "returns ONLY user secrets if the user can't push to the repository" do
        readonly_codespace = create(:codespace, owner: @user, repository: @other_org_repo, make_collaborator: false)
        FakeKredz.with_secrets(@user_secret, @repo_secret, @org_secret) do
          secrets = Codespaces::Secret.assemble(readonly_codespace)

          assert_equal 1, secrets.count
          assert_equal @user_secret[:name], secrets.first.name
        end
      end

      test "does not return filtered secrets" do
        FakeKredz.with_secrets(@user_secret, @repo_secret, @org_secret, @filtered_repo_secret,
          @filtered_org_secret, @another_filtered_repo_secret, @another_filtered_org_secret) do
          secrets = Codespaces::Secret.assemble(@codespace)

          secret_names = secrets.map(&:name)
          assert_equal 3, secrets.count
          assert secret_names.include? @user_secret[:name]
          assert secret_names.include? @repo_secret[:name]
          assert secret_names.include? @org_secret[:name]
          refute secret_names.include? @filtered_repo_secret[:name]
          refute secret_names.include? @filtered_org_secret[:name]
          refute secret_names.include? @another_filtered_repo_secret[:name]
          refute secret_names.include? @another_filtered_org_secret[:name]
        end
      end

      test "correctly consolidates secrets with overrides User > Repo > Org" do
        FakeKredz.with_secrets(
          @user_secret,
          @repo_secret,
          @org_secret,
          @org_repo_override_secret,
          @repo_override_secret,
          @org_repo_user_override_secret,
          @repo_user_override_secret,
          @user_override_secret,
        ) do
          secrets = Codespaces::Secret.assemble(@codespace)

          assert_equal 5, secrets.count

          actual_org_repo_override_secret = secrets.find { |s| s.name == @org_repo_override_secret[:name] }
          # repo wins between org and repo
          assert_equal @repo_override_secret[:owner], actual_org_repo_override_secret.owner

          actual_org_repo_user_override_secret = secrets.find { |s| s.name == @org_repo_user_override_secret[:name] }
          # user wins between org, repo and user
          assert_equal @user_override_secret[:owner], actual_org_repo_user_override_secret.owner
        end
      end

      test "returns host setup secrets for an org" do
        GitHub.flipper[:codespaces_host_setup_policy].enable
        GitHub.flipper[:codespaces_salus_beta_customers].enable(@enterprise)
        FakeKredz.with_secrets(@user_secret, @host_setup_secret, @another_host_setup_secret) do
          secrets = Codespaces::Secret.assemble(@codespace, host_setup: true)

          assert_equal 3, secrets.count
          assert secrets.map(&:name).include? @host_setup_secret[:name]
          assert secrets.map(&:name).include? @another_host_setup_secret[:name]
          assert secrets.map(&:type).include? Codespaces::Secret::TYPE_HOST_SETUP
        end
      end

      test "returns host setup secrets for an org (readonly codespace)" do
        GitHub.flipper[:codespaces_host_setup_policy].enable
        GitHub.flipper[:codespaces_salus_beta_customers].enable(@enterprise)
        readonly_codespace = create(:codespace, owner: @user, repository: @repo, make_collaborator: false, billable_owner: @org, billable_owner_override: true)
        FakeKredz.with_secrets(@user_secret, @host_setup_secret, @another_host_setup_secret) do
          secrets = Codespaces::Secret.assemble(readonly_codespace, host_setup: true)

          assert_equal 3, secrets.count
          assert secrets.map(&:name).include? @host_setup_secret[:name]
          assert secrets.map(&:name).include? @another_host_setup_secret[:name]
          assert secrets.map(&:type).include? Codespaces::Secret::TYPE_HOST_SETUP
        end
      end

      test "doesn't return host setup secrets for another org" do
        GitHub.flipper[:codespaces_host_setup_policy].enable
        GitHub.flipper[:codespaces_salus_beta_customers].enable
        codespace = create(:codespace, owner: @user, repository: @other_org_repo)
        FakeKredz.with_secrets(@user_secret, @host_setup_secret, @another_host_setup_secret) do
          secrets = Codespaces::Secret.assemble(codespace, host_setup: true)

          assert_equal 1, secrets.count
          assert_equal @user_secret[:name], secrets.first.name
        end
      end

      test "doesn't return host setup secrets without feature flag" do
        GitHub.flipper[:codespaces_host_setup_policy].disable
        GitHub.flipper[:codespaces_salus_beta_customers].disable
        FakeKredz.with_secrets(@user_secret, @host_setup_secret, @another_host_setup_secret) do
          secrets = Codespaces::Secret.assemble(@codespace, host_setup: true)

          assert_equal 1, secrets.count
          assert_equal @user_secret[:name], secrets.first.name
        end
      end

      test "doesn't return host setup secrets without specifying" do
        GitHub.flipper[:codespaces_host_setup_policy].enable
        GitHub.flipper[:codespaces_salus_beta_customers].enable
        FakeKredz.with_secrets(@user_secret, @host_setup_secret, @another_host_setup_secret) do
          secrets = Codespaces::Secret.assemble(@codespace)

          assert_equal 1, secrets.count
          assert_equal @user_secret[:name], secrets.first.name
        end
      end
    end

    context "decrypt", skip_enterprise: true do
      test "successfully decrypts secret that was encrypted with codespaces secret key" do
        FakeKredz.with_secrets(@org_repo_override_secret) do
          secrets = Codespaces::Secret.assemble(@codespace)

          assert_equal "org version of org repo override secret", secrets.first.decrypt
        end
      end

      test "successfully decrypts all levels of secrets" do
        FakeKredz.with_secrets(
          @user_secret,
          @repo_secret,
          @org_secret,
          @org_repo_override_secret,
          @repo_override_secret,
          @org_repo_user_override_secret,
          @repo_user_override_secret,
          @user_override_secret,
        ) do
          secrets = Codespaces::Secret.assemble(@codespace)

          assert_equal 5, secrets.count

          actual_org_repo_override_secret = secrets.find { |s| s.name == @org_repo_override_secret[:name] }
          assert_equal "repo version of org repo override secret", actual_org_repo_override_secret.decrypt

          actual_org_repo_user_override_secret = secrets.find { |s| s.name == @org_repo_user_override_secret[:name] }
          assert_equal "user version of org repo user override secret", actual_org_repo_user_override_secret.decrypt
        end
      end

      test "fails to decrypt secret encrypted with a different key" do
        # We shouldn't be able to get into this situation since we're only
        # asking credz for the secrets stored for the codespaces integration,
        # but I figured it would be good to test our defense-in-depth approach
        # here.
        FakeKredz.with_secrets(@actions_org_secret) do
          secrets = Codespaces::Secret.assemble(@codespace)
          secret = secrets.first

          assert_raises(DietEarthsmoke::ExtractionError) do
            secret.decrypt
          end
        end
      end
    end

    context "prebuilds allowed" do
      test "returns false if prebuilds are not enabled for the repo" do
        GitHub.flipper[:codespaces_prebuilds_readyonly_access_check].enable

        refute Codespaces::Secret.prebuild_allowed?(codespace: @codespace)
      end

      test "returns true if prebuilds are enabled and the feature flag is disabled" do
        GitHub.flipper[:codespaces_prebuilds_readyonly_access_check].disable

        prebuild_configuration = create(:codespace_prebuild_configuration, repository: @codespace.repository)

        assert Codespaces::Secret.prebuild_allowed?(codespace: @codespace)
      end

      test "returns false if the user doesn't have contributor access to the repository" do
        GitHub.flipper[:codespaces_prebuilds_readyonly_access_check].enable

        prebuild_configuration = create(:codespace_prebuild_configuration, repository: @other_org_repo)
        readonly_codespace = create(:codespace, owner: @user, repository: @other_org_repo, make_collaborator: false)
        FakeKredz.with_secrets(@user_secret, @repo_secret, @org_secret) do
          refute Codespaces::Secret.prebuild_allowed?(codespace: readonly_codespace)
        end
      end

      test "returns true if user has write access to the repo" do
        GitHub.flipper[:codespaces_prebuilds_readyonly_access_check].enable

        prebuild_configuration = create(:codespace_prebuild_configuration, repository: @codespace.repository)
        FakeKredz.with_secrets(@user_secret, @repo_secret, @org_secret) do
          assert Codespaces::Secret.prebuild_allowed?(codespace: @codespace)
        end
      end
    end

    context "bulk fetching" do
      test "repo and org secrets do not require subsequent fetches to get encrypted values" do
        FakeKredz.any_instance.expects(:fetch_credential).never
        FakeKredz.with_secrets(@repo_secret, @org_secret) do
          secrets = Codespaces::Secret.assemble(@codespace)

          assert_equal 2, secrets.count
          assert secrets.map(&:name).include? @repo_secret[:name]
          assert secrets.map(&:name).include? @org_secret[:name]
          assert_equal @test_secret_value, secrets.first.decrypt
        end
      end
    end
  end
end unless GitHub.enterprise?
