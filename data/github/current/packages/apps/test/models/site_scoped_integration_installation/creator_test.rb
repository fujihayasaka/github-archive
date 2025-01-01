# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dogstats_test_helpers"
require "test_helpers/permissions_helper"

class SiteScopedIntegrationInstallation::CreatorTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper
  include PermissionsHelper

  fixtures do
    make_trusted_oauth_apps_owner

    @user        = create(:user)
    @repository  = create(:repository, owner: @user)

    @actions = create(:launch_integration, default_permissions: { "contents" => Permission::Action::Read })
    GitHub.stubs(:launch_github_app).returns(@actions)
    check_suite = create(:check_suite_for_actions_app, repository: @repository)
    @workflow_run = check_suite.workflow_run

    @unlimited_global_integration = create_unlimited_global_integration
  end

  setup do
    GitHub.flipper[:disabled_global_apps].disable
  end

  context ".perform" do
    test "it doesn't create a site scoped installation if the feature is disabled" do
      GitHub.flipper[:disabled_global_apps].enable

      result = SiteScopedIntegrationInstallation::Creator.perform(
        @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
      )

      refute_predicate result, :success?
      expected_message = "Global-Apps is disabled for this integration"
      assert_equal expected_message, result.error
    end

    test "it doesn't create a site scoped installation for non global apps" do
      integration = create(:integration)

      result = SiteScopedIntegrationInstallation::Creator.perform(
        integration, @user, repositories: [@repository], entry_point: :test_case
      )

      refute_predicate result, :success?
      expected_message = "Integration can't be globally installed"
      assert_equal expected_message, result.error
    end

    test "returns a site scoped installation for a user repository" do
      result = SiteScopedIntegrationInstallation::Creator.perform(
        @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
      )

      assert_predicate result, :success?
      site_scoped_installation = result.installation
      assert_predicate site_scoped_installation, :valid?
      assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

      assert_actor_and_subject_granted_in_permissions_table(
        actor:   site_scoped_installation,
        subject: @repository.resources.metadata,
        action:  :read,
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor:   site_scoped_installation,
        subject: @repository.resources.issues,
        action:  :read,
      )

      if @unlimited_global_integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
        struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
          selections: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset
          },
          subject_types_and_actions: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read }
          },
          subject_ids: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id]
          }
        )

        assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
      end
    end

    test "sets the integration_id and target attributes" do
      result = SiteScopedIntegrationInstallation::Creator.perform(
        @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
      )

      assert_predicate result, :success?
      assert result.installation

      site_scoped_installation = result.installation

      assert_equal @unlimited_global_integration.id, site_scoped_installation.integration_id
      assert_equal @user, site_scoped_installation.target
    end

    test "sets the expires_at attribute by default" do
      Timecop.freeze do
        expiry = SiteScopedIntegrationInstallation::Creator::EXPIRATION_WINDOW.from_now

        result = SiteScopedIntegrationInstallation::Creator.perform(
          @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
        )

        assert_predicate result, :success?
        assert result.installation

        site_scoped_installation = result.installation

        # We need to compare using `.to_i` because of the following:
        #
        # Minitest::Assertion: No visible difference in the ActiveSupport::TimeWithZone#inspect output.
        # You should look at the implementation of #== on ActiveSupport::TimeWithZone or its members.
        assert_equal expiry.to_i, site_scoped_installation.expires_at.to_i

        assert_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @repository.resources.metadata,
          action:  :read,
        )

        permission_records = Permission.where(actor: site_scoped_installation)
        assert_equal 1, permission_records.count

        permission = permission_records.first
        assert_equal expiry.to_i, permission.expires_at.to_i
      end
    end

    test "can opt out of expires_at being set" do
      result = SiteScopedIntegrationInstallation::Creator.perform(
        @unlimited_global_integration, @user, repositories: [@repository], expires: false, entry_point: :test_case
      )

      assert_predicate result, :success?
      assert result.installation

      site_scoped_installation = result.installation

      # For some reason I can't get ActiveRecord to state
      # that it's nil through the model.
      #
      # Instead it's returning 0 which is `nil.to_i`
      assert_equal 0, site_scoped_installation.expires_at.to_i

      assert_actor_and_subject_granted_in_permissions_table(
        actor:   site_scoped_installation,
        subject: @repository.resources.metadata,
        action:  :read,
      )

      permission_records = Permission.where(actor: site_scoped_installation)
      assert_equal 1, permission_records.count

      permission = permission_records.first
      assert_equal 0, permission.expires_at.to_i
    end

    test "returns a site scoped installation for an integration in all user repositories" do
      result = SiteScopedIntegrationInstallation::Creator.perform(@unlimited_global_integration, @user, repositories: :all, entry_point: :test_case)

      assert_predicate result, :success?
      assert result.installation

      assert_actor_and_subject_granted_in_permissions_table(
        actor:   result.installation,
        subject: @user.repository_resources.metadata,
        action:  :read,
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor:   result.installation,
        subject: @user.repository_resources.issues,
        action:  :read,
      )

      if @unlimited_global_integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
        struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
          selections: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::All
          },
          subject_types_and_actions: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read }
          }
        )

        assert_same_hash(struct.serialize, result.installation.authorization_details)
      end
    end

    test "grants access to all of the specified resources" do
      docs_repo = create(:repository, :minimal, owner: @user)

      result = SiteScopedIntegrationInstallation::Creator.perform(@unlimited_global_integration, @user, repositories: @user.repositories, entry_point: :test_case)

      assert_predicate result, :success?

      installation = result.installation

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: @repository.resources.metadata,
        action: :read,
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: docs_repo.resources.metadata,
        action: :read,
      )

      if @unlimited_global_integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
        struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
          selections: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset
          },
          subject_types_and_actions: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read }
          },
          subject_ids: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id, docs_repo.id]
          }
        )

        serialized = struct.serialize

        assert_equal serialized["version"], installation.authorization_details["version"]
        assert_same_hash(serialized["selections"], installation.authorization_details["selections"])
        assert_same_hash(serialized["subject_types_and_actions"], installation.authorization_details["subject_types_and_actions"])

        # assert_with_same_hash ensures order leading to flakes.
        expected_subject_ids = T.must(struct.subject_ids)[ScopedInstallations::AuthorizationDetails::ResourceType::Repository]
        assert_same_elements(expected_subject_ids, installation.authorization_details["subject_ids"]["repository"])
      end
    end

    test "grants limited permissions" do
      docs_repo = create(:repository, :minimal, owner: @user)

      integration = create_unlimited_global_integration(permissions: { "metadata" => Permission::Action::Read, "issues" => Permission::Action::Read })

      result = SiteScopedIntegrationInstallation::Creator.perform(
        integration, @user, repositories: @user.repositories, permissions: { "metadata" => Permission::Action::Read }, entry_point: :test_case
      )

      assert_predicate result, :success?

      installation = result.installation

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: @repository.resources.metadata,
        action: :read,
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: @repository.resources.issues,
        action: :read,
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: docs_repo.resources.metadata,
        action: :read,
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: docs_repo.resources.issues,
        action: :read,
      )

      if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
        struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
          selections: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset
          },
          subject_types_and_actions: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read }
          },
          subject_ids: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id, docs_repo.id]
          }
        )

        serialized = struct.serialize

        assert_equal serialized["version"], installation.authorization_details["version"]
        assert_same_hash(serialized["selections"], installation.authorization_details["selections"])
        assert_same_hash(serialized["subject_types_and_actions"], installation.authorization_details["subject_types_and_actions"])

        # assert_with_same_hash ensures order leading to flakes.
        expected_subject_ids = T.must(struct.subject_ids)[ScopedInstallations::AuthorizationDetails::ResourceType::Repository]
        assert_same_elements(expected_subject_ids, installation.authorization_details["subject_ids"]["repository"])
      end
    end

    test "grants organization permissions" do
      org = create(:organization)

      integration = create_unlimited_global_integration(permissions: { "members" => :write })

      result = SiteScopedIntegrationInstallation::Creator.perform(
        integration, org, repositories: org.repositories, permissions: { "members" => :read }, entry_point: :test_case
      )

      assert_predicate result, :success?

      installation = result.installation

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: org.resources.members,
        action: :read,
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: org.resources.members,
        action: :write,
      )

      if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
        struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
          selections: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Organization => ScopedInstallations::AuthorizationDetails::Selection::Subset
          },
          subject_types_and_actions: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Organization => { "members" => Permission::Action::Read }
          },
          subject_ids: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Organization => [org.id]
          }
        )

        assert_same_hash(struct.serialize, installation.authorization_details)
      end
    end

    test "grant codespace permissions for apps with the capability" do
      integration = create_unlimited_global_integration(
        capabilities: {
          static_installation_codespace_permissions: true
        },
        properties: {
          static_installation_codespace_permissions: { "codespace_metadata" => :read }
        },
      )

      codespace = create(:codespace)

      result = SiteScopedIntegrationInstallation::Creator.perform(
        integration, codespace.owner, repositories: [codespace.repository], codespaces: [codespace], entry_point: :test_case
      )

      assert_predicate result, :success?

      installation = result.installation

      assert_actor_and_subject_granted_in_permissions_table(
        actor: installation,
        subject: codespace.resources.codespace_metadata,
        action: :read,
      )

      if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
        struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
          selections: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Codespace => ScopedInstallations::AuthorizationDetails::Selection::Subset,
            ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset
          },
          subject_types_and_actions: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Codespace => { "codespace_metadata" => Permission::Action::Read },
            ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read }
          },
          subject_ids: {
            ScopedInstallations::AuthorizationDetails::ResourceType::Codespace => [codespace.id],
            ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [codespace.repository.id]
          }
        )

        assert_same_hash(struct.serialize, installation.authorization_details)
      end
    end

    test "returns a failure when the permissions check returns a failure" do
      failed_check_result = SiteScopedIntegrationInstallation::Permissions::Result.new(false, reason: :missing_integration)
      SiteScopedIntegrationInstallation::Permissions.any_instance.stubs(:check).returns(failed_check_result)

      result = SiteScopedIntegrationInstallation::Creator.perform(@unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case)

      assert_predicate result, :failed?
      assert_nil result.installation
    end

    test "does not allow internal apps to elevate site scoped installations permissions" do
      Apps::Internal::Registry.configure(
        app: @actions,
        app_alias: :actions,
        id: ->(*) { @actions.id },
        capabilities: { installed_globally: true, limited_access: false },
      )

      result = SiteScopedIntegrationInstallation::Creator.perform(
        @actions, @user, repositories: [@repository], permissions: { "contents" => :write }, entry_point: :test_case
      )
      refute_predicate result, :success?
      expected_error = "The permissions requested are not granted to this integration."
      assert_equal expected_error, result.error
    end

    test "destroys the site scoped installation if granting permissions fails and the record does not expire" do
      assert_no_difference "SiteScopedIntegrationInstallation.count" do
        SiteScopedIntegrationInstallation::Creator.any_instance.stubs(:grant_permissions!).raises(ActiveRecord::ActiveRecordError)

        result = SiteScopedIntegrationInstallation::Creator.perform(
          @unlimited_global_integration,
          @user,
          repositories: [@repository],
          entry_point: :test_case,
          expires: false,
        )

        assert_predicate result, :failed?
        assert_nil result.installation
      end
    end

    # In this scenario, we save a database query and rely on the pt-archiver
    # process to cleanup the impotent SSII record.
    test "does not destroy the site scoped installation if granting permissions fails but the record does expire" do
      assert_difference "SiteScopedIntegrationInstallation.count", 1 do
        SiteScopedIntegrationInstallation::Creator.any_instance.stubs(:grant_permissions!).raises(ActiveRecord::ActiveRecordError)

        result = SiteScopedIntegrationInstallation::Creator.perform(
          @unlimited_global_integration,
          @user,
          repositories: [@repository],
          entry_point: :test_case,
          expires: true
        )

        assert_predicate result, :failed?
        assert_nil result.installation
      end
    end

    context "limited global apps" do
      test "prevents minting tokens on targets that are not accessible" do
        monalisa = create(:user, login: "monalisa")
        hubot = create(:user, login: "hubot")

        integration = create_internal_app_with_capabilities(
          capabilities: {
            installed_globally: true,
            limited_access: true,
          },
          properties: {
            accessible_targets: {
              "monalisa" => [],
            },
          },
        )

        result = SiteScopedIntegrationInstallation::Creator.perform(
          integration, hubot, repositories: [], entry_point: :test_case
        )

        refute_predicate result, :success?
        expected_error = "This integration doesn't have access to the given target"
        assert_equal expected_error, result.error
      end

      test "prevents minting tokens on targets where accessible_targets are not configured" do
        monalisa = create(:user, login: "monalisa")
        hubot = create(:user, login: "hubot")

        integration = create_internal_app_with_capabilities(
          capabilities: {
            installed_globally: true,
            limited_access: true,
          },
          properties: {},
        )

        result = SiteScopedIntegrationInstallation::Creator.perform(
          integration, hubot, repositories: [], entry_point: :test_case
        )

        refute_predicate result, :success?
        expected_error = "This integration doesn't have access to the given target"
        assert_equal expected_error, result.error
      end

      test "prevents minting tokens if at least one repo is not accessible" do
        monalisa = create(:user, login: "monalisa")

        apples   = create(:repository, :minimal, name: "apples", owner: monalisa)
        bananas  = create(:repository, :minimal, name: "bananas", owner: monalisa)
        coconuts = create(:repository, :minimal, name: "coconuts", owner: monalisa)

        integration = create_internal_app_with_capabilities(
          capabilities: {
            installed_globally: true,
            limited_access: true,
          },
          properties: {
            accessible_targets: {
              "monalisa" => %w[apples bananas],
            },
          },
        )

        result = SiteScopedIntegrationInstallation::Creator.perform(
          integration, monalisa, repositories: [apples, bananas, coconuts], entry_point: :test_case
        )

        refute_predicate result, :success?
        expected_error = "This integration doesn't have access to all of the requested repositories"
        assert_equal expected_error, result.error
      end

      test "allows minting tokens for all repos when all repos are accessible" do
        monalisa = create(:user, login: "monalisa")

        apples   = create(:repository, :minimal, name: "apples", owner: monalisa)
        bananas  = create(:repository, :minimal, name: "bananas", owner: monalisa)
        coconuts = create(:repository, :minimal, name: "coconuts", owner: monalisa)

        integration = create_internal_app_with_capabilities(
          capabilities: {
            installed_globally: true,
            limited_access: true,
          },
          properties: {
            accessible_targets: {
              "monalisa" => [],
            },
          },
        )

        result = SiteScopedIntegrationInstallation::Creator.perform(
          integration, monalisa, repositories: [apples, bananas, coconuts], entry_point: :test_case
        )

        assert_predicate result, :success?
      end

      test "is not case sensitive with accessible target logins or repository names" do
        monalisa = create(:user, login: "MoNaLIsA")

        apples   = create(:repository, :minimal, name: "apples", owner: monalisa)
        bananas  = create(:repository, :minimal, name: "bananas", owner: monalisa)
        coconuts = create(:repository, :minimal, name: "coconuts", owner: monalisa)

        hubot = create(:user, login: "hubot")

        hubot_one = create(:repository, :minimal, name: "Some-RepoFor_HUBOT", owner: hubot)

        integration = create_internal_app_with_capabilities(
          capabilities: {
            installed_globally: true,
            limited_access: true,
          },
          properties: {
            accessible_targets: {
              "monalisa" => [],
              "HuBoT" => ["some-repofor_hubot"]
            },
          },
        )

        result = SiteScopedIntegrationInstallation::Creator.perform(
          integration, monalisa, repositories: [apples, bananas, coconuts], entry_point: :test_case
        )

        assert_predicate result, :success?

        result = SiteScopedIntegrationInstallation::Creator.perform(
          integration, hubot, repositories: [hubot_one], entry_point: :test_case
        )

        assert_predicate result, :success?
      end

      test "prevents minting tokens for repos with the same name with different owners" do
        monalisa = create(:user, login: "monalisa")
        hubot = create(:user, login: "hubot")

        _monalisa_apples = create(:repository, :minimal, name: "apples", owner: monalisa)
        hubot_apples    = create(:repository, :minimal, name: "apples", owner: hubot)

        integration = create_internal_app_with_capabilities(
          capabilities: {
            installed_globally: true,
            limited_access: true,
          },
          properties: {
            accessible_targets: {
              "monalisa" => ["apples"],
            },
          },
        )

        result = SiteScopedIntegrationInstallation::Creator.perform(
          integration, monalisa, repositories: [hubot_apples], entry_point: :test_case
        )

        refute_predicate result, :success?
        expected_error = "There is at least one repository that does not exist or is not accessible by the target."
        assert_equal expected_error, result.error
      end
    end

    context "elevated_read_access_on_target" do
      test "does not grant additional access by default if there is an installation but the capability is not available" do
        refute_nil make_integration_installation(integration: @unlimited_global_integration, repository: @repository)

        result = SiteScopedIntegrationInstallation::Creator.perform(
          @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
        )

        assert_predicate result, :success?
        site_scoped_installation = result.installation
        assert_predicate site_scoped_installation, :valid?
        assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

        assert_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @repository.resources.metadata,
          action:  :read,
        )

        refute_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @user.repository_resources.metadata,
          action:  :read,
        )

        if @unlimited_global_integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
          struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
            selections: {
              ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset
            },
            subject_types_and_actions: {
              ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read }
            },
            subject_ids: {
              ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id]
            }
          )

          assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
        end
      end

      test "does not grant additional access, even when specified directly without the app capability" do
        refute_nil make_integration_installation(integration: @unlimited_global_integration, repository: @repository)

        result = SiteScopedIntegrationInstallation::Creator.perform(
          @unlimited_global_integration, @user, repositories: [@repository], elevated_read_access_on_target: true, entry_point: :test_case
        )

        assert_predicate result, :success?
        site_scoped_installation = result.installation
        assert_predicate site_scoped_installation, :valid?
        assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

        assert_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @repository.resources.metadata,
          action:  :read,
        )

        refute_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @user.repository_resources.metadata,
          action:  :read,
        )

        if @unlimited_global_integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
          struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
            selections: {
              ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset
            },
            subject_types_and_actions: {
              ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read }
            },
            subject_ids: {
              ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id]
            }
          )

          assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
        end
      end

      test "does not grant additional access if there isn't an installation" do
        integration = create_internal_app_with_capabilities(
          permissions: { "metadata" => :read },
          capabilities: {
            installed_globally: true,
            elevated_read_access_on_target: true,
            limited_access: false,
          }
        )

        result = SiteScopedIntegrationInstallation::Creator.perform(
          integration, @user, repositories: [@repository], elevated_read_access_on_target: true, entry_point: :test_case
        )

        assert_nil IntegrationInstallation.with_repository(@repository).find_by(target: @user, integration: integration)

        assert_predicate result, :success?
        site_scoped_installation = result.installation

        assert_predicate site_scoped_installation, :valid?
        assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

        assert_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @repository.resources.metadata,
          action:  :read,
        )

        refute_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @user.repository_resources.metadata,
          action:  :read,
        )
      end

      test "does not grant read access on the target if not specified directly" do
        integration = create_internal_app_with_capabilities(
          permissions: { "metadata" => :read },
          capabilities: {
            installed_globally: true,
            elevated_read_access_on_target: true,
            limited_access: false,
          }
        )

        make_integration_installation(repository: @repository, integration: integration)

        result = SiteScopedIntegrationInstallation::Creator.perform(
          integration, @user, repositories: [@repository], entry_point: :test_case
        )

        assert_predicate result, :success?
        site_scoped_installation = result.installation

        assert_predicate site_scoped_installation, :valid?
        assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

        assert_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @repository.resources.metadata,
          action:  :read,
        )

        refute_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @user.repository_resources.metadata,
          action:  :read,
        )
      end

      test "grants read access on the target if specified directly and the repository is part of the installation" do
        integration = create_internal_app_with_capabilities(
          permissions: { "metadata" => :read },
          capabilities: {
            installed_globally: true,
            elevated_read_access_on_target: true,
            limited_access: false,
          }
        )

        make_integration_installation(repository: @repository, integration: integration)

        result = SiteScopedIntegrationInstallation::Creator.perform(
          integration, @user, repositories: [@repository], elevated_read_access_on_target: true, entry_point: :test_case
        )

        assert_predicate result, :success?
        site_scoped_installation = result.installation

        assert_predicate site_scoped_installation, :valid?
        assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

        refute_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @repository.resources.metadata,
          action:  :read,
        )

        assert_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @user.repository_resources.metadata,
          action:  :read,
        )

        if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
          struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
            selections: {
              ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::All
            },
            subject_types_and_actions: {
              ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read }
            }
          )

          assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
        end
      end

      test "grants write access on the repositories requested only" do
        integration = create_internal_app_with_capabilities(
          permissions: { "metadata" => :read, "contents" => :write },
          capabilities: {
            installed_globally: true,
            elevated_read_access_on_target: true,
            limited_access: false,
          }
        )

        make_integration_installation(repository: @repository, integration: integration)

        result = SiteScopedIntegrationInstallation::Creator.perform(
          integration, @user, repositories: [@repository], elevated_read_access_on_target: true, entry_point: :test_case
        )

        assert_predicate result, :success?
        site_scoped_installation = result.installation

        assert_predicate site_scoped_installation, :valid?
        assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

        refute_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @repository.resources.metadata,
          action:  :read,
        )

        assert_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @user.repository_resources.metadata,
          action:  :read,
        )

        assert_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @repository.resources.contents,
          action:  :write,
        )

        assert_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @user.repository_resources.contents,
          action:  :read,
        )

        if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
          struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
            selections: {
              ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::All
            },
            subject_types_and_actions: {
              ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read, "contents" => Permission::Action::Read }
            },
            asymmetric: {
              ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "contents" => { "write" => [@repository.id] } }
            }
          )

          assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
        end
      end

      test "requires all requested repositories are part of the installation" do
        integration = create_internal_app_with_capabilities(
          permissions: { "metadata" => :read, "contents" => :write },
          capabilities: {
            installed_globally: true,
            elevated_read_access_on_target: true,
            limited_access: false,
          }
        )

        repository2 = create(:repository, :minimal, owner: @user)
        make_integration_installation(repository: @repository, integration: integration)

        result = SiteScopedIntegrationInstallation::Creator.perform(
          integration, @user, repositories: [@repository, repository2], entry_point: :test_case
        )

        assert_predicate result, :success?
        site_scoped_installation = result.installation

        assert_predicate site_scoped_installation, :valid?
        assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

        [@repository, repository2].each do |repo|
          assert_actor_and_subject_granted_in_permissions_table(
            actor:   site_scoped_installation,
            subject: repo.resources.metadata,
            action:  :read,
          )
        end

        [@repository, repository2].each do |repo|
          assert_actor_and_subject_granted_in_permissions_table(
            actor:   site_scoped_installation,
            subject: repo.resources.contents,
            action:  :write,
          )
        end

        refute_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @user.repository_resources.metadata,
          action:  :read,
        )

        refute_actor_and_subject_granted_in_permissions_table(
          actor:   site_scoped_installation,
          subject: @user.repository_resources.contents,
          action:  :read,
        )

        if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
          struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
            selections: {
              ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset
            },
            subject_types_and_actions: {
              ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read, "contents" => Permission::Action::Write }
            },
            subject_ids: {
              ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id, repository2.id]
            }
          )

          serialized = struct.serialize

          assert_equal serialized["version"], site_scoped_installation.authorization_details["version"]
          assert_same_hash(serialized["selections"], site_scoped_installation.authorization_details["selections"])
          assert_same_hash(serialized["subject_types_and_actions"], site_scoped_installation.authorization_details["subject_types_and_actions"])

          # assert_with_same_hash ensures order leading to flakes.
          expected_subject_ids = T.must(struct.subject_ids)[ScopedInstallations::AuthorizationDetails::ResourceType::Repository]
          assert_same_elements(expected_subject_ids, site_scoped_installation.authorization_details["subject_ids"]["repository"])
        end
      end
    end

    context "packages" do
      context "when codespaces are present" do
        # Packages Permissions Availability TODO: Keep this until we know what to do with Codespaces.
        # See https://github.com/github/package-registry-team/issues/7344
        test "grants package permissions for all packages accessible to a repo with the relevant access type" do
          codespace = create(:codespace, owner: @user, repository_id: @repository.id)

          repo = create(:repository, owner: @user)
          other_repo = create(:repository, owner: @user)

          make_trusted_oauth_apps_owner
          integration = create(:codespaces_integration, default_permissions: { "packages" => :write, "metadata" => Permission::Action::Read, "contents" => Permission::Action::Read })

          # The secret sauce: to enable Codespaces to work with packages there is a
          # special set of bookeeping tables that store repositories that have
          # access to a package. We use that information in the
          # SiteScopedIntegrationInstallation::*::Creators to grant equivalent
          # `permissions` to Codespaces site scoped installation tokens so that the
          # $GITHUB_TOKEN has access to packages in the Package Registry. *phew!*
          # This creates two packages, each in different repos from the one the codespace is associated with.
          # The IntegrationAllowedPackage rows tell the access logic to create permissions rows for the codespace's
          # repository for each of the packages.
          package_one = create(:registry_package, repository: repo)
          allowed_package_one = create(:integration_allowed_package, package: package_one, integration: integration, access_type: :administration, repository_id: @repository.id)
          package_two = create(:registry_package, repository: other_repo)
          allowed_package_two = create(:integration_allowed_package, package: package_two, integration: integration, access_type: :contents, repository_id: @repository.id)

          # After creating two packages that the codespace should have access to, we have to
          # go through the actual helper methods production would use in order to have the expiration
          # for the installation extended. Using Creator.perform will simply set defaults.
          _, site_scoped_installation = Codespaces::Tokens.grant_repository_access(@user, codespace)

          assert_predicate site_scoped_installation, :valid?
          assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

          subject_one = ::PackageRegistry::PackageSubject.new(id: package_one.id, access_type: allowed_package_one.access_type)
          assert_actor_and_subject_granted_in_permissions_table(
            actor: site_scoped_installation,
            subject: subject_one.resources.administration,
            action: :write
          )

          subject_two = ::PackageRegistry::PackageSubject.new(id: package_two.id, access_type: allowed_package_two.access_type)
          assert_actor_and_subject_granted_in_permissions_table(
            actor: site_scoped_installation,
            subject: subject_two.resources.contents,
            action: :read
          )

          # verify the package permissions are not going to expire before the codespace access
          expiry = Apps::Internal.property(:oauth_access_expiry, app: integration).from_now

          assert package_one_permission = Permission.find_by(actor: site_scoped_installation, subject: subject_one)
          assert package_two_permission = Permission.find_by(actor: site_scoped_installation, subject: subject_two)

          assert_in_delta expiry, package_one_permission&.expires_at, 1.minute
          assert_in_delta expiry, package_two_permission&.expires_at, 1.minute
        end

        test "does not expire package permissions if the installation does not expire" do
          codespace = create(:codespace, owner: @user, repository_id: @repository.id)
          integration = create_internal_app_with_capabilities(
            permissions: { "metadata" => :read, "packages" => :write },
            capabilities: {
              installed_globally: true,
              elevated_read_access_on_target: true,
              limited_access: false,
              manage_packages_permissions: true,
              write_legacy_site_scoped_fine_grained_package_permissions: true
            },
          )
          refute integration.default_permissions.key?("organization_packages")

          result = SiteScopedIntegrationInstallation::Creator.perform(
            integration, @user,
            repositories: [@repository],
            codespaces: [codespace],
            permissions: { "metadata" => :read, "packages" => :write },
            expires: false,
            entry_point: :test_case,
          )

          assert_predicate result, :success?
          assert site_scoped_installation = result.installation
          assert_predicate site_scoped_installation, :valid?

          subject = IntegrationInstallation::AbilityCollection.new(parent: @user, name: "organization_packages", ability_type_prefix: "Organization")
          assert_actor_and_subject_granted_in_permissions_table(actor: site_scoped_installation, subject: subject, action: :write)

          permission_record = Permission.find_by(
            actor_id: site_scoped_installation.ability_id,
            actor_type: site_scoped_installation.ability_type,
            subject_id: subject.ability_id,
            subject_type: subject.ability_type
          )

          refute_nil permission_record
          assert_predicate permission_record&.expires_at, :nil?
        end

        test "grants organization_packages by default for internal apps with the manage_packages_permissions capability" do
          codespace = create(:codespace, owner: @user, repository_id: @repository.id)

          integration = create_internal_app_with_capabilities(
            permissions: { "metadata" => :read, "packages" => :write },
            capabilities: {
              installed_globally: true,
              elevated_read_access_on_target: true,
              limited_access: false,
              manage_packages_permissions: true,
              write_legacy_site_scoped_fine_grained_package_permissions: true,
            },
          )

          refute integration.default_permissions.key?("organization_packages")

          result = SiteScopedIntegrationInstallation::Creator.perform(
            integration, @user, repositories: [@repository], codespaces: [codespace], permissions: { "metadata" => :read, "packages" => :write }, entry_point: :test_case
          )

          assert_predicate result, :success?

          assert site_scoped_installation = result.installation
          assert_predicate site_scoped_installation, :valid?
          assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

          assert site_scoped_installation.permissions.key?("organization_packages")
          assert site_scoped_installation.permissions["organization_packages"].equal? :write

          subject = IntegrationInstallation::AbilityCollection.new(parent: @user, name: "organization_packages", ability_type_prefix: "Organization")
          assert_actor_and_subject_granted_in_permissions_table(actor: site_scoped_installation, subject: subject, action: :write)

          if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
            struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
              selections: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset,
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => ScopedInstallations::AuthorizationDetails::Selection::Subset
              },
              subject_types_and_actions: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read, "packages" => Permission::Action::Write },
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => { "organization_packages" => Permission::Action::Write }
              },
              subject_ids: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id],
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => [@user.id]
              }
            )

            assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
          end
        end

        test "grants package access when requesting all repositories" do
          codespace = create(:codespace, owner: @user, repository_id: @repository.id)

          integration = create_internal_app_with_capabilities(
            permissions: { "metadata" => :read, "packages" => :write },
            capabilities: {
              installed_globally: true,
              elevated_read_access_on_target: true,
              limited_access: false,
              manage_packages_permissions: true,
              write_legacy_site_scoped_fine_grained_package_permissions: true,
            },
          )

          refute integration.default_permissions.key?("organization_packages")

          result = SiteScopedIntegrationInstallation::Creator.perform(
            integration, @user, repositories: SiteScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_REPOSITORIES, codespaces: [codespace], permissions: { "metadata" => :read, "packages" => :write }, entry_point: :test_case
          )

          assert_predicate result, :success?

          assert site_scoped_installation = result.installation
          assert_predicate site_scoped_installation, :valid?
          assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

          assert site_scoped_installation.permissions.key?("organization_packages")
          assert site_scoped_installation.permissions["organization_packages"].equal? :write

          subject = IntegrationInstallation::AbilityCollection.new(parent: @user, name: "organization_packages", ability_type_prefix: "Organization")
          assert_actor_and_subject_granted_in_permissions_table(actor: site_scoped_installation, subject: subject, action: :write)

          if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
            struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
              selections: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::All,
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => ScopedInstallations::AuthorizationDetails::Selection::Subset
              },
              subject_types_and_actions: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read, "packages" => Permission::Action::Write },
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => { "organization_packages" => Permission::Action::Write }
              },
              subject_ids: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => [@user.id]
              }
            )

            assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
          end
        end

        test "grants organization_packages with read-only scope when requested" do
          codespace = create(:codespace, owner: @user, repository_id: @repository.id)

          integration = create_internal_app_with_capabilities(
            permissions: { "metadata" => :read, "packages" => :write },
            capabilities: {
              installed_globally: true,
              elevated_read_access_on_target: true,
              limited_access: false,
              manage_packages_permissions: true,
              write_legacy_site_scoped_fine_grained_package_permissions: true
            },
          )

          refute integration.default_permissions.key?("organization_packages")

          result = SiteScopedIntegrationInstallation::Creator.perform(
            integration, @user, repositories: [@repository], codespaces: [codespace], permissions: { "metadata" => :read, "packages" => :read }, entry_point: :test_case
          )

          assert_predicate result, :success?

          assert site_scoped_installation = result.installation
          assert_predicate site_scoped_installation, :valid?
          assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

          assert site_scoped_installation.permissions.key?("organization_packages")
          assert site_scoped_installation.permissions["organization_packages"].equal? :read

          subject = IntegrationInstallation::AbilityCollection.new(parent: @user, name: "organization_packages", ability_type_prefix: "Organization")
          assert_actor_and_subject_granted_in_permissions_table(actor: site_scoped_installation, subject: subject, action: :read)

          if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
            struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
              selections: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset,
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => ScopedInstallations::AuthorizationDetails::Selection::Subset
              },
              subject_types_and_actions: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read, "packages" => Permission::Action::Read },
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => { "organization_packages" => Permission::Action::Read }
              },
              subject_ids: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id],
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => [@user.id]
              }
            )

            assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
          end
        end

        test "does not grant organization_packages when no packages permission is requested" do
          integration = create_internal_app_with_capabilities(
            permissions: { "metadata" => :read },
            capabilities: {
              installed_globally: true,
              elevated_read_access_on_target: true,
              limited_access: false,
              manage_packages_permissions: true,
              write_legacy_site_scoped_fine_grained_package_permissions: true
            },
          )

          refute integration.default_permissions.key?("organization_packages")

          result = SiteScopedIntegrationInstallation::Creator.perform(
            integration, @user, repositories: [@repository], permissions: { "metadata" => :read }, entry_point: :test_case
          )

          assert_predicate result, :success?

          assert site_scoped_installation = result.installation
          assert_predicate site_scoped_installation, :valid?
          assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

          refute site_scoped_installation.permissions.key?("organization_packages")

          subject = IntegrationInstallation::AbilityCollection.new(parent: @user, name: "organization_packages", ability_type_prefix: "Organization")
          refute_actor_and_subject_granted_in_permissions_table(actor: site_scoped_installation, subject: subject, action: :write)
          refute_actor_and_subject_granted_in_permissions_table(actor: site_scoped_installation, subject: subject, action: :read)

          if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
            struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
              selections: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset,
              },
              subject_types_and_actions: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read },
              },
              subject_ids: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id],
              }
            )

            assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
          end
        end

        test "does not grant organization_packages permission when no packages are requested and the App has organization_packages permission" do
          # This case is yet another indictment of organization_packages.
          #
          # The organization_packages permission is intended to only be used in
          # conjunction with granting individual package permissions. There is
          # no reason for an App to have this permission granted unless
          # package permissions are also being granted. This is so important
          # that we prevent integrators from selecting this permission in the
          # UI and won't grant it on normal installations.
          #
          # See https://github.com/github/github/pull/208903 for more. Also:
          # https://github.com/github/github/blob/2082006c3e65e07dc02548c172ed747cad74554a/packages/apps/app/models/organization/resources.rb#L32
          #
          # Because the SSIIC attempts to grant organization permissions _and_
          # packages permissions as part of .perform it's _possible_, if the
          # App somehow has `organization_packages` in its default version
          # (like Codespaces), to attempt to write duplicate
          # `Organization/organization_permissions` records, which is not
          # allowed in the permissions table.
          #
          # This test gives us confidence that we're not attempting to write
          # organization_packages twice.

          org = create(:organization)
          repository = create(:repository, owner: org)
          integration = create_internal_app_with_capabilities(
            # This _shouldn't_ be possible for 3rd party apps, but is currently
            # possible for the 1st party Codespaces App, which is also probably
            # a mistake.
            permissions: { "metadata" => :read, "packages" => :write, "organization_packages" => :read },
            capabilities: {
              installed_globally: true,
              elevated_read_access_on_target: true,
              limited_access: false,
              manage_packages_permissions: true
            },
          )

          assert integration.default_permissions.key?("organization_packages")

          result = SiteScopedIntegrationInstallation::Creator.perform(
            integration,
            org,
            repositories: [repository],
            # Not requesting any permissions here falls back to the App's
            # default permissions, which includes organization_packages.
            #
            # This simulates the behavior of
            # `Integration#grant_repository_codespace_scoped_installation_on`,
            # which doesn't pass explicit permissions and instead falls back to
            # the app's defaults:
            # https://github.com/github/github/blob/2082006c3e65e07dc02548c172ed747cad74554a/packages/app_security/app/models/oauth_access/provider.rb#L201
            permissions: {},
            entry_point: :test_case
          )

          assert_predicate result, :success?

          assert site_scoped_installation = result.installation
          assert_predicate site_scoped_installation, :valid?
          assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

          refute site_scoped_installation.permissions.key?("organization_packages")

          subject = IntegrationInstallation::AbilityCollection.new(parent: org, name: "organization_packages", ability_type_prefix: "Organization")
          refute_actor_and_subject_granted_in_permissions_table(actor: site_scoped_installation, subject: subject, action: :write)
          refute_actor_and_subject_granted_in_permissions_table(actor: site_scoped_installation, subject: subject, action: :read)

          if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
            struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
              selections: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset,
              },
              subject_types_and_actions: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read, "packages" => Permission::Action::Write },
              },
              subject_ids: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [repository.id],
              }
            )

            assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
          end
        end
      end

      context "when should_grant_packages_permissions: true" do
        # Packages Permissions Availability TODO: Keep this until we know what to do with Codespaces.
        # See https://github.com/github/package-registry-team/issues/7344
        test "grants package permissions for all packages accessible to a repo with the relevant access type" do
          repo = create(:repository, :minimal, owner: @user)
          other_repo = create(:repository, :minimal, owner: @user)

          make_trusted_oauth_apps_owner
          integration = create(:codespaces_integration)

          package = create(:registry_package, repository: repo)
          allowed_package = create(:integration_allowed_package, package: package, integration: integration, access_type: :administration, repository_id: @repository.id)

          package_2 = create(:registry_package, repository: other_repo)
          allowed_package_2 = create(:integration_allowed_package, package: package_2, integration: integration, access_type: :contents, repository_id: @repository.id)

          access = SiteScopedIntegrationInstallation::Creator.perform(
            integration,
            @repository.owner,
            repositories: [@repository],
            permissions: { "contents" => :read, "packages" => :read },
            should_grant_packages_permissions: true,
            entry_point: :test_case,
          )

          assert site_scoped_installation = access.installation
          assert_predicate site_scoped_installation, :valid?
          assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

          subject = ::PackageRegistry::PackageSubject.new(id: package.id, access_type: allowed_package.access_type)
          assert_actor_and_subject_granted_in_permissions_table(
            actor: site_scoped_installation,
            subject: subject.resources.contents,
            action: :read
          )

          refute_actor_and_subject_granted_in_permissions_table(
            actor: site_scoped_installation,
            subject: subject.resources.contents,
            action: :write
          )

          subject_2 = ::PackageRegistry::PackageSubject.new(id: package_2.id, access_type: allowed_package_2.access_type)
          assert_actor_and_subject_granted_in_permissions_table(
            actor: site_scoped_installation,
            subject: subject_2.resources.contents,
            action: :read
          )

          refute_actor_and_subject_granted_in_permissions_table(
            actor: site_scoped_installation,
            subject: subject_2.resources.contents,
            action: :write
          )

          if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
            struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
              selections: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset,
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => ScopedInstallations::AuthorizationDetails::Selection::Subset,
              },
              subject_types_and_actions: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read, "packages" => Permission::Action::Read, "contents" => Permission::Action::Read },
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => { "organization_packages" => Permission::Action::Read }
              },
              subject_ids: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id],
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => [@repository.owner.id],
              },
              asymmetric: {
                ScopedInstallations::AuthorizationDetails::ResourceType::PackageRegistry => {
                  "contents" => { "read" => [subject.ability_id, subject_2.ability_id] }
                }
              }
            )

            serialized = struct.serialize

            assert_equal serialized["version"], site_scoped_installation.authorization_details["version"]
            assert_same_hash(serialized["selections"], site_scoped_installation.authorization_details["selections"])
            assert_same_hash(serialized["subject_ids"], site_scoped_installation.authorization_details["subject_ids"])
            assert_same_hash(serialized["subject_types_and_actions"], site_scoped_installation.authorization_details["subject_types_and_actions"])

            # assert_with_same_hash ensures order leading to flakes.
            expected = T.must(T.must(T.must(struct.asymmetric)[ScopedInstallations::AuthorizationDetails::ResourceType::PackageRegistry])["contents"])["read"]
            actual = site_scoped_installation.authorization_details.dig("asymmetric", "package", "contents", "read")

            assert_same_elements(expected, actual)
          end
        end
      end

      context "when granting extended permissions" do
        test "grants extended permissions for pull requests" do
          forker = create(:user)
          repository_fork = create(:fork_repository, forker: forker, fork_repo: @repository, from_example: :pull_request_fork)

          example_repo :pull_request_fork, @repository

          issue = create(:issue, repository: @repository, user: forker, created_at: 5.hours.ago, assignee: @user)
          pull  = create(:pull_request,
            repository: @repository,
            base_repository: @repository,
            base_user: @repository.owner,
            base_ref: "master",
            head_repository: repository_fork,
            head_user: repository_fork.owner,
            head_ref: "topic",
            title: "some title",
            body: "some body",
            issue: issue,
            user: forker,
          )

          make_trusted_oauth_apps_owner

          access = SiteScopedIntegrationInstallation::Creator.perform(
            @unlimited_global_integration,
            @repository.owner,
            repositories: [@repository],
            permissions: { "metadata" => Permission::Action::Read },
            extended_permissions: [
              {
                "repository_id" => @repository.id,
                "pull_requests" => [
                  {
                    "number" => pull.number,
                    "permissions" => {
                      "sarifs" => "write"
                    }
                  }
                ]
              }
            ],
            entry_point: :test_case,
          )

          assert site_scoped_installation = access.installation
          assert_predicate site_scoped_installation, :valid?
          assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

          assert_actor_and_subject_granted_in_permissions_table(
            actor: site_scoped_installation,
            subject: pull.resources.sarifs,
            action: :write
          )

          assert_actor_and_subject_granted_in_permissions_table(
            actor: site_scoped_installation,
            subject: @repository.resources.metadata,
            action: :read
          )

          if @unlimited_global_integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
            struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
              selections: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset,
              },
              subject_types_and_actions: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read }
              },
              subject_ids: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id],
              },
              asymmetric: {
                ScopedInstallations::AuthorizationDetails::ResourceType::PullRequest => {
                  "sarifs" => { "write" => [pull.resources.sarifs.ability_id] }
                }
              }
            )

            assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
          end
        end

        test "grants permission on workflow runs" do
          access = SiteScopedIntegrationInstallation::Creator.perform(
            @unlimited_global_integration,
            @repository.owner,
            repositories: [@repository],
            permissions: { "metadata" => :read },
            extended_permissions: [
              {
                "repository_id" => @repository.id,
                "workflow_runs" => [
                  {
                    "id" => @workflow_run.id,
                    "permissions" => {
                      "codespaces_prebuild" => "write"
                    }
                  }
                ]
              }
            ],
            entry_point: :test_case,
          )

          assert site_scoped_installation = access.installation
          assert_predicate site_scoped_installation, :valid?
          assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

          assert_actor_and_subject_granted_in_permissions_table(
            actor: site_scoped_installation,
            subject: @workflow_run.resources.codespaces_prebuild,
            action: :write
          )

          assert_actor_and_subject_granted_in_permissions_table(
            actor: site_scoped_installation,
            subject: @repository.resources.metadata,
            action: :read
          )

          if @unlimited_global_integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
            struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
              selections: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset,
              },
              subject_types_and_actions: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read }
              },
              subject_ids: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id],
              },
              asymmetric: {
                ScopedInstallations::AuthorizationDetails::ResourceType::WorkflowRun => {
                  "codespaces_prebuild" => { "write" => [@workflow_run.resources.codespaces_prebuild.ability_id] }
                }
              }
            )

            assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
          end
        end
      end

      # Packages Permissions Availability TODO: Keep this until we know what to do with Codespaces.
      # See https://github.com/github/package-registry-team/issues/7344
      context "write_legacy_site_scoped_fine_grained_package_permissions capability" do
        test "writes fine grained package permission rows for all packages when capabilty is present (Codespaces)" do
          repo = create(:repository, :minimal, owner: @user)
          integration = create(:codespaces_integration)

          package = create(:registry_package, repository: repo)
          allowed_package = create(:integration_allowed_package, package: package, integration: integration, access_type: :administration, repository_id: @repository.id)

          access = SiteScopedIntegrationInstallation::Creator.perform(
            integration,
            @repository.owner,
            repositories: [@repository],
            permissions: { "contents" => :read, "packages" => :read },
            should_grant_packages_permissions: true,
            entry_point: :test_case,
          )

          assert site_scoped_installation = access.installation
          assert_predicate site_scoped_installation, :valid?
          assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

          subject = ::PackageRegistry::PackageSubject.new(id: package.id, access_type: allowed_package.access_type)
          assert_actor_and_subject_granted_in_permissions_table(
            actor: site_scoped_installation,
            subject: subject.resources.contents,
            action: :read
          )

          if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
            struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
              selections: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset,
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => ScopedInstallations::AuthorizationDetails::Selection::Subset
              },
              subject_types_and_actions: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read, "contents" => Permission::Action::Read, "packages" => Permission::Action::Read },
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => { "organization_packages" => Permission::Action::Read }
              },
              subject_ids: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id],
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => [@user.id],
              },
              asymmetric: {
                ScopedInstallations::AuthorizationDetails::ResourceType::PackageRegistry => {
                  "contents" => { "read" => [subject.resources.contents.ability_id] }
                }
              }
            )

            assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
          end
        end

        test "does not write fine grained package permission rows for all packages when capabilty is absent (Actions Global App)" do
          repo = create(:repository, :minimal, owner: @user)
          integration = create_unlimited_global_integration(
            permissions: { "contents" => :read, "packages" => :read },
            capabilities: {
              manage_packages_permissions: true,
              # Note how write_legacy_site_scoped_fine_grained_package_permissions is not present.
            })

          package = create(:registry_package, repository: repo)
          allowed_package = create(:integration_allowed_package, package: package, integration: integration, access_type: :administration, repository_id: @repository.id)

          access = SiteScopedIntegrationInstallation::Creator.perform(
            integration,
            @repository.owner,
            repositories: [@repository],
            permissions: { "contents" => :read, "packages" => :read },
            should_grant_packages_permissions: true,
            entry_point: :test_case,
          )

          assert site_scoped_installation = access.installation
          assert_predicate site_scoped_installation, :valid?
          assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

          subject = ::PackageRegistry::PackageSubject.new(id: package.id, access_type: allowed_package.access_type)
          refute_actor_and_subject_granted_in_permissions_table(
            actor: site_scoped_installation,
            subject: subject.resources.contents,
            action: :read
          )

          if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
            struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
              selections: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset,
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => ScopedInstallations::AuthorizationDetails::Selection::Subset
              },
              subject_types_and_actions: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read, "contents" => Permission::Action::Read, "packages" => Permission::Action::Read },
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => { "organization_packages" => Permission::Action::Read }
              },
              subject_ids: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id],
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => [@user.id],
              }
            )

            assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
          end
        end
      end

      context "when limiting packages permission writing" do
        # Packages Permissions Availability TODO: Keep this until we know what to do with Codespaces.
        # See https://github.com/github/package-registry-team/issues/7344
        test "grants package permissions for all packages when rows are under max limit" do
          GitHub.flipper[:installations_max_packages_grantable].enable

          repo = create(:repository, :minimal, owner: @user)
          integration = create(:codespaces_integration)

          package = create(:registry_package, repository: repo)
          allowed_package = create(:integration_allowed_package, package: package, integration: integration, access_type: :administration, repository_id: @repository.id)

          access = SiteScopedIntegrationInstallation::Creator.perform(
            integration,
            @repository.owner,
            repositories: [@repository],
            permissions: { "contents" => :read, "packages" => :read },
            should_grant_packages_permissions: true,
            entry_point: :test_case,
          )

          assert site_scoped_installation = access.installation
          assert_predicate site_scoped_installation, :valid?
          assert site_scoped_installation.is_a?(SiteScopedIntegrationInstallation)

          subject = ::PackageRegistry::PackageSubject.new(id: package.id, access_type: allowed_package.access_type)
          assert_actor_and_subject_granted_in_permissions_table(
            actor: site_scoped_installation,
            subject: subject.resources.contents,
            action: :read
          )

          if integration.feature_enabled?(:write_authorization_details_for_site_scoped_integration_installations)
            struct = ScopedInstallations::AuthorizationDetails::Structs::V1.new(
              selections: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => ScopedInstallations::AuthorizationDetails::Selection::Subset,
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => ScopedInstallations::AuthorizationDetails::Selection::Subset
              },
              subject_types_and_actions: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => { "metadata" => Permission::Action::Read, "contents" => Permission::Action::Read, "packages" => Permission::Action::Read },
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => { "organization_packages" => Permission::Action::Read }
              },
              subject_ids: {
                ScopedInstallations::AuthorizationDetails::ResourceType::Repository => [@repository.id],
                ScopedInstallations::AuthorizationDetails::ResourceType::Organization => [@user.id],
              },
              asymmetric: {
                ScopedInstallations::AuthorizationDetails::ResourceType::PackageRegistry => {
                  "contents" => { "read" => [subject.resources.contents.ability_id] }
                }
              }
            )

            assert_same_hash(struct.serialize, site_scoped_installation.authorization_details)
          end
        end

        # Packages Permissions Availability TODO: Keep this until we know what to do with Codespaces.
        # See https://github.com/github/package-registry-team/issues/7344
        test "blocks package permissions for all packages when rows are over max limit" do
          GitHub.flipper[:installations_max_packages_grantable].enable
          @user.set_max_packages_authorizable_per_token(1, @user)

          repo = create(:repository, :minimal, owner: @user)
          other_repo = create(:repository, :minimal, owner: @user)

          integration = create(:codespaces_integration)

          package = create(:registry_package, repository: repo)
          create(:integration_allowed_package, package: package, integration: integration, access_type: :administration, repository_id: @repository.id)

          package_2 = create(:registry_package, repository: other_repo)
          create(:integration_allowed_package, package: package_2, integration: integration, access_type: :contents, repository_id: @repository.id)

          access = SiteScopedIntegrationInstallation::Creator.perform(
            integration,
            @repository.owner,
            repositories: [@repository],
            permissions: { "contents" => :read, "packages" => :read },
            should_grant_packages_permissions: true,
            entry_point: :test_case,
          )

          assert_nil access.installation
          assert_match(/Too many packages for installation. Please supply up to 1 package./, access.error)
        end

        # Packages Permissions Availability TODO: Keep this until we know what to do with Codespaces.
        # See https://github.com/github/package-registry-team/issues/7344
        test "logs max package exceptions when feature flag is on" do
          GitHub.flipper[:installations_max_packages_grantable].enable
          @user.set_max_packages_authorizable_per_token(1, @user)

          repo = create(:repository, :minimal, owner: @user)
          other_repo = create(:repository, :minimal, owner: @user)

          integration = create(:codespaces_integration)

          package = create(:registry_package, repository: repo)
          create(:integration_allowed_package, package: package, integration: integration, access_type: :administration, repository_id: @repository.id)

          package_2 = create(:registry_package, repository: other_repo)
          create(:integration_allowed_package, package: package_2, integration: integration, access_type: :contents, repository_id: @repository.id)

          expected_log = {
            "Body" => "Detected an App creating a scoped installation access token exceeding MAX_PACKAGES_ROWS",
            "gh.integration.id" => integration.id,
            "gh.installation.packages_count" => 2,
            "gh.installation.target.id" => @user.id,
            "gh.installation.max_repos_flipper_enabled" => true
          }

          assert_logged(**expected_log) do
            SiteScopedIntegrationInstallation::Creator.perform(
              integration,
              @repository.owner,
              repositories: [@repository],
              permissions: { "contents" => :read, "packages" => :read },
              should_grant_packages_permissions: true,
              entry_point: :test_case,
            )
          end
        end

        # Packages Permissions Availability TODO: Keep this until we know what to do with Codespaces.
        # See https://github.com/github/package-registry-team/issues/7344
        test "logs max package exceptions when feature flag is off" do
          GitHub.flipper[:installations_max_packages_grantable].disable
          @user.set_max_packages_authorizable_per_token(1, @user)

          repo = create(:repository, :minimal, owner: @user)
          other_repo = create(:repository, :minimal, owner: @user)

          integration = create(:codespaces_integration)

          package = create(:registry_package, repository: repo)
          create(:integration_allowed_package, package: package, integration: integration, access_type: :administration, repository_id: @repository.id)

          package_2 = create(:registry_package, repository: other_repo)
          create(:integration_allowed_package, package: package_2, integration: integration, access_type: :contents, repository_id: @repository.id)

          expected_log = {
            "Body" => "Detected an App creating a scoped installation access token exceeding MAX_PACKAGES_ROWS",
            "gh.integration.id" => integration.id,
            "gh.installation.packages_count" => 2,
            "gh.installation.target.id" => @user.id,
            "gh.installation.max_repos_flipper_enabled" => false
          }

          assert_logged(**expected_log) do
            SiteScopedIntegrationInstallation::Creator.perform(
              integration,
              @repository.owner,
              repositories: [@repository],
              permissions: { "contents" => :read, "packages" => :read },
              should_grant_packages_permissions: true,
              entry_point: :test_case,
            )
          end
        end
      end
    end
  end

  context ".perform_with_cache" do
    test "uses the cached installation if one is available" do
      with_cache_enabled do
        result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
          @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
        )
        assert_predicate result, :success?

        installation_id = result.installation.id

        assert_no_difference "SiteScopedIntegrationInstallation.count" do
          result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
            @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
          )

          assert_predicate result, :success?
          assert_predicate result, :found_cached?
        end

        assert_equal installation_id, result.installation.id
      end
    end

    test "does not use the cache if the installation is expired" do
      with_cache_enabled do
        result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
          @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
        )
        assert_predicate result, :success?

        installation = result.installation
        installation_id = installation.id
        installation.update_attribute(:expires_at, 2.days.ago)
        assert_predicate installation.reload, :expired?

        assert_difference "SiteScopedIntegrationInstallation.count", 1 do
          result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
            @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
          )

          assert_predicate result, :success?
          refute_predicate result, :found_cached?
        end

        refute_equal installation_id, result.installation.id
      end
    end

    test "asynchronously bumps the installation (and permissions) expiration" do
      with_cache_enabled do
        integration = @unlimited_global_integration
        result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
          integration, @user, repositories: [@repository], entry_point: :test_case
        )
        assert_predicate result, :success?

        installation = result.installation
        installation_id = installation.id
        installation.update_attribute(:expires_at, 2.hours.from_now)
        refute_predicate installation.reload, :expired?

        Timecop.freeze do
          expected_job = ScopedIntegrationInstallableExpirationExtensionJob
          assert_performed_with(job: expected_job, args: [installation, 25.hours.from_now, { entry_point: :test_case }]) do
            assert_no_difference "SiteScopedIntegrationInstallation.count" do
              result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
                integration, @user, repositories: [@repository], entry_point: :test_case
              )
              assert_predicate result, :success?
            end

            assert_equal 25.hours.from_now.to_i, installation.reload.expires_at.to_i
            assert_equal installation_id, result.installation.id
          end
        end
      end
    end

    test "does not bump the installation (and permissions) expiration if expiration is not with threshold" do
      with_cache_enabled do
        integration = @unlimited_global_integration
        result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
          integration, @user, repositories: [@repository], entry_point: :test_case
        )
        assert_predicate result, :success?

        installation = result.installation
        installation_id = installation.id

        Timecop.freeze do
          installation.update_attribute(:expires_at, 6.hours.from_now)
          refute_predicate installation.reload, :expired?
          assert_no_performed_jobs(only: ScopedIntegrationInstallableExpirationExtensionJob) do
            assert_no_difference "ScopedIntegrationInstallation.count" do
              result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
                integration, @user, repositories: [@repository], entry_point: :test_case
              )
              assert_predicate result, :success?
            end
          end

          assert_equal 6.hours.from_now.to_i, installation.reload.expires_at.to_i, "Expected expires_at not to be bumped"
          assert_equal installation_id, result.installation.id
        end
      end
    end

    test "updates the rate-limit of a cached ssii if a new rate-limit is passed when ff enabled" do
      GitHub.flipper[:site_scoped_installation_cache_key_without_rate_limit].enable

      with_cache_enabled do
        integration = @unlimited_global_integration

        result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
          integration, @user, repositories: [@repository], entry_point: :test_case, rate_limit: 500,
        )
        assert_predicate result, :success?

        installation_id = result.installation.id
        assert_equal 500, result.installation.rate_limit

        assert_no_difference "SiteScopedIntegrationInstallation.count" do
          result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
            integration, @user, repositories: [@repository], entry_point: :test_case, rate_limit: 1000,
          )

          assert_predicate result, :success?
          assert_predicate result, :found_cached?
          assert_equal 1000, result.installation.rate_limit
          assert_dogstats_increment(1, "site_scoped_integration_installation.creator.rate_limit_changed")
        end

        assert_equal installation_id, result.installation.id
      end
    end

    test "does not touch a cached ssii if the same rate-limit is passed" do
      GitHub.flipper[:site_scoped_installation_cache_key_without_rate_limit].enable

      with_cache_enabled do
        installation_id, updated_at = Timecop.travel(1.hour.ago) do
          result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
            @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case, rate_limit: 500,
          )
          assert_predicate result, :success?
          assert_equal 500, result.installation.rate_limit
          [result.installation.id, result.installation.updated_at]
        end

        assert_no_difference "SiteScopedIntegrationInstallation.count" do
          result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
            @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case, rate_limit: 500,
          )

          assert_predicate result, :success?
          assert_predicate result, :found_cached?
          assert_equal installation_id, result.installation.id
          assert_equal 500, result.installation.rate_limit
          assert_equal updated_at.to_i, result.installation.updated_at.to_i
          refute_dogstats_increment("site_scoped_integration_installation.creator.rate_limit_changed")
        end
      end
    end

    test "creates a new record if the cached record was destroyed" do
      with_cache_enabled do
        result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
          @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
        )
        assert_predicate result, :success?
        cached_installation_id = result.installation.id
        result.installation.destroy

        assert_difference "SiteScopedIntegrationInstallation.count", 1 do
          result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
            @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
          )
          assert_predicate result, :success?
        end

        refute_equal cached_installation_id, result.installation.id
      end
    end

    test "does not use the cached site scoped installation if repositories requested are no longer available" do
      with_cache_enabled do
        result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
          @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
        )
        assert_predicate result, :success?

        # transfer repo to another target
        other_user = create(:user)
        assert @repository.transfer_ownership_to(other_user, actor: @user)

        assert_no_difference "SiteScopedIntegrationInstallation.count" do
          result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
            @unlimited_global_integration, @user.reload, repositories: [@repository], entry_point: :test_case
          )

          assert_predicate result, :failed?
          expected_error = "There is at least one repository that does not exist or is not accessible by the target."
          assert_equal expected_error, result.error
        end
      end
    end

    test "does not use cached installation if the permissions requested are no longer available" do
      with_cache_enabled do
        integration = create_unlimited_global_integration(permissions: { "metadata" => :read, "contents" => :write })
        result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
          integration, @user,
          repositories: [@repository],
          permissions: { "metadata" => :read, "contents" => :write },
          entry_point: :test_case,
        )
        assert_predicate result, :success?

        integration.update(default_permissions: { "metadata" => :read })
        integration.reload

        assert_no_difference "SiteScopedIntegrationInstallation.count" do
          result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
            integration, @user,
            repositories: [@repository],
            permissions: { "metadata" => :read, "contents" => :write },
            entry_point: :test_case,
          )
          assert_predicate result, :failed?
          assert_equal "The permissions requested are not granted to this integration.", result.error
        end
      end
    end

    test "uses the cached installation when installating on :all repositories" do
      with_cache_enabled do
        result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
          @unlimited_global_integration, @user, repositories: :all, entry_point: :test_case
        )
        assert_predicate result, :success?

        installation_id = result.installation.id

        assert_no_difference "SiteScopedIntegrationInstallation.count" do
          result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
            @unlimited_global_integration, @user, repositories: :all, entry_point: :test_case
          )

          assert_predicate result, :success?
          assert_predicate result, :found_cached?
        end

        assert_equal installation_id, result.installation.id
      end
    end

    test "does not use cached site scoped installation if the integration was updated" do
      with_cache_enabled do
        previous_result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
          @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
        )
        assert_predicate previous_result, :success?
        previous_site_scoped_installation_id = previous_result.installation.id

        Timecop.travel(2.hours.from_now) do
          @unlimited_global_integration.touch

          assert_difference "SiteScopedIntegrationInstallation.count", 1 do
            # Create a new site scoped installation
            latest_result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
              @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
            )
            assert_predicate latest_result, :success?

            latest_site_scoped_installation_id = latest_result.installation.id
            refute_equal previous_site_scoped_installation_id, latest_site_scoped_installation_id
          end
        end
      end
    end

    test "does not use cached site scoped installation if a different rate-limit is passed" do
      # TODO(jpemberthy): remove the whole test once the FF is promoted.
      GitHub.flipper[:site_scoped_installation_cache_key_without_rate_limit].disable

      with_cache_enabled do
        previous_result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
          @unlimited_global_integration, @user, repositories: [@repository], entry_point: :test_case
        )
        assert_predicate previous_result, :success?
        previous_site_scoped_installation_id = previous_result.installation.id

        @unlimited_global_integration.touch

        assert_difference "SiteScopedIntegrationInstallation.count", 1 do
          # Create a new site scoped installation
          latest_result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
            @unlimited_global_integration, @user, repositories: [@repository], rate_limit: 5_000, entry_point: :test_case
          )
          assert_predicate latest_result, :success?

          latest_site_scoped_installation_id = latest_result.installation.id
          refute_equal previous_site_scoped_installation_id, latest_site_scoped_installation_id
        end
      end
    end

    test "does not use cached site scoped installation for different codespaces" do
      with_cache_enabled do
        codespace = create(:codespace, owner: @user, repository_id: @repository.id)

        previous_result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
          @unlimited_global_integration, @user, repositories: [@repository], codespaces: [codespace], entry_point: :test_case
        )
        assert_predicate previous_result, :success?
        previous_site_scoped_installation_id = previous_result.installation.id

        other_codespace = create(:codespace, owner: @user, repository_id: @repository.id)

        assert_difference "SiteScopedIntegrationInstallation.count", 1 do
          # Create a new site scoped installation
          latest_result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
            @unlimited_global_integration, @user, repositories: [@repository], codespaces: [other_codespace], entry_point: :test_case
          )
          assert_predicate latest_result, :success?

          latest_site_scoped_installation_id = latest_result.installation.id
          refute_equal previous_site_scoped_installation_id, latest_site_scoped_installation_id
        end
      end
    end
  end

  context "instrumentation" do
    test "creation" do
      events = subscribe "site_scoped_integration_installation.create"

      user = create(:user)
      repo = create(:repository, :minimal, owner: user)
      integration = create_unlimited_global_integration(
        permissions: { "metadata" => :read, "issues" => :read },
      )

      result = SiteScopedIntegrationInstallation::Creator.perform(
        integration, user, repositories: [repo], entry_point: :test_case
      )
      assert_predicate result, :success?
      installation = result.installation

      expected_payload = {}.tap do |payload|
        payload[:site_scoped_integration_installation]    = installation.name
        payload[:site_scoped_integration_installation_id] = installation.id
        payload[:integration]                             = integration.name
        payload[:integration_id]                          = integration.id
        payload[:user]                                    = user.to_s
        payload[:user_id]                                 = user.id
        payload[:permissions]                             = { "metadata" => :read, "issues" => :read }
      end

      assert event = events.pop, "expected an instrument creation event"
      assert_equal "site_scoped_integration_installation.create", event.name
      assert_equal expected_payload, event.payload
    end

    test "does instrument proper stats when transactions are disabled" do
      user = create(:user)
      repo = create(:repository, :minimal, owner: user)
      integration = create_unlimited_global_integration(
        permissions: { "metadata" => :read, "issues" => :read },
      )

      result = SiteScopedIntegrationInstallation::Creator.perform(
        integration, user, repositories: [repo]
      )
      assert_predicate result, :success?
      installation = result.installation

      expected_tags = ["result:success"]
      assert_dogstats_increment("site_scoped_integration_installation.create", tags: expected_tags)
    end
  end

  context "writing permissions correctly" do
    test "it uses the .grant_permissions! method" do
      user = create(:user)
      repo = create(:repository, :minimal, owner: user)
      integration = create_unlimited_global_integration(
        permissions: { "metadata" => :read, "issues" => :read },
      )

      Permissions::Service.expects(:grant_permissions).never

      result = SiteScopedIntegrationInstallation::Creator.perform(
        integration, user, repositories: [repo]
      )

      assert_predicate result, :success?

      assert_actor_and_subject_granted_in_permissions_table(
        actor:   result.installation,
        subject: repo.resources.metadata,
        action:  :read,
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor:   result.installation,
        subject: repo.resources.issues,
        action:  :read,
      )
    end
  end
end
