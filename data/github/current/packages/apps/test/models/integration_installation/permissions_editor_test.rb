# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class IntegrationInstallationPermissionsEditorEditingAnIntegrationInstallationTest < GitHub::TestCase
  include PermissionsHelper

  fixtures do
    @integration = create(:integration, default_permissions: { "metadata" => :read, "contents" => :read, "members" => :read })
    @repo_integration = create(:integration, default_permissions: { "metadata" => :read })
    @admin       = create(:user, login: "the-admin")
    @repo_admin  = create(:user, login: "repo-admin")
    @org         = create(:organization, login: "ACME", admin: @admin)
    @business    = create(:business, owners: [@admin])

    @repo = create(:repository, :minimal, owner: @org, name: "repo")

    @team = create(:team, organization: @org)
    @team.add_member(@repo_admin)
    @team.add_repository(@repo, :admin)
  end

  context ".perform" do
    test "returns a failure when the target is a personal account that is not the installer's account" do
      other_user = create(:user, login: "other-user")

      installation = make_integration_installation(repository: create(:repository, :minimal, owner: other_user))
      version = installation.integration.versions.create(default_permissions: { "contents" => :read })

      result = IntegrationInstallation::PermissionsEditor.perform(
        installation,
        editor: @admin,
        version: version,
        entry_point: :test_case,
      )

      assert_predicate result, :failed?
      assert_equal "You do not have permission to edit integrations on other-user", result.error
    end

    test "returns a failure when the target is an org but the installer is not an owner of the org" do
      member = create(:user)
      @org.add_member(member)

      installation = make_integration_installation(repository: @repo)
      version = installation.integration.versions.create(default_permissions: { "members" => :read })

      result = IntegrationInstallation::PermissionsEditor.perform(
        installation,
        editor: member,
        version: version,
        entry_point: :test_case,
      )

      assert_predicate result, :failed?
      assert_equal "You do not have permission to edit integrations on ACME", result.error
    end

    test "returns a failure when the new version doesn't belong to the integration" do
      version      = create(:integration) .latest_version
      installation = make_integration_installation(target: @admin)

      result = IntegrationInstallation::PermissionsEditor.perform(
        installation,
        editor: @admin,
        version: version,
        entry_point: :test_case,
      )

      assert_predicate result, :failed?
      assert_equal "Version does not belong to integration", result.error
    end

    test "returns an installation with the updated version number" do
      installation = make_integration_installation(target: @admin)
      version = installation.integration.versions.create(default_permissions: { "contents" => :read })

      result = IntegrationInstallation::PermissionsEditor.perform(
        installation,
        editor: @admin,
        version: version,
        entry_point: :test_case,
      )

      assert_equal result.installation.integration_version_id,     version.id
      assert_equal result.installation.integration_version_number, version.number
    end

    test "returns a failure when the target is an org and the installer is a repo admin on only some installed repos when feature flag is enabled" do
      non_adminable_repo = create(:repository, :minimal, owner: @org, name: "non-adminable-repo")

      installation = make_integration_installation(repositories: [@repo, non_adminable_repo], permissions: { "metadata" => :read })
      version = installation.integration.versions.create(default_permissions: { "metadata" => :read, "contents" => :read })

      result = IntegrationInstallation::PermissionsEditor.perform(
        installation,
        editor: @repo_admin,
        version: version,
        entry_point: :test_case,
      )

      assert_predicate result, :failed?
      assert_equal "You do not have permission to edit integrations on ACME", result.error
    end

    test "returns an installation with the updated version number when the target is an org and the installer is a repo admin when feature flag is enabled" do
      installation = make_integration_installation(repository: @repo, integration: @repo_integration)
      version = installation.integration.versions.create(default_permissions: { "metadata" => :read, "contents" => :read })

      result = IntegrationInstallation::PermissionsEditor.perform(
        installation,
        editor: @repo_admin,
        version: version,
        entry_point: :test_case,
      )

      assert_predicate result, :success?, result.error
      assert_equal result.installation.integration_version_id,     version.id
      assert_equal result.installation.integration_version_number, version.number
    end

    test "returns a failure when the target is an org and the installer is a repo admin when feature flag is enabled with org-only permissions" do
      installation = make_integration_installation(repository: @repo)
      version = installation.integration.versions.create(default_permissions: { "members" => :read })

      result = IntegrationInstallation::PermissionsEditor.perform(
        installation,
        editor: @repo_admin,
        version: version,
        entry_point: :test_case,
      )

      assert_predicate result, :failed?
      assert_equal "You do not have permission to edit integrations on ACME", result.error
    end

    test "returns a failure when the repository permisssions include `administration` write but the actor is an admin outside collaborator" do
      outside_collaborator = create(:user, login: "outside-collaborator")
      @repo.add_member(outside_collaborator, action: :admin)
      assert @repo.adminable_by?(outside_collaborator)

      installation = make_integration_installation(repository: @repo, permissions: { "metadata" => :read })
      version = installation.integration.versions.create(default_permissions: { "metadata" => :read, "administration" => :write })

      result = IntegrationInstallation::PermissionsEditor.perform(
        installation,
        editor: outside_collaborator,
        version: version,
        entry_point: :test_case,
      )

      assert_predicate result, :failed?
      assert_equal "You do not have permission to edit integrations on ACME", result.error
    end

    test "queues a SyncScopedIntegrationInstallationsJob" do
      installation = make_integration_installation(repository: @repo, integration: @repo_integration)

      old_version = installation.version
      new_version = installation.integration.versions.create(default_permissions: { "metadata" => :read, "contents" => :read })

      assert_enqueued_with(job: SyncScopedIntegrationInstallationsJob, args: [installation, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case]) do
        IntegrationInstallation::PermissionsEditor.perform(installation, editor: @repo_admin, version: new_version, entry_point: :test_case)
      end
    end

    context "changes the permissions" do
      context "installs new permissions" do
        context "on installations that are installed on Users" do
          test "successfully updates the installation's permissions" do
            old_permissions = { "metadata" => :read, "contents" => :write }

            new_permissions = { "metadata" => :read, "single_file" => :write }
            new_single_file_name = ".github/ISSUE_TEMPLATE/project_tracking.md"

            integration  = create(:integration, default_permissions: old_permissions)
            installation = make_integration_installation(target: @admin, integration: integration)

            assert_equal(old_permissions, installation.permissions)
            assert_equal(old_permissions, installation.get_cached_permissions)

            version = integration.versions.create(default_permissions: new_permissions, single_file_name: new_single_file_name)
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal(new_permissions, result.installation.permissions)
            assert_equal(new_permissions, result.installation.get_cached_permissions)

            permissions_cache = result.installation.permissions_cache.deep_transform_values(&:to_sym)
            assert_equal(new_permissions, permissions_cache)
          end
        end

        context "on installations that are installed on Organizations" do
          test "successfully updates the installation's permissions" do
            integration  = create(:integration, default_permissions: { "metadata" => :read, "members" => :write })
            installation = make_integration_installation(target: @org, integration: integration)

            assert_equal({ "metadata" => :read, "members" => :write }, installation.permissions)

            version = integration.versions.create(default_permissions: { "organization_projects" => :write })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal({ "organization_projects" => :write }, result.installation.permissions)
          end
        end

        context "installations that are installed on Businesses" do
          test "successfully updates the installation's permissions" do
            installation = make_integration_installation(target: @business, permissions: { "enterprise_administration" => :read })

            assert_equal({ "enterprise_administration" => :read }, installation.permissions)

            version = create(:integration_version, integration: installation.integration, default_permissions: { "enterprise_administration" => :write })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_predicate result, :success?
            assert_equal({ "enterprise_administration" => :write }, result.installation.permissions)
          end

          test "writes to permissions table" do
            installation = make_integration_installation(target: @business, permissions: { Business::Resources.subject_types.first => :read })

            assert_equal installation.permissions[Business::Resources.subject_types.first], :read

            version = create(:integration_version, integration: installation.integration, default_permissions: { "enterprise_administration" => :write })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_predicate result, :success?

            subject = @business.resources.enterprise_administration

            assert_granted_in_permissions_table(
              actor_id:     installation.ability_id,
              actor_type:   installation.ability_type,
              subject_id:   subject.ability_id,
              subject_type: subject.ability_type,
              action:       :write,
            )
          end
        end

        context "on installations that are installed certain repositories" do
          test "successfully updates the installation's permissions" do
            integration  = create(:integration, default_permissions: { "metadata" => :read, "contents" => :write })
            installation = make_integration_installation(repository: @repo, integration: integration)

            assert_equal({ "metadata" => :read, "contents" => :write }, installation.permissions)

            version = integration.versions.create(default_permissions: { "metadata" => :read, "deployments" => :write })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal({ "metadata" => :read, "deployments" => :write }, result.installation.permissions)
          end
        end
      end

      context "upgrades existing permissions" do
        context "on installations that are installed on Users" do
          test "successfully upgrades the installation's permissions" do
            integration  = create(:integration, default_permissions: { "metadata" => :read, "contents" => :read })
            installation = make_integration_installation(target: @admin, integration: integration)

            assert_equal({ "metadata" => :read, "contents" => :read }, installation.permissions)

            version = integration.versions.create(default_permissions: { "contents" => :write, "metadata" => :read })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal({ "metadata" => :read, "contents" => :write }, result.installation.permissions)
          end
        end

        context "on installations that are installed on Organizations" do
          test "successfully upgrades the installation's permissions" do
            integration  = create(:integration, default_permissions: { "metadata" => :read, "members" => :read })
            installation = make_integration_installation(target: @org, integration: integration)

            assert_equal({ "metadata" => :read, "members" => :read }, installation.permissions)

            version = integration.versions.create(default_permissions: { "members" => :write, "metadata" => :read })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal({ "metadata" => :read, "members" => :write }, result.installation.permissions)
          end
        end

        context "on installations that are installed on Businesses" do
          test "successfully upgrades the installation's permissions" do
            integration  = create(:integration, default_permissions: { "enterprise_administration" => :read })
            installation = make_integration_installation(target: @business, integration: integration)

            assert_equal({ "enterprise_administration" => :read }, installation.permissions)

            version = integration.versions.create(default_permissions: { "enterprise_administration" => :write })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal({ "enterprise_administration" => :write }, result.installation.permissions)
          end
        end

        context "on installations that are installed on certain repositories" do
          test "successfully upgrades the installation's permissions" do
            integration  = create(:integration, default_permissions: { "metadata" => :read, "contents" => :read })
            installation = make_integration_installation(repository: @repo, integration: integration)

            assert_equal({ "metadata" => :read, "contents" => :read }, installation.permissions)

            version = integration.versions.create(default_permissions: { "contents" => :write, "metadata" => :read })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal({ "metadata" => :read, "contents" => :write }, result.installation.permissions)
          end
        end

        test "on installations where the integration only has User permissions" do
          integration  = create(:integration, default_permissions: { "emails" => :read })
          installation = make_integration_installation(target: @admin, integration: integration)

          assert_equal({}, installation.permissions)

          version = integration.versions.create(default_permissions: { "emails" => :write })
          result = IntegrationInstallation::PermissionsEditor.perform(
            installation,
            editor: @admin,
            version: version,
            entry_point: :test_case,
          )

          assert_equal({}, result.installation.permissions)
        end
      end

      context "downgrades existing permissions" do
        context "on installations that are installed on Users" do
          test "successfully downgrades the installation's permissions" do
            integration  = create(:integration, default_permissions: { "metadata" => :read, "contents" => :write })
            installation = make_integration_installation(target: @admin, integration: integration)

            assert_equal({ "metadata" => :read, "contents" => :write }, installation.permissions)

            version = integration.versions.create(default_permissions: { "contents" => :read, "metadata" => :read })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal({ "metadata" => :read, "contents" => :read }, result.installation.permissions)
          end
        end

        context "on installations that are installed on Organizations" do
          test "successfully downgrades the installation's permissions" do
            integration  = create(:integration, default_permissions: { "metadata" => :read, "members" => :write })
            installation = make_integration_installation(target: @org, integration: integration)

            assert_equal({ "metadata" => :read, "members" => :write }, installation.permissions)

            version = integration.versions.create(default_permissions: { "members" => :read, "metadata" => :read })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal({ "metadata" => :read, "members" => :read }, result.installation.permissions)
          end
        end

        context "on installations that are installed on Businesses" do
          test "successfully downgrades the installation's permissions" do
            integration  = create(:integration, default_permissions: { "enterprise_administration" => :write })
            installation = make_integration_installation(target: @business, integration: integration)

            assert_equal({ "enterprise_administration" => :write }, installation.permissions)

            version = integration.versions.create(default_permissions: { "enterprise_administration" => :read })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal({ "enterprise_administration" => :read }, result.installation.permissions)
          end
        end

        context "on installations that are installed on certain repositories" do
          test "successfully downgrades the installation's permissions" do
            integration  = create(:integration, default_permissions: { "metadata" => :read, "contents" => :write })
            installation = make_integration_installation(repository: @repo, integration: integration)

            assert_equal({ "metadata" => :read, "contents" => :write }, installation.permissions)

            version = integration.versions.create(default_permissions: { "contents" => :read, "metadata" => :read })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal({ "metadata" => :read, "contents" => :read }, result.installation.permissions)
          end

          test "removes dependent permissions on resources like protected branches" do
            integration  = create(:integration, default_permissions: { "metadata" => :read, "contents" => :write })
            installation = make_integration_installation(repository: @repo, integration: integration)

            assert_same_hash({ "metadata" => :read, "contents" => :write }, installation.permissions)

            protected_branch = create(:protected_branch, repository: @repo)
            subject          = protected_branch.resources.contents

            Permissions::Service.grant_app_permission(actor: installation, subject: subject, action: :write, entry_point: :test_case)

            assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: subject, action: :write)

            version = integration.versions.create(default_permissions: { "metadata" => :read, "contents" => :read })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_same_hash({ "metadata" => :read, "contents" => :read }, result.installation.permissions)
            refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: subject, action: :write)
          end
        end

        test "on installations where the integration only has User permissions" do
          integration  = create(:integration, default_permissions: { "emails" => :write })
          installation = make_integration_installation(target: @admin, integration: integration)

          assert_equal({}, installation.permissions)

          version = integration.versions.create(default_permissions: { "emails" => :read })
          result = IntegrationInstallation::PermissionsEditor.perform(
            installation,
            editor: @admin,
            version: version,
            entry_point: :test_case,
          )

          assert_equal({}, result.installation.permissions)
        end
      end

      context "removes existing permissions" do
        context "on installations that are installed on Users" do
          test "successfully removes the installation's permissions" do
            integration  = create(:integration, default_permissions: { "metadata" => :read, "contents" => :read })
            installation = make_integration_installation(target: @admin, integration: integration)

            assert_equal({ "metadata" => :read, "contents" => :read }, installation.permissions)

            version = integration.versions.create(default_permissions: { "metadata" => :read })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal({ "metadata" => :read }, result.installation.permissions)
          end
        end

        context "on installations that are installed on Organizations" do
          test "successfully removes the installation's permissions" do
            installation = make_integration_installation(target: @org, integration: @integration)
            assert_equal({ "metadata" => :read, "contents" => :read, "members" => :read }, installation.permissions)

            version = @integration.versions.create(default_permissions: { "metadata" => :read })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal({ "metadata" => :read }, result.installation.permissions)
          end
        end

        context "on installations that are installed on Businesses" do
          test "successfully removes the installation's permissions" do
            installation = make_integration_installation(target: @business, permissions: { "enterprise_administration" => :write })
            assert_equal({ "enterprise_administration" => :write }, installation.permissions)

            version = installation.integration.versions.create(default_permissions: { "metadata" => :read })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_predicate result, :success?
            assert_empty result.installation.permissions
          end
        end

        context "on installations that are installed certain repositories" do
          test "successfully removes the installation's permissions" do
            integration  = create(:integration, default_permissions: { "metadata" => :read, "contents" => :read })
            installation = make_integration_installation(repository: @repo, integration: integration)

            assert_equal({ "metadata" => :read, "contents" => :read }, installation.permissions)

            version = integration.versions.create(default_permissions: { "metadata" => :read })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal({ "metadata" => :read }, result.installation.permissions)
          end

          test "removes dependent permissions on resources like protected branches" do
            integration  = create(:integration, default_permissions: { "metadata" => :read, "contents" => :write })
            installation = make_integration_installation(repository: @repo, integration: integration)

            assert_same_hash({ "metadata" => :read, "contents" => :write }, installation.permissions)

            protected_branch = create(:protected_branch, repository: @repo)
            subject          = protected_branch.resources.contents

            Permissions::Service.grant_app_permission(actor: installation, subject: subject, action: :write, entry_point: :test_case)

            assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: subject, action: :write)

            version = integration.versions.create(default_permissions: { "metadata" => :read })
            result = IntegrationInstallation::PermissionsEditor.perform(
              installation,
              editor: @admin,
              version: version,
              entry_point: :test_case,
            )

            assert_equal({ "metadata" => :read }, result.installation.permissions)
            refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: subject, action: :write)
          end
        end

        test "on installations where the integration only has User permissions" do
          integration  = create(:integration, default_permissions: { "emails" => :write })
          installation = make_integration_installation(target: @admin, integration: integration)

          assert_equal({}, installation.permissions)

          version = integration.versions.create
          result = IntegrationInstallation::PermissionsEditor.perform(
            installation,
            editor: @admin,
            version: version,
            entry_point: :test_case,
          )

          assert_equal({}, result.installation.permissions)
        end
      end
    end

    context "changes events" do
      test "add events" do
        installation = make_integration_installation(target: @admin, integration: @integration)
        assert_predicate installation.events, :empty?

        version = @integration.versions.create(default_permissions: { "metadata" => :read }, default_events: %w(label))
        result = IntegrationInstallation::PermissionsEditor.perform(
          installation,
          editor: @admin,
          version: version,
          entry_point: :test_case,
        )

        assert_equal %w(label), result.installation.events
      end

      test "removes events" do
        installation = make_integration_installation(target: @admin, integration: @integration, events: %w(label))
        assert_equal %w(label), installation.events

        version = @integration.versions.create
        result = IntegrationInstallation::PermissionsEditor.perform(
          installation,
          editor: @admin,
          version: version,
          entry_point: :test_case,
        )

        assert_predicate result.installation.events, :empty?
      end

      test "no change in events" do
        installation = make_integration_installation(target: @admin, integration: @integration, events: %w(label))
        assert_equal %w(label), installation.events
        IntegrationInstallation.any_instance.expects(:update!).never

        version = @integration.versions.create(default_permissions: { "metadata" => :read }, default_events: %w(label))
        result = IntegrationInstallation::PermissionsEditor.perform(
          installation,
          editor: @admin,
          version: version,
          entry_point: :test_case,
        )
      end
    end

    test "instruments the update of version" do
      events = subscribe "integration_installation.version_updated"
      old_version = @integration.latest_version

      installation = make_integration_installation(target: @org, integration: @integration)
      version      = @integration.versions.create(default_permissions: { "contents" => :read })

      edited_installation = IntegrationInstallation::PermissionsEditor.perform(
        installation,
        editor: @admin,
        version: version,
        entry_point: :test_case,
      ).installation

      expected_payload = {}.tap do |payload|
        payload[:installation_id]      = edited_installation.id
        payload[:actor]                = @admin.login
        payload[:actor_id]             = @admin.id
        payload[:integration]          = @integration.name
        payload[:app]                  = @integration.name
        payload[:integration_id]       = @integration.id
        payload[:app_id]               = @integration.id
        payload[:name]                 = @integration.name
        payload[:slug]                 = @integration.slug
        payload[:org]                  = @org.to_s
        payload[:org_id]               = @org.id
        payload[:old_version]          = old_version.number
        payload[:new_version]          = version.number
        payload[:repository_selection] = "all"

        payload[:permissions_removed]   = { "members" => :read }
        payload[:permissions_unchanged] = { "contents" => :read, "metadata" => :read }
      end

      assert event = events.pop, "not instrumented"
      assert_same_hash expected_payload, event.payload
    end

    test "does not instrument the version update for Actions app" do
      GitHub.stubs(:actions_enabled?).returns(true)

      make_trusted_oauth_apps_owner
      integration = create(:launch_integration)

      events = subscribe "integration_installation.version_updated"

      installation = make_integration_installation(target: @org, integration: integration)
      version      = integration.versions.create(default_permissions: { "contents" => :read })

      IntegrationInstallation::PermissionsEditor.perform(
        installation,
        editor: @admin,
        version: version,
        entry_point: :test_case,
      )

      assert_predicate events, :empty?
    end
  end
end
