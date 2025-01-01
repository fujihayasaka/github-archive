# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class IntegrationInstallationEditorEditingAnIntegrationInstallationTest < GitHub::TestCase
  include PermissionsHelper
  include DogstatsTestHelpers

  fixtures do
    make_trusted_oauth_apps_owner

    @integration = create(:integration, default_permissions: { "contents" => :read, "members" => :read })
    @admin = create(:user)
    @org   = create(:organization, login: "ACME", admin: @admin)

    @repo   = create(:private_repository, owner: @org, name: "repo")
    @repo_1 = create(:private_repository, owner: @org, name: "repo-1")
    @public_repo = create(:repository, :minimal, owner: @org, name: "org-public")
  end

  setup_once do
    enable_cache_storage
  end

  setup do
    reset_cache
  end

  teardown_once do
    disable_cache_storage
  end

  context ".perform" do
    context "repo admin app management" do
      test "returns a failure when the target is a personal account that is not the installer's account" do
        other_user = create(:user, login: "other-user")

        installation = make_integration_installation(integration: @integration, repository: create(:repository, :minimal, owner: other_user))

        result = IntegrationInstallation::Editor.perform(
          installation,
          editor: @admin,
          repositories: [create(:repository, :minimal, owner: other_user)],
          entry_point: :test_case,
        )

        assert_predicate result, :failed?
        assert_equal "You do not have permission to modify this app on other-user.", result.error
        assert_equal :not_admin_on_subset, result.reason
      end

      test "returns a failure when the target is an org but the installer is not an owner of the org" do
        member = create(:user)
        @org.add_member(member)

        installation = make_integration_installation(integration: @integration, repository: @repo)

        result = IntegrationInstallation::Editor.perform(
          installation,
          editor: member,
          repositories: [@repo],
          entry_point: :test_case,
        )

        assert_predicate result, :failed?
        assert_equal "You cannot modify apps with organization permissions on ACME. Please contact an Organization Owner.", result.error
        assert_equal :requires_org_permissions, result.reason
      end

      test "returns a failure if a repository isn't owned by the owner given" do
        other_org = create(:organization, admin: @admin)
        other_org_repo = create(:repository, :minimal, owner: other_org)

        installation = make_integration_installation(integration: @integration, repository: @repo)

        result = IntegrationInstallation::Editor.perform(
          installation,
          repositories: [other_org_repo],
          editor: @admin,
          entry_point: :test_case,
        )

        assert_predicate result, :failed?
        assert_equal "Repositories must be owned by ACME. Please contact an Organization Owner.", result.error
        assert_equal :not_owned_by_target, result.reason
      end

      test "returns a failure if the editor cannot admin all of the repos" do
        installation = make_integration_installation(integration: @integration, repository: @repo)

        user = create(:user)
        @repo_1.add_member(user)

        result = IntegrationInstallation::Editor.perform(
          installation,
          repositories: [@repo, @repo_1],
          editor: user,
          entry_point: :test_case,
        )

        assert_predicate result, :failed?
        assert_equal "You do not have permission to modify this app on ACME. Please contact an Organization Owner.", result.error
        assert_equal :not_admin_on_subset, result.reason
      end

      test "returns a failure if the editor cannot admin all of the removed repos" do
        enable_feature_flag(:installation_editor_current_repositories)
        new_installation = IntegrationInstallation::Creator.perform(
          @integration,
          @org,
          repositories: [@repo, @repo_1, @public_repo],
          version: @integration.latest_version,
          installer: @admin,
          entry_point: :test_case,
        ).installation

        user = create(:user)
        @repo_1.add_member(user)

        result = IntegrationInstallation::Editor.perform(
          new_installation,
          repositories: [@repo_1],
          editor: user,
          entry_point: :test_case,
        )

        assert_predicate result, :failed?
        assert_equal "You do not have permission to modify this app on ACME. Please contact an Organization Owner.", result.error
        assert_equal :not_admin_on_subset, result.reason
      end

      test "returns a failure if the editor cannot admin the account, and requests install on all" do
        installation = make_integration_installation(integration: @integration, repository: @repo)

        user = create(:user)
        @repo_1.add_member(user)

        result = IntegrationInstallation::Editor.perform(
          installation,
          repositories: [],
          editor: user,
          entry_point: :test_case,
        )

        assert_predicate result, :failed?
        assert_equal "You cannot modify apps with organization permissions on ACME. Please contact an Organization Owner.", result.error
        assert_equal :requires_org_permissions, result.reason
      end

      test "returns a success if the editor can admin all of the repos but can't admin the target" do
        installation = make_integration_installation(repository: @repo, permissions: { "metadata" => :read })

        user = create(:user)
        @repo.add_member(user, action: :admin)
        @repo_1.add_member(user, action: :admin)

        result = IntegrationInstallation::Editor.perform(
          installation,
          repositories: [@repo, @repo_1],
          editor: user,
          entry_point: :test_case,
        )

        assert_predicate result, :success?
      end

      test "returns a success if the editor can admin all of the repositories on the target org, but there are org permissions" do
        integration = create(:integration, default_permissions: { "members" => :read })
        installation = make_integration_installation(integration: integration, repository: @repo)

        user = create(:user)
        @repo.add_member(user, action: :admin)
        @repo_1.add_member(user, action: :admin)

        result = IntegrationInstallation::Editor.perform(
          installation,
          repositories: [@repo, @repo_1],
          editor: user,
          entry_point: :test_case,
        )

        assert_predicate result, :success?
      end

      test "uses static permissions if defined on the integration" do
        integration = create(:codespaces_integration)
        installation = make_integration_installation(integration: integration, repository: @repo)

        user = create(:user)
        @repo.add_member(user, action: :admin)
        @repo_1.add_member(user, action: :admin)

        result = IntegrationInstallation::Editor.perform(
          installation,
          repositories: [@repo, @repo_1],
          editor: user,
          entry_point: :test_case,
        )

        assert_predicate result, :success?

        expected_permissions = Apps::Privileged.property(:static_installation_repository_permissions, app: integration)
        unexpected_permissions = integration.latest_version.permissions_of_type(Repository).reject { |resource, _| expected_permissions.key?(resource) }

        expected_permissions.each_pair do |resource, action|
          assert_able installation, action, @repo.resources.public_send(resource.to_sym)
          assert_able installation, action, @repo_1.resources.public_send(resource.to_sym)
        end

        unexpected_permissions.each_pair do |resource, action|
          refute_able installation, action, @repo.resources.public_send(resource.to_sym)
          refute_able installation, action, @repo_1.resources.public_send(resource.to_sym)
        end
      end
    end

    context "changes the permissions" do
      test "from all repos, to a specific set of repos" do
        new_installation = make_integration_installation(target: @org, integration: @integration)

        assert_predicate new_installation, :installed_on_all_repositories?

        assert_equal "all", new_installation.get_cached_repository_selection
        assert_equal "all", new_installation.repository_selection_cache

        edited_installation = IntegrationInstallation::Editor.perform(
          new_installation,
          repositories: [@repo, @public_repo],
          editor: @admin,
          entry_point: :test_case,
        ).installation

        refute_predicate edited_installation, :installed_on_all_repositories?
        assert_same_elements [@repo, @public_repo], edited_installation.repositories

        assert_equal "selected", new_installation.get_cached_repository_selection
        assert_equal "selected", new_installation.repository_selection_cache
      end

      test "and stats deleted_rows with entry point" do
        new_installation = make_integration_installation(target: @org, integration: @integration)
        _ = IntegrationInstallation::Editor.perform(
          new_installation,
          repositories: [@repo, @public_repo],
          editor: @admin,
          entry_point: :test_case,
        ).installation

        assert_dogstats_distribution(1, "permissions_service.deleted_rows", tags: ["entry_point:test_case"])
      end

      test "queues a job to calculate the rate limit" do
        new_installation = make_integration_installation(target: @org, integration: @integration)

        assert new_installation.installed_on_all_repositories?

        assert_enqueued_jobs 1, only: UpdateIntegrationInstallationRateLimitJob, queue: "update_integration_installation_rate_limit" do
          edited_installation = IntegrationInstallation::Editor.perform(
            new_installation,
            repositories: [@repo, @public_repo],
            editor: @admin,
            entry_point: :test_case,
          ).installation

          assert_enqueued_with(job: UpdateIntegrationInstallationRateLimitJob, args: [edited_installation.id], queue: "update_integration_installation_rate_limit")
        end
      end

      test "from a specific set of repos to all repos" do
        new_installation = IntegrationInstallation::Creator.perform(
          @integration,
          @org,
          repositories: [@repo],
          version: @integration.latest_version,
          installer: @admin,
          entry_point: :test_case,
        ).installation

        refute new_installation.installed_on_all_repositories?

        edited_installation = IntegrationInstallation::Editor.perform(
          new_installation,
          repositories: nil,
          editor: @admin,
          entry_point: :test_case,
        ).installation

        assert edited_installation.installed_on_all_repositories?
        assert_includes edited_installation.repositories, @public_repo
        assert_includes edited_installation.repositories, @repo_1
        assert_equal "all", new_installation.get_cached_repository_selection
        assert_equal "all", new_installation.repository_selection_cache
      end

      test "to add an additional repository to the set of specific repos" do
        new_installation = IntegrationInstallation::Creator.perform(
          @integration,
          @org,
          repositories: [@repo],
          version: @integration.latest_version,
          installer: @admin,
          entry_point: :test_case,
        ).installation

        refute new_installation.installed_on_all_repositories?

        edited_installation = IntegrationInstallation::Editor.perform(
          new_installation,
          repositories: [@repo, @repo_1],
          editor: @admin,
          entry_point: :test_case,
        ).installation

        refute edited_installation.installed_on_all_repositories?
        assert_same_elements [@repo, @repo_1], \
          edited_installation.repositories
      end

      test "to remove a repository from the set of specific repos" do
        new_installation = IntegrationInstallation::Creator.perform(
          @integration,
          @org,
          repositories: [@repo, @repo_1, @public_repo],
          version: @integration.latest_version,
          installer: @admin,
          entry_point: :test_case,
        ).installation

        refute new_installation.installed_on_all_repositories?

        edited_installation = IntegrationInstallation::Editor.perform(
          new_installation,
          repositories: [@repo],
          editor: @admin,
          entry_point: :test_case,
        ).installation

        refute edited_installation.installed_on_all_repositories?
        assert_equal [@repo], edited_installation.repositories
      end

      test "to include a brand new set of specific repos" do
        new_installation = IntegrationInstallation::Creator.perform(
          @integration,
          @org,
          repositories: [@repo],
          version: @integration.latest_version,
          installer: @admin,
          entry_point: :test_case,
        ).installation

        assert_equal [@repo], new_installation.repositories

        edited_installation = IntegrationInstallation::Editor.perform(
          new_installation,
          repositories: [@repo_1],
          editor: @admin,
          entry_point: :test_case,
        ).installation

        assert_equal [@repo_1], edited_installation.repositories
      end

      test "to include all repositories when there were previously none after an accepted permission change" do
        # No repository permissions
        @integration.update(default_permissions: { "members" => :read })
        @integration.reload

        new_installation = IntegrationInstallation::Creator.perform(
          @integration,
          @org,
          repositories: :none,
          version: @integration.latest_version,
          installer: @admin,
          entry_point: :test_case,
        ).installation

        assert_empty new_installation.repositories
        refute_predicate new_installation, :repository_installation_required?

        # Give the Integration repository permisions and "accept" the permissions
        # so that the installation is no longer "outdated".
        new_version = @integration.versions.create(default_permissions: { "metadata" => :read, "members" => :read })
        permissions_result = IntegrationInstallation::PermissionsEditor.perform(
          new_installation,
          editor: @admin,
          version: new_version,
          entry_point: :test_case,
        )
        assert_predicate permissions_result, :success?, permissions_result.error

        edited_installation = IntegrationInstallation::Editor.perform(
          permissions_result.installation,
          repositories: nil, # install on all repositories
          editor: @admin,
          entry_point: :test_case,
        ).installation

        assert_same_elements [@repo, @repo_1, @public_repo], edited_installation.repositories
      end

      test "updates installation's updated_at timestamp" do
        installation = make_integration_installation(repository: @repo, permissions: { "metadata" => :read })
        previous_updated_at = installation.updated_at

        Timecop.travel(1.second.from_now) do
          result = ActiveRecord::Base.connected_to(role: :reading) do
            IntegrationInstallation::Editor.perform(
              installation,
              repositories: [@repo, @repo_1],
              editor: @admin,
              entry_point: :test_case,
            )
          end
          new_updated_at = installation.reload.updated_at

          assert_predicate result, :success?
          assert_operator previous_updated_at, :<, new_updated_at
        end
      end
    end

    context "updating the permissions table" do
      include PermissionsHelper

      test "when adding a new repository to an installation" do
        version = @integration.versions.create(
          default_permissions: { "members" => :read, "metadata" => :read },
        )

        # Start by installing this App on a single repository
        new_installation = IntegrationInstallation::Creator.perform(
          @integration,
          @org,
          repositories: [@repo],
          version: version,
          installer: @admin,
          entry_point: :test_case,
        ).installation

        # Check abilities table
        assert_able new_installation, :read, @repo.resources.metadata
        refute_able new_installation, :read, @repo_1.resources.metadata

        # Check permissions table
        assert_granted_in_permissions_table(
          actor_id: new_installation.id,
          actor_type: new_installation.ability_type,
          subject_id: @repo.resources.metadata.ability_id,
          subject_type: @repo.resources.metadata.ability_type,
        )

        refute_granted_in_permissions_table(
          actor_id: new_installation.id,
          actor_type: new_installation.ability_type,
          subject_id: @repo_1.resources.metadata.ability_id,
          subject_type: @repo_1.resources.metadata.ability_type,
        )

        edited_installation = IntegrationInstallation::Editor.perform(
          new_installation,
          repositories: [@repo, @repo_1],
          editor: @admin,
          entry_point: :test_case,
        ).installation

        # Both repos should now be readable by the installation, in both
        # clusters:
        #
        # Check abilities table
        assert_able edited_installation, :read, @repo.resources.metadata
        assert_able edited_installation, :read, @repo_1.resources.metadata

        # Check permissions table
        assert_granted_in_permissions_table(
          actor_id: new_installation.id,
          actor_type: new_installation.ability_type,
          subject_id: @repo.resources.metadata.ability_id,
          subject_type: @repo.resources.metadata.ability_type,
        )

        assert_granted_in_permissions_table(
          actor_id: new_installation.id,
          actor_type: new_installation.ability_type,
          subject_id: @repo_1.resources.metadata.ability_id,
          subject_type: @repo_1.resources.metadata.ability_type,
        )
      end

      context "when removing a repository from an installation" do
        test "access is revoked" do
          version = @integration.versions.create(
            default_permissions: { "members" => :read, "metadata" => :read },
          )

          # Start by installing this App on two repositories
          new_installation = IntegrationInstallation::Creator.perform(
            @integration,
            @org,
            repositories: [@repo, @repo_1],
            version: version,
            installer: @admin,
            entry_point: :test_case,
          ).installation

          # Check abilities table
          assert_able new_installation, :read, @repo.resources.metadata
          assert_able new_installation, :read, @repo_1.resources.metadata

          # Check permissions table
          assert_granted_in_permissions_table(
            actor_id: new_installation.id,
            actor_type: new_installation.ability_type,
            subject_id: @repo.resources.metadata.ability_id,
            subject_type: @repo.resources.metadata.ability_type,
          )

          assert_granted_in_permissions_table(
            actor_id: new_installation.id,
            actor_type: new_installation.ability_type,
            subject_id: @repo_1.resources.metadata.ability_id,
            subject_type: @repo_1.resources.metadata.ability_type,
          )

          edited_installation = IntegrationInstallation::Editor.perform(
            new_installation,
            repositories: [@repo],
            editor: @admin,
            entry_point: :test_case,
          ).installation

          # Only one repo should now be readable by the installation, in both
          # clusters:
          #
          # Check abilities table
          assert_able edited_installation, :read, @repo.resources.metadata
          refute_able edited_installation, :read, @repo_1.resources.metadata

          # Check permissions table
          assert_granted_in_permissions_table(
            actor_id: new_installation.id,
            actor_type: new_installation.ability_type,
            subject_id: @repo.resources.metadata.ability_id,
            subject_type: @repo.resources.metadata.ability_type,
          )

          refute_granted_in_permissions_table(
            actor_id: new_installation.id,
            actor_type: new_installation.ability_type,
            subject_id: @repo_1.resources.metadata.ability_id,
            subject_type: @repo_1.resources.metadata.ability_type,
          )
        end

        test "access to protected branches is revoked" do
          installation = make_integration_installation(
            integration: @integration,
            repositories: [@repo, @repo_1],
            permissions: {
              "metadata" => :read,
              "contents" => :read,
            },
          )

          protected_branch = create(:protected_branch, repository: @repo_1)

          subject = protected_branch.resources.contents
          Permissions::Service.grant_app_permission(actor: installation, subject: subject, action: :write, entry_point: :test_case)

          assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: subject)

          result = IntegrationInstallation::Editor.perform(installation, repositories: [@repo], editor: @admin, entry_point: :test_case)
          assert_predicate result, :success?

          refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: subject)
        end
      end

      context "when moving from a set of repos to 'all' repos" do
        test "access is properly given" do
          version = @integration.versions.create(
            default_permissions: { "members" => :read, "metadata" => :read },
          )

          # Start by installing this App on one repository
          new_installation = IntegrationInstallation::Creator.perform(
            @integration,
            @org,
            repositories: [@repo],
            version: version,
            installer: @admin,
            entry_point: :test_case,
          ).installation

          # Check abilities table
          assert_able new_installation, :read, @repo.resources.metadata
          refute_able new_installation, :read, @org.repository_resources.metadata

          # Check permissions table
          assert_granted_in_permissions_table(
            actor_id: new_installation.id,
            actor_type: new_installation.ability_type,
            subject_id: @repo.resources.metadata.ability_id,
            subject_type: @repo.resources.metadata.ability_type,
          )

          refute_granted_in_permissions_table(
            actor_id: new_installation.id,
            actor_type: new_installation.ability_type,
            subject_id: @org.repository_resources.metadata.ability_id,
            subject_type: @org.repository_resources.metadata.ability_type,
          )

          # Edit installation to install on *all* repositories
          edited_installation = IntegrationInstallation::Editor.perform(
            new_installation,
            repositories: nil,
            editor: @admin,
            entry_point: :test_case,
          ).installation

          # All repos should now be readable by the installation, in both
          # clusters, via the installation target (the org):
          #
          # Check abilities table
          assert_able edited_installation, :read, @org.repository_resources.metadata

          # Check permissions table
          assert_granted_in_permissions_table(
            actor_id: new_installation.id,
            actor_type: new_installation.ability_type,
            subject_id: @org.repository_resources.metadata.ability_id,
            subject_type: @org.repository_resources.metadata.ability_type,
          )
        end

        test "access to protected branches is not revoked" do
          installation = make_integration_installation(
            integration: @integration,
            repository: @repo,
            permissions: {
              "metadata" => :read,
              "contents" => :read,
            },
          )

          protected_branch = create(:protected_branch, repository: @repo)

          subject = protected_branch.resources.contents
          Permissions::Service.grant_app_permission(actor: installation, subject: subject, action: :write, entry_point: :test_case)

          assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: subject)

          # Edit installation to install on *all* repositories
          result = IntegrationInstallation::Editor.perform(installation, repositories: nil, editor: @admin, entry_point: :test_case)
          assert_predicate result, :success?

          assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: subject)
        end
      end

      context "when moving from 'all' repos to specific repos" do
        test "access was properly set" do
          version = @integration.versions.create(
            default_permissions: { "members" => :read, "metadata" => :read },
          )

          # Start by installing this App on *all* repositories
          new_installation = IntegrationInstallation::Creator.perform(
            @integration,
            @org,
            repositories: nil,
            version: version,
            installer: @admin,
            entry_point: :test_case,
          ).installation

          # Check abilities table
          assert_able new_installation, :read, @org.repository_resources.metadata

          # Check permissions table
          assert_granted_in_permissions_table(
            actor_id: new_installation.id,
            actor_type: new_installation.ability_type,
            subject_id: @org.repository_resources.metadata.ability_id,
            subject_type: @org.repository_resources.metadata.ability_type,
          )

          # Edit installation to install on a single repository
          edited_installation = IntegrationInstallation::Editor.perform(
            new_installation,
            repositories: [@repo],
            editor: @admin,
            entry_point: :test_case,
          ).installation

          # All repos should no longer be readable by the installation, in both
          # clusters, via the installation target (the org):
          #
          # Check abilities table
          assert_able edited_installation, :read, @repo.resources.metadata
          refute_able edited_installation, :read, @org.repository_resources.metadata

          # Check permissions table
          assert_granted_in_permissions_table(
            actor_id: new_installation.id,
            actor_type: new_installation.ability_type,
            subject_id: @repo.resources.metadata.ability_id,
            subject_type: @repo.resources.metadata.ability_type,
          )

          refute_granted_in_permissions_table(
            actor_id: new_installation.id,
            actor_type: new_installation.ability_type,
            subject_id: @org.repository_resources.metadata.ability_id,
            subject_type: @org.repository_resources.metadata.ability_type,
          )
        end

        test "does not attempt to delete permissions records if repository selection does not change" do
          create(:repository, :minimal, owner: @org)

          installation = make_integration_installation(target: @org, permissions: { "metadata" => :read, "contents" => :read })
          assert_predicate installation, :installed_on_all_repositories?

          # There should be minimal primary activity as this is a "no-op" from
          # a repository access perspective:
          primary_clusters_and_counts =
            if GitHub.enterprise?
              {
                ApplicationRecord::Mysql1 => 5,
              }
            else
              {
                ApplicationRecord::Collab => 1, # <-- Workspace repository advisory filtering from PermissionGrantable
                ApplicationRecord::Permissions => 2, # <-- A query from PermissionGrantable checking installed on all status
                ApplicationRecord::Repositories => 2, # <-- Repositories 'active' queries from permission checking
              }
            end

          # Most queries should go to the replicas:
          replica_clusters_and_counts =
            if GitHub.enterprise?
              {
                ApplicationRecord::Mysql1 => 5,
              }
            else
              {
                ApplicationRecord::Collab => TestEnv.test_all_features? ? 0 : 1,
                ApplicationRecord::Permissions => TestEnv.test_all_features? ? 1 : 2, # <-- installed on all repos check
                ApplicationRecord::Repositories => TestEnv.test_all_features? ? 0 : 2, # <-- caching current repositories
              }
            end

          assert_query_count_against_primary(clusters_and_counts: primary_clusters_and_counts) do
            assert_query_count_against_replicas(clusters_and_counts: replica_clusters_and_counts) do
              result = IntegrationInstallation::Editor.perform(
                installation,
                repositories: [],
                editor: @admin,
                skip_callbacks: true, # Not important for this test and makes SQL query tracking more difficult
                entry_point: :test_case,
              )

              assert_predicate result, :success?
              assert_same_elements @org.repositories.pluck(:id), installation.repository_ids
            end
          end
        end

        test "allows installing on subset when the number of repositories on the target is greater than the limit", skip_if_feature_disabled: :repo_subset_limit_for_installations do
          create(:repository, :minimal, owner: @org)

          installation = make_integration_installation(target: @org, permissions: { "metadata" => :read, "contents" => :read })

          Integration::InstallationService.stub_const(:DEFAULT_MAX_REPOS, 2) do
            result = IntegrationInstallation::Editor.perform(
              installation,
              repositories: [@repo],
              editor: @admin,
              entry_point: :test_case,
            )

            assert_predicate result, :success?
            assert_same_elements [@repo.id], installation.repository_ids
          end
        end

        context "repos that were removed" do
          test "access to protected branches is revoked" do
            installation = make_integration_installation(
               integration: @integration,
               target: @org,
               permissions: {
                 "metadata" => :read,
                 "contents" => :read,
               },
             )

            protected_branch = create(:protected_branch, repository: @repo_1)

            subject = protected_branch.resources.contents
            Permissions::Service.grant_app_permission(actor: installation, subject: subject, action: :write, entry_point: :test_case)

            assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: subject)

            # Edit installation to install on a single repository
            result = IntegrationInstallation::Editor.perform(installation, repositories: [@repo], editor: @admin, entry_point: :test_case)
            assert_predicate result, :success?

            refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: subject)
          end
        end

        context "repos that were not removed" do
          test "access to protected branches is not revoked" do
            installation = make_integration_installation(
               integration: @integration,
               target: @org,
               permissions: {
                 "metadata" => :read,
                 "contents" => :read,
               },
             )

            protected_branch = create(:protected_branch, repository: @repo)

            subject = protected_branch.resources.contents
            action  = :write

            Permissions::Service.grant_app_permission(actor: installation, subject: subject, action: action, entry_point: :test_case)

            assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: subject)

            # Edit installation to install on a single repository
            result = IntegrationInstallation::Editor.perform(installation, repositories: [@repo], editor: @admin, entry_point: :test_case)
            assert_predicate result, :success?

            assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: subject)
          end
        end
      end
    end

    test "does not affect the cache when permissions writes fail" do
      installation = make_integration_installation(
        repositories: [@repo, @repo_1],
        permissions: { "metadata" => :read }
      )

      previous_updated_at = installation.updated_at

      # Set and get cached values
      cached_permissions = installation.get_cached_permissions
      cached_selection = installation.get_cached_repository_selection

      # Stub a failure to write permissions
      Permissions::Service
        .stubs(:revoke_permissions_granted_on_subjects)
        .raises(ActiveRecord::ConnectionTimeoutError)

      assert_no_changes -> { installation.updated_at } do
        assert_raises ActiveRecord::ConnectionTimeoutError do
          IntegrationInstallation::Editor.perform(
            installation,
            repositories: nil,
            editor: @admin,
            entry_point: :test_case,
          )
        end
      end

      installation.reload
      assert_equal cached_selection, installation.repository_selection_cache
      assert_same_hash cached_permissions, installation.permissions_cache.transform_values(&:to_sym)
    end

    test "instruments addition of a repo to an installation" do
      events = subscribe "integration_installation.repositories_added"

      installation = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [@repo],
        version: @integration.latest_version,
        installer: @admin,
        entry_point: :test_case,
      ).installation

      edited_installation = IntegrationInstallation::Editor.perform(
        installation,
        repositories: [@repo, @repo_1],
        editor: @admin,
        entry_point: :test_case,
      ).installation

      assert_same_elements [@repo, @repo_1], \
        edited_installation.repositories

      expected_payload = {}.tap do |payload|
        payload[:installation_id]            = edited_installation.id
        payload[:actor]                      = @admin.login
        payload[:actor_id]                   = @admin.id
        payload[:application_client_id]      = @integration.key
        payload[:integration]                = @integration.name
        payload[:app]                        = @integration.name
        payload[:integration_id]             = @integration.id
        payload[:app_id]                     = @integration.id
        payload[:name]                       = @integration.name
        payload[:slug]                       = @integration.slug
        payload[:org]                        = @org.to_s
        payload[:org_id]                     = @org.id
        payload[:repositories_added]         = [@repo_1.id]
        payload[:repositories_added_names]   = [@repo_1.full_name]
        payload[:repository_selection]       = "selected"
        payload[:requester_id]               = nil

      end

      assert event = events.pop, "not instrumented"
      assert_same_hash expected_payload, event.payload
    end

    test "instruments addition of many repos in a background job" do
      events = subscribe "integration_installation.repositories_added"

      installation = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [@repo],
        version: @integration.latest_version,
        installer: @admin,
        entry_point: :test_case,
      ).installation

      IntegrationInstallation.stub_const(:MAX_REPOS_TO_INSTRUMENT, 1) do
        args = [
          :repositories_added,
          installation.id,
          @admin.id,
          [@repo_1.id],
          "selected",
          { requester_id: nil }
        ]

        assert_enqueued_with(job: IntegrationInstallationInstrumentationJob, args: args) do
          edited_installation = IntegrationInstallation::Editor.perform(
            installation,
            repositories: [@repo, @repo_1],
            editor: @admin,
            entry_point: :test_case,
          ).installation

          # Still adds the repos synchronously
          assert_same_elements [@repo, @repo_1], \
            edited_installation.repositories

          refute events.pop, "should not be instrumented yet"
        end
      end
    end

    test "instruments removal of a repo from an installation" do
      events = subscribe "integration_installation.repositories_removed"

      installation = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [@repo, @repo_1],
        version: @integration.latest_version,
        installer: @admin,
        entry_point: :test_case,
      ).installation

      edited_installation = IntegrationInstallation::Editor.perform(
        installation,
        repositories: [@repo],
        editor: @admin,
        entry_point: :test_case,
      ).installation

      assert_equal [@repo], \
        edited_installation.repositories

      expected_payload = {}.tap do |payload|
        payload[:installation_id]            = edited_installation.id
        payload[:actor]                      = @admin.login
        payload[:actor_id]                   = @admin.id
        payload[:application_client_id]      = @integration.key
        payload[:integration]                = @integration.name
        payload[:app]                        = @integration.name
        payload[:integration_id]             = @integration.id
        payload[:app_id]                     = @integration.id
        payload[:name]                       = @integration.name
        payload[:slug]                       = @integration.slug
        payload[:org]                        = @org.to_s
        payload[:org_id]                     = @org.id
        payload[:repositories_removed]       = [@repo_1.id]
        payload[:repositories_removed_names] = [@repo_1.full_name]
        payload[:repository_selection]       = "selected"

      end

      assert event = events.pop, "not instrumented"
      assert_same_hash expected_payload, event.payload
    end

    test "instruments removal of many repos in a background job" do
      events = subscribe "integration_installation.repositories_removed"

      installation = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [@repo, @repo_1],
        version: @integration.latest_version,
        installer: @admin,
        entry_point: :test_case,
      ).installation

      IntegrationInstallation.stub_const(:MAX_REPOS_TO_INSTRUMENT, 1) do
        args = [
          :repositories_removed,
          installation.id,
          @admin.id,
          [@repo_1.id],
          "selected",
        ]

        assert_enqueued_with(job: IntegrationInstallationInstrumentationJob, args: args) do
          edited_installation = IntegrationInstallation::Editor.perform(
            installation,
            repositories: [@repo],
            editor: @admin,
            entry_point: :test_case,
          ).installation

          # Still removes the repos synchronously
          assert_equal [@repo], \
            edited_installation.repositories

          refute events.pop, "should not be instrumented yet"
        end
      end
    end

    test "skips after_updated_callbacks if skip_callbacks is true" do
      events = subscribe "integration_installation.repositories_added"

      installation = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [@repo],
        version: @integration.latest_version,
        installer: @admin,
        entry_point: :test_case,
      ).installation

      assert_enqueued_jobs 0, only: UpdateIntegrationInstallationRateLimitJob, queue: "update_integration_installation_rate_limit" do
        edited_installation = IntegrationInstallation::Editor.perform(
          installation,
          repositories: [@repo, @repo_1],
          editor: @admin,
          skip_callbacks: true,
          entry_point: :test_case,
        ).installation

        assert_same_elements [@repo, @repo_1], edited_installation.repositories
        refute event = events.pop, "unexpected instrument"
      end
    end

    test "enqueues a SyncScopedIntegrationInstallationsJob when repositories are removed" do
      installation = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [@repo, @repo_1],
        version: @integration.latest_version,
        installer: @admin,
        entry_point: :test_case,
      ).installation

      assert_enqueued_with(job: SyncScopedIntegrationInstallationsJob, args: [installation, action: :repositories_removed, repository_ids: [@repo_1.id], entry_point: :test_case]) do
        IntegrationInstallation::Editor.perform(
          installation,
          repositories: [@repo],
          editor: @admin,
          entry_point: :test_case,
        )
      end
    end

    test "instruments switch from install on all to specific repos" do
      events_added = subscribe "integration_installation.repositories_added"
      events_removed = subscribe "integration_installation.repositories_removed"

      another_org_repo = create(:repository, :minimal, owner: @org, name: "another-repo")

      installation = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [],
        version: @integration.latest_version,
        installer: @admin,
        entry_point: :test_case,
      ).installation

      assert installation.installed_on_all_repositories?

      edited_installation = IntegrationInstallation::Editor.perform(
        installation,
        repositories: [@repo_1],
        editor: @admin,
        entry_point: :test_case,
      ).installation

      assert_equal [@repo_1], \
      edited_installation.repositories

      expected_base_payload = {}.tap do |payload|
        payload[:installation_id]       = edited_installation.id
        payload[:actor]                 = @admin.login
        payload[:actor_id]              = @admin.id
        payload[:application_client_id] = @integration.key
        payload[:integration]           = @integration.name
        payload[:app]                   = @integration.name
        payload[:integration_id]        = @integration.id
        payload[:app_id]                = @integration.id
        payload[:name]                  = @integration.name
        payload[:slug]                  = @integration.slug
        payload[:org]                   = @org.to_s
        payload[:org_id]                = @org.id
        payload[:repository_selection]  = "selected"

      end

      expected_payload_for_added = expected_base_payload.merge(
        repositories_added: [@repo_1.id],
        repositories_added_names: [@repo_1.full_name],
        requester_id: nil
      )

      expected_payload_for_removed = expected_base_payload.merge(
        repositories_removed: [@repo.id, @public_repo.id, another_org_repo.id],
        repositories_removed_names: [@repo.full_name, @public_repo.full_name, another_org_repo.full_name]
      )

      assert event = events_added.pop, "not instrumented"
      assert_same_hash expected_payload_for_added, event.payload

      if GitHub.flipper[:integration_installation_editor_instrumentation].enabled?
        assert_empty events_removed, "unexpected instrument"
      else
        assert event = events_removed.pop, "not instrumented"
        assert_same_hash expected_payload_for_removed, event.payload
      end
    end

    test "instruments switch from install on specific repos to on all" do
      events = subscribe "integration_installation.repositories_added"

      installation = IntegrationInstallation::Creator.perform(
        @integration,
        @org,
        repositories: [@repo],
        version: @integration.latest_version,
        installer: @admin,
        entry_point: :test_case,
        ).installation

      edited_installation = IntegrationInstallation::Editor.perform(
        installation,
        repositories: nil,
        editor: @admin,
        entry_point: :test_case,
        ).installation

      assert installation.installed_on_all_repositories?

      expected_base_payload = {}.tap do |payload|
        payload[:installation_id]       = edited_installation.id
        payload[:actor]                 = @admin.login
        payload[:actor_id]              = @admin.id
        payload[:application_client_id] = @integration.key
        payload[:integration]           = @integration.name
        payload[:app]                   = @integration.name
        payload[:integration_id]        = @integration.id
        payload[:app_id]                = @integration.id
        payload[:name]                  = @integration.name
        payload[:slug]                  = @integration.slug
        payload[:org]                   = @org.to_s
        payload[:org_id]                = @org.id
        payload[:repository_selection]  = "all"
        payload[:requester_id]          = nil

      end

      expected_payload_for_added = expected_base_payload.merge(
        repositories_added: [@repo_1.id, @public_repo.id],
        repositories_added_names: [@repo_1.full_name, @public_repo.full_name],
      )

      assert event = events.pop, "not instrumented"
      assert_same_hash expected_payload_for_added, event.payload
    end

    test "switch to installation on all repos only includes those owned by the target" do
      user        = create :paid_user
      user_repo   = create(:private_repository, :minimal, owner: user)
      user_repo_2 = create(:private_repository, owner: user)

      events = subscribe "integration_installation.repositories_added"

      # setup fork of org-owned repo, that is owned by another user, and the user has indirect access to
      forker = create :paid_user, login: "forker"
      org_team = create(:team, organization: @org)
      org_team.add_member(forker)
      org_team.add_member(forker)
      org_team.add_repository(@repo, :pull)
      @org.add_admin user
      @org.allow_private_repository_forking(actor: user)
      org_private_repo_fork = create(:fork_repository, forker: forker, fork_repo: @repo)
      assert org_private_repo_fork
      assert_includes user.associated_repository_ids, org_private_repo_fork.id

      # setup org-owned fork of private repo owned by an org that the user is an admin of
      foreign_org = create :organization, login: "foreign-org", admin: user
      oopf = create(:fork_repository, forker: user, fork_repo: @repo.reload, organization: foreign_org)
      assert oopf
      user.reload
      assert_includes user.associated_repository_ids, oopf.id

      installation = IntegrationInstallation::Creator.perform(
        @integration,
        user,
        repositories: [user_repo],
        version: @integration.latest_version,
        installer: user,
        entry_point: :test_case,
        ).installation

      edited_installation = IntegrationInstallation::Editor.perform(
        installation,
        repositories: nil,
        editor: user,
        entry_point: :test_case,
        ).installation

      assert_equal 2, edited_installation.repository_ids.count

      expected_repositories = [user_repo_2.id]
      assert event = events.pop, "not instrumented"
      assert_equal expected_repositories, event.payload[:repositories_added]
    end
  end

  context "append" do
    test "validates that editor has permission" do
      other_user = create(:user, login: "other-user")

      installation = make_integration_installation(integration: @integration, repository: create(:repository, :minimal, owner: other_user))

      result = IntegrationInstallation::Editor.append(
        installation,
        editor: @admin,
        repositories: [create(:repository, :minimal, owner: other_user)],
      )

      assert_predicate result, :failed?
      assert_equal "You do not have permission to modify this app on other-user.", result.error
      assert_equal :not_admin_on_subset, result.reason
    end

    test "updates installation to include specified repositories" do
      installation = make_integration_installation(integration: @integration, repository: @repo)

      result = IntegrationInstallation::Editor.append(
        installation,
        editor: @admin,
        repositories: [@repo_1],
        entry_point: :test_case
      )

      assert_predicate result, :success?
    end

    test "updates installation's updated_at timestamp" do
      installation = make_integration_installation(integration: @integration, repository: @repo)
      previous_updated_at = installation.updated_at

      Timecop.travel(1.minute.from_now) do
        result = IntegrationInstallation::Editor.append(
          installation,
          editor: @admin,
          repositories: [@repo_1],
          entry_point: :test_case
        )
        new_updated_at = installation.reload.updated_at

        assert_predicate result, :success?
        assert_operator previous_updated_at, :<, new_updated_at
      end
    end

    test "leaves existing installation repositories intact" do
      installation = make_integration_installation(integration: @integration, repository: @repo)

      result = IntegrationInstallation::Editor.append(
        installation,
        editor: @admin,
        repositories: [@repo_1],
        entry_point: :test_case
      )

      assert_predicate result, :success?

      assert_same_elements [@repo, @repo_1], installation.repositories
    end

    context "primary/replica queries" do
      test "appending permissions only queries primary when absolutely necessary", skip_enterprise: true do
        installation = make_integration_installation(integration: @integration, repository: @repo)

        # We should only be querying the primary to write, which means no
        # repositories. We do expect queries against the permissions table
        # (obvs.) and Mysql1 to update the installation's updated_at timestamp
        # for cache invalidation.
        primary_clusters_and_counts = {
          ApplicationRecord::Collab => 0,
          ApplicationRecord::Mysql1 => 1, # <-- Invalidates the cache on integration_installations
          ApplicationRecord::Permissions => 1, # <-- Appends the repo to the installation
          ApplicationRecord::Repositories => 0,
        }

        replica_clusters_and_counts = {
          ApplicationRecord::Collab => 3,
          ApplicationRecord::Mysql1 => TestEnv.test_all_features? ? 10 : 7,
          ApplicationRecord::Permissions => 9,
          ApplicationRecord::Repositories => 5,
        }

        assert_query_count_against_primary(clusters_and_counts: primary_clusters_and_counts) do
          assert_query_count_against_replicas(clusters_and_counts: replica_clusters_and_counts) do
            result = IntegrationInstallation::Editor.append(
              installation,
              editor: @admin,
              repositories: [@repo_1],
              entry_point: :test_case
            )
            assert_predicate result, :success?
          end
        end
      end

      test "editing all repos makes cluster queries", skip_enterprise: true do
        new_installation = IntegrationInstallation::Creator.perform(
          @integration,
          @org,
          repositories: [@repo],
          version: @integration.latest_version,
          installer: @admin,
          entry_point: :test_case,
        ).installation

        refute new_installation.installed_on_all_repositories?

        10.times { create(:repository, owner: @org) }

        primary_clusters_and_counts = {
          ApplicationRecord::Collab => 13, # n+1 trade_control_restrictions from instrumentation
          ApplicationRecord::Configurations => 1,
          ApplicationRecord::Mysql1 => 23, # n+1 business_organization_memberships from instrumentation
          ApplicationRecord::Permissions => 5,
          ApplicationRecord::Repositories => 16, # n+1 internal_repositories & repository_networks from instrumentation
        }
        replica_clusters_and_counts = {
          ApplicationRecord::Collab => 0,
          ApplicationRecord::Configurations => 0,
          ApplicationRecord::Mysql1 => TestEnv.test_all_features? ? 6 : 0,
          ApplicationRecord::Permissions => TestEnv.test_all_features? ? 5 : 4,
          ApplicationRecord::Repositories => 1,
        }

        result = assert_query_count_against_primary(clusters_and_counts: primary_clusters_and_counts) do
          assert_query_count_against_replicas(clusters_and_counts: replica_clusters_and_counts) do
            IntegrationInstallation::Editor.perform(
              new_installation,
              repositories: nil,
              editor: @admin,
              entry_point: :test_case,
            )
          end
        end

        assert result.installation.installed_on_all_repositories?
      end
    end
  end
end
