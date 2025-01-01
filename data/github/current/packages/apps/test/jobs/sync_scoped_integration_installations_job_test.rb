# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/permissions_helper"

class SyncScopedIntegrationInstallationsJobTest < GitHub::TestCase
  include JobTestHelper
  include PermissionsHelper
  include GitHub::DatabaseQueryWarningsTestHelpers

  fixtures do
    @user = create(:user, login: "target")

    @org = create(:organization)
    @org_admin = T.must(@org.admins.first)

    @repo1 = create(:repository, :minimal, owner: @user)
    @repo2 = create(:repository, :minimal, owner: @user)

    @parent = make_integration_installation(repositories: [@repo1, @repo2], permissions: { "metadata" => :read })
    @installation = make_scoped_integration_installation(parent: @parent, repositories: [@repo1, @repo2])
    @access = @parent.integration.grant(@user, entry_point: :test_case)

    @parent_all_repos = make_integration_installation(target: @user, permissions: { "metadata" => :read })
    @installation_all_repos = make_scoped_integration_installation(parent: @parent_all_repos, repositories: :all)
    @access_all_repos = @parent_all_repos.integration.grant(@user, entry_point: :test_case)

    @parent_on_org = make_integration_installation(target: @org, permissions: { "members" => :write })
    @installation_with_org_permissions = make_scoped_integration_installation(parent: @parent_on_org, repositories: [])
    @access_on_org = @parent_on_org.integration.grant(@org_admin, entry_point: :test_case)
  end

  context "permissions_updated" do
    context "'active' scoped installations" do
      context "does not add Repository permissions" do
        test "s2s on select repositories" do
          assert_no_query_warnings do
            Timecop.freeze do
              # Create a token so that the installation is considered 'active'
              @installation.generate_token

              old_version = @parent.version
              new_version = @parent.integration.versions.create(default_permissions: { "metadata" => :read, "issues" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo1.resources.metadata, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo2.resources.metadata, action: :read)

              refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo1.resources.issues, action: :read)
              refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo2.resources.issues, action: :read)

              SyncScopedIntegrationInstallationsJob.perform_now(@parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo1.resources.metadata, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo2.resources.metadata, action: :read)

              refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo1.resources.issues, action: :read)
              refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo2.resources.issues, action: :read)
            end
          end
        end

        test "u2s on select repositories" do
          assert_no_query_warnings do
            Timecop.freeze do
              scoped_access, error_response = @parent.integration.grant_scoped_access_from(@access, @user, entry_point: :test_case)
              installation = scoped_access.installation

              old_version = @parent.version
              new_version = @parent.integration.versions.create(default_permissions: { "metadata" => :read, "issues" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo1.resources.metadata, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo2.resources.metadata, action: :read)

              refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo1.resources.issues, action: :read)
              refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo2.resources.issues, action: :read)

              SyncScopedIntegrationInstallationsJob.perform_now(@parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo1.resources.metadata, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo2.resources.metadata, action: :read)

              refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo1.resources.issues, action: :read)
              refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo2.resources.issues, action: :read)
            end
          end
        end

        test "s2s on all repositories" do
          assert_no_query_warnings do
            Timecop.freeze do
              # Create a token so that the installation is considered 'active'
              @installation_all_repos.generate_token

              old_version = @parent_all_repos.version
              new_version = @parent_all_repos.integration.versions.create(default_permissions: { "metadata" => :read, "issues" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.metadata, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.metadata, action: :read)

              refute_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.issues, action: :read)
              refute_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.issues, action: :read)

              SyncScopedIntegrationInstallationsJob.perform_now(@parent_all_repos, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.metadata, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.metadata, action: :read)

              refute_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.issues, action: :read)
              refute_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.issues, action: :read)
            end
          end
        end

        test "u2s with all repositories" do
          assert_no_query_warnings do
            Timecop.freeze do
              scoped_access, error_response = @parent_all_repos.integration.grant_scoped_access_from(@access_all_repos, @user, entry_point: :test_case)
              installation = scoped_access.installation

              old_version = @parent_all_repos.version
              new_version = @parent_all_repos.integration.versions.create(default_permissions: { "metadata" => :read, "issues" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.metadata, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.metadata, action: :read)

              refute_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.issues, action: :read)
              refute_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.issues, action: :read)

              SyncScopedIntegrationInstallationsJob.perform_now(@parent_all_repos, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.metadata, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.metadata, action: :read)

              refute_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.issues, action: :read)
              refute_actor_and_subject_granted_in_permissions_table(actor: @installation_all_repos, subject: @user.repository_resources.issues, action: :read)
            end
          end
        end
      end

      context "does not add Organization permissions" do
        test "s2s" do
          assert_no_query_warnings do
            Timecop.freeze do
              # Create a token so that the installation is considered 'active'
              @installation_with_org_permissions.generate_token

              old_version = @parent_on_org.version
              new_version = @parent_on_org.integration.versions.create(default_permissions: { "members" => :write, "organization_administration" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: @installation_with_org_permissions, subject: @org.resources.members, action: :write)
              refute_actor_and_subject_granted_in_permissions_table(actor: @installation_with_org_permissions, subject: @org.resources.organization_administration, action: :write)

              SyncScopedIntegrationInstallationsJob.perform_now(@parent_on_org, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: @installation_with_org_permissions, subject: @org.resources.members, action: :write)
              refute_actor_and_subject_granted_in_permissions_table(actor: @installation_with_org_permissions, subject: @org.resources.organization_administration, action: :write)
            end
          end
        end
      end

      context "does not upgrade Repository permissions" do
        test "s2s with select repos" do
          assert_no_query_warnings do
            Timecop.freeze do
              parent = make_integration_installation(repositories: [@repo1, @repo2], permissions: { "issues" => :read })
              installation = make_scoped_integration_installation(parent: parent, repositories: [@repo1, @repo2])

              # Create a token so that the installation is considered 'active'
              installation.generate_token

              old_version = parent.version
              new_version = parent.integration.versions.create(default_permissions: { "issues" => :write })

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues, action: :read)

              SyncScopedIntegrationInstallationsJob.perform_now(parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues, action: :read)
            end
          end
        end

        test "u2s with select repos" do
          assert_no_query_warnings do
            Timecop.freeze do
              parent = make_integration_installation(repositories: [@repo1, @repo2], permissions: { "issues" => :read })

              scoped_access, error_response = parent.integration.grant_scoped_access_from(@access, @user, entry_point: :test_case)
              installation = scoped_access.installation

              old_version = parent.version
              new_version = parent.integration.versions.create(default_permissions: { "issues" => :write })

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues, action: :read)

              SyncScopedIntegrationInstallationsJob.perform_now(parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues, action: :read)
            end
          end
        end

        test "s2s with all repos" do
          assert_no_query_warnings do
            Timecop.freeze do
              parent = make_integration_installation(target: @user, permissions: { "issues" => :read })
              installation = make_scoped_integration_installation(parent: parent, repositories: :all)

              # Create a token so that the installation is considered 'active'
              installation.generate_token

              old_version = parent.version
              new_version = parent.integration.versions.create(default_permissions: { "issues" => :write })

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :read)

              SyncScopedIntegrationInstallationsJob.perform_now(parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :read)
            end
          end
        end

        test "u2s with all repos" do
          assert_no_query_warnings do
            Timecop.freeze do
              parent = make_integration_installation(target: @user, permissions: { "issues" => :read })
              scoped_access, error_response = parent.integration.grant_scoped_access_from(@access_all_repos, @user, entry_point: :test_case)
              installation = scoped_access.installation

              old_version = parent.version
              new_version = parent.integration.versions.create(default_permissions: { "issues" => :write })

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :read)

              SyncScopedIntegrationInstallationsJob.perform_now(parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :read)
            end
          end
        end
      end

      context "downgrades Repository permissions" do
        test "s2s with select repos" do
          assert_no_query_warnings do
            Timecop.freeze do
              parent = make_integration_installation(repositories: [@repo1, @repo2], permissions: { "issues" => :write })
              installation = make_scoped_integration_installation(parent: parent, repositories: [@repo1, @repo2])

              # Create a token so that the installation is considered 'active'
              installation.generate_token

              old_version = parent.version
              new_version = parent.integration.versions.create(default_permissions: { "issues" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues, action: :write)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues, action: :write)

              SyncScopedIntegrationInstallationsJob.perform_now(parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues, action: :read)
            end
          end
        end

        test "u2s with select repos" do
          assert_no_query_warnings do
            Timecop.freeze do
              user = @repo1.owner
              upgraded_permissions = { "issues" => :write, "metadata" => :read }
              downgraded_permissions = { "issues" => :read, "metadata" => :read }

              integration = create(:integration, owner: user, default_permissions: upgraded_permissions)
              parent = make_integration_installation(integration: integration, repositories: [@repo1, @repo2])

              access = integration.grant(user, entry_point: :test_case)
              scoped_access, error_response = integration.grant_scoped_access_from(access, user, entry_point: :test_case)
              installation = scoped_access.installation

              assert_same_hash upgraded_permissions, installation.permissions

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues, action: :write)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues, action: :write)

              old_version = parent.version
              new_version = parent.integration.versions.create(default_permissions: downgraded_permissions)

              SyncScopedIntegrationInstallationsJob.perform_now(parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues, action: :read)
            end
          end
        end

        test "s2s with all repos" do
          assert_no_query_warnings do
            Timecop.freeze do
              parent = make_integration_installation(target: @user, permissions: { "issues" => :write })
              installation = make_scoped_integration_installation(parent: parent, repositories: :all)

              # Create a token so that the installation is considered 'active'
              installation.generate_token

              old_version = parent.version
              new_version = parent.integration.versions.create(default_permissions: { "issues" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :write)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :write)

              SyncScopedIntegrationInstallationsJob.perform_now(parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :read)
            end
          end
        end

        test "u2s with all repos" do
          assert_no_query_warnings do
            Timecop.freeze do
              user = @repo1.owner
              upgraded_permissions = { "issues" => :write, "metadata" => :read }
              downgraded_permissions = { "issues" => :read, "metadata" => :read }

              integration = create(:integration, owner: user, default_permissions: upgraded_permissions)
              parent = make_integration_installation(integration: integration, target: user)

              access = integration.grant(user, entry_point: :test_case)
              scoped_access, error_response = integration.grant_scoped_access_from(access, user, entry_point: :test_case)
              installation = scoped_access.installation

              assert_same_hash upgraded_permissions, installation.permissions

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: user.repository_resources.issues, action: :write)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: user.repository_resources.issues, action: :write)

              old_version = parent.version
              new_version = parent.integration.versions.create(default_permissions: downgraded_permissions)

              SyncScopedIntegrationInstallationsJob.perform_now(parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: user.repository_resources.issues, action: :read)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: user.repository_resources.issues, action: :read)
            end
          end
        end
      end

      context "downgrades Organization permissions" do
        test "s2s" do
          assert_no_query_warnings do
            Timecop.freeze do
              # Create a token so that the installation is considered 'active'
              @installation_with_org_permissions.generate_token

              old_version = @parent_on_org.version
              new_version = @parent_on_org.integration.versions.create(default_permissions: { "members" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: @installation_with_org_permissions, subject: @org.resources.members, action: :write)

              SyncScopedIntegrationInstallationsJob.perform_now(@parent_on_org, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: @installation_with_org_permissions, subject: @org.resources.members, action: :read)
            end
          end
        end

        test "us2" do
          assert_no_query_warnings do
            Timecop.freeze do
              scoped_access, error_response = @parent_on_org.integration.grant_scoped_access_from(@access_on_org, @org, entry_point: :test_case)
              installation = scoped_access.installation

              old_version = @parent_on_org.version
              new_version = @parent_on_org.integration.versions.create(default_permissions: { "members" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @org.resources.members, action: :write)

              SyncScopedIntegrationInstallationsJob.perform_now(@parent_on_org, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @org.resources.members, action: :read)
            end
          end
        end
      end

      context "removes Repository permissions" do
        test "s2s with select repos" do
          assert_no_query_warnings do
            Timecop.freeze do
              parent = make_integration_installation(repositories: [@repo1, @repo2], permissions: { "metadata" => :read, "issues" => :write })
              installation = make_scoped_integration_installation(parent: parent, repositories: [@repo1, @repo2])

              # Create a token so that the installation is considered 'active'
              installation.generate_token

              old_version = parent.version
              new_version = parent.integration.versions.create(default_permissions: { "metadata" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues, action: :write)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues, action: :write)

              SyncScopedIntegrationInstallationsJob.perform_now(parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues)
              refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues)
            end
          end
        end

        test "u2s with select repos" do
          assert_no_query_warnings do
            Timecop.freeze do
              parent = make_integration_installation(repositories: [@repo1, @repo2], permissions: { "metadata" => :read, "issues" => :write })

              scoped_access, error_response = parent.integration.grant_scoped_access_from(@access, @user, entry_point: :test_case)
              installation = scoped_access.installation

              old_version = parent.version
              new_version = parent.integration.versions.create(default_permissions: { "metadata" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues, action: :write)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues, action: :write)

              SyncScopedIntegrationInstallationsJob.perform_now(parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues)
              refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues)
            end
          end
        end

        test "s2s with all repos" do
          assert_no_query_warnings do
            Timecop.freeze do
              parent = make_integration_installation(target: @user, permissions: { "metadata" => :read, "issues" => :write })
              installation = make_scoped_integration_installation(parent: parent, repositories: :all)

              # Create a token so that the installation is considered 'active'
              installation.generate_token

              old_version = parent.version
              new_version = parent.integration.versions.create(default_permissions: { "metadata" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :write)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :write)

              SyncScopedIntegrationInstallationsJob.perform_now(parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues)
              refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues)
            end
          end
        end

        test "u2s with all repos" do
          assert_no_query_warnings do
            Timecop.freeze do
              parent = make_integration_installation(target: @user, permissions: { "metadata" => :read, "issues" => :write })

              scoped_access, error_response = parent.integration.grant_scoped_access_from(@access_all_repos, @user, entry_point: :test_case)
              installation = scoped_access.installation

              old_version = parent.version
              new_version = parent.integration.versions.create(default_permissions: { "metadata" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :write)
              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues, action: :write)

              SyncScopedIntegrationInstallationsJob.perform_now(parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues)
              refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @user.repository_resources.issues)
            end
          end
        end
      end

      context "removes Organization permissions" do
        test "s2s" do
          assert_no_query_warnings do
            Timecop.freeze do
              # Create a token so that the installation is considered 'active'
              @installation_with_org_permissions.generate_token

              old_version = @parent_on_org.version
              new_version = @parent_on_org.integration.versions.create(default_permissions: { "organization_administration" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: @installation_with_org_permissions, subject: @org.resources.members, action: :write)
              refute_actor_and_subject_granted_in_permissions_table(actor: @installation_with_org_permissions, subject: @org.resources.organization_administration)

              SyncScopedIntegrationInstallationsJob.perform_now(@parent_on_org, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              refute_actor_and_subject_granted_in_permissions_table(actor: @installation_with_org_permissions, subject: @org.resources.members)
              refute_actor_and_subject_granted_in_permissions_table(actor: @installation_with_org_permissions, subject: @org.resources.organization_administration)
            end
          end
        end

        test "us2" do
          assert_no_query_warnings do
            Timecop.freeze do
              scoped_access, error_response = @parent_on_org.integration.grant_scoped_access_from(@access_on_org, @org, entry_point: :test_case)
              installation = scoped_access.installation

              old_version = @parent_on_org.version
              new_version = @parent_on_org.integration.versions.create(default_permissions: { "organization_administration" => :read })

              assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @org.resources.members, action: :write)
              refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @org.resources.organization_administration)

              SyncScopedIntegrationInstallationsJob.perform_now(@parent_on_org, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

              refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @org.resources.members)
              refute_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @org.resources.organization_administration)
            end
          end
        end
      end
    end

    context "scoped installations that are no longer considered 'active'" do
      test "does not downgrade Repository permissions" do
        parent = make_integration_installation(repositories: [@repo1, @repo2], permissions: { "issues" => :write })
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo1, @repo2])

        # Create an token that is no longer active
        Timecop.freeze(Date.yesterday) do
          installation.generate_token
        end

        old_version = parent.version
        new_version = parent.integration.versions.create(default_permissions: { "issues" => :read })

        assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues, action: :write)
        assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues, action: :write)

        SyncScopedIntegrationInstallationsJob.perform_now(parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

        assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues, action: :write)
        assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues, action: :write)
      end

      test "does not remove Repository permissions" do
        parent = make_integration_installation(repositories: [@repo1, @repo2], permissions: { "metadata" => :read, "issues" => :write })
        installation = make_scoped_integration_installation(parent: parent, repositories: [@repo1, @repo2])

        # Create an token that is no longer active
        Timecop.freeze(Date.yesterday) do
          installation.generate_token
        end

        old_version = parent.version
        new_version = parent.integration.versions.create(default_permissions: { "metadata" => :read })

        assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues, action: :write)
        assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues, action: :write)

        SyncScopedIntegrationInstallationsJob.perform_now(parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case)

        assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo1.resources.issues, action: :write)
        assert_actor_and_subject_granted_in_permissions_table(actor: installation, subject: @repo2.resources.issues, action: :write)
      end
    end
  end

  context "repositories_removed" do
    test "uninstalls repositories from 'active' scoped installations" do
      Timecop.freeze do
        # Create a token so that the installation is considered 'active'
        @installation.generate_token

        assert_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo1.resources.metadata, action: :read)

        SyncScopedIntegrationInstallationsJob.perform_now(@parent, action: :repositories_removed, repository_ids: [@repo1.id], entry_point: :test_case)

        refute_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo1.resources.metadata, action: :read)
      end
    end

    test "does not uninstall repositories whose tokens have expired" do
      assert_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo1.resources.metadata, action: :read)

      SyncScopedIntegrationInstallationsJob.perform_now(@parent, action: :repositories_removed, repository_ids: [@repo1.id], entry_point: :test_case)

      assert_actor_and_subject_granted_in_permissions_table(actor: @installation, subject: @repo1.resources.metadata, action: :read)
    end

    test "does not raise a GitHub::SQL::BadValue if there aren't any repository_ids" do
      Timecop.freeze do
        # Create a token so that the installation is considered 'active'
        @installation.generate_token
        SyncScopedIntegrationInstallationsJob.perform_now(@parent, action: :repositories_removed, repository_ids: [], entry_point: :test_case)
      end
    end

    test "does not raise a GitHub::SQL::BadValue if there aren't repository permissions" do
      Timecop.freeze do
        version = create(:integration_version, integration: @parent.integration, default_permissions: {})
        @parent.update_version(editor: @user, version: version, entry_point: :test_case)

        refute_actor_and_subject_granted_in_permissions_table(actor: @parent, subject: @repo1.resources.metadata, action: :read)

        # Create a token so that the installation is considered 'active'
        @installation.generate_token
        SyncScopedIntegrationInstallationsJob.perform_now(@parent, action: :repositories_removed, repository_ids: [@repo1.id], entry_point: :test_case)
      end
    end
  end

  context "retry conditions" do
    test "retries on dirty exit" do
      old_version = @parent.version
      new_version = @parent.integration.versions.create(default_permissions: { "issues" => :write })

      assert_retry_on_dirty_exit job: SyncScopedIntegrationInstallationsJob, args: [@parent, action: :permissions_updated, old_version: old_version, new_version: new_version, entry_point: :test_case]
    end
  end
end
