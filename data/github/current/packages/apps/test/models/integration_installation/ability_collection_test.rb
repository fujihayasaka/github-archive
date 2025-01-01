# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationInstallationAbilityCollectionTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    # The IntegrationInstallation::AbilityCollection extention is used by
    # several collections of sub-resources on a Repository. We could use any one of them for our
    # tests. In this case, we're choosing to use the issues collection.
    @org = create(:organization, plan: "bronze")
    @owner = @org.admins.first

    @repo = create(:private_repository, owner: @org, from_example: :review_comment_fork)

    @collection = @repo.resources.issues
    @installation = make_integration_installation(repository: @repo, permissions: { "issues" => :read })
    @integration = @installation.integration

    @global_app = create_privileged_app_with_capabilities(permissions: { "issues" => :read }, capabilities: { installed_globally: true })

    @global_installation = GlobalIntegrationInstallation.new(@global_app, @global_app.owner)
    refute_nil @global_installation

    assert issue = create(:issue, repository: @repo)
    assert pull = PullRequest.create_for(@repo,
      base:  "master",
      head:  "topic",
      user:  @owner,
      issue: issue,
    )

    @pull = pull

    make_trusted_oauth_apps_owner
    actions_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(actions_app)

    @workflow_run = create(:check_suite_for_actions_app, repository: @repo).workflow_run
  end

  test "allows an IntegrationInstallation to be granted an ability on the collection" do
    user = create(:user)
    integration = create(:integration)
    result = integration.install_on(
      user,
      repositories: [create(:repository, :minimal, owner: user)],
      installer: user,
      entry_point: :test_case
    )
    assert result.success?
    installation = result.installation

    assert @collection.grant?(installation, :read)
  end

  test "does not allow anything other than an IntegrationInstallation to be granted an ability on the collection" do
    user = create(:user)
    refute @collection.grant?(user, :read)
  end

  context "#permit?" do
    test "returns true if the actor has permission on the parent of the collection" do
      user = create(:user)
      @repo.add_member(user)

      assert_able user, :read, @collection
    end

    test "returns true if the actor has permission on the collection" do
      @collection.add_actor(@installation, action: :read)

      assert_able @installation, :read, @collection
    end

    test "returns true if the actor has a permission for all private repos for this association" do
      org = create(:organization)
      org_repo = create(:private_repository, :minimal, owner: org)
      version = @integration.versions.create(
        default_permissions: { "issues" => :read },
      )

      installation = @integration.install_on(
        org, repositories: [],
        version: version,
        installer: org.admins.first,
        entry_point: :test_case
      ).installation

      assert_able installation, :read, org_repo.resources.issues
    end

    test "returns false if the actor does not have direct or indirect permission on this association" do
      org = create(:organization)
      org_repo = create(:private_repository, :minimal, owner: org)
      version = @integration.versions.create(
        default_permissions: { "issues" => :read },
      )

      installation = @integration.install_on(
        org, repositories: [],
        version: version,
        installer: org.admins.first,
        entry_point: :test_case
      ).installation

      refute_able installation, :read, org_repo.resources.statuses
    end

    test "returns false if the actor does not have direct administration access to the repository" do
      pub_repo = create(:repository, :minimal, owner: @org)
      refute_able @installation, :read, pub_repo.resources.administration
    end

    test "returns false if the actor does not have direct administration access to the repository for hook resources" do
      pub_repo = create(:repository, :minimal, owner: @org)
      refute_able @installation, :read, pub_repo.resources.repository_hooks
    end

    test "returns false if the actor does not have direct administration access to the repository for vulnerability alerts" do
      pub_repo = create(:repository, :minimal, owner: @org)
      refute_able @installation, :read, pub_repo.resources.vulnerability_alerts
    end

    test "returns false if the actor does not have direct administration access to the repository for secrets" do
      pub_repo = create(:repository, :minimal, owner: @org)
      refute_able @installation, :read, pub_repo.resources.secrets
    end

    test "returns false if the actor does not have direct administration access to the organization for web hooks" do
      refute_able @installation, :read, @org.resources.organization_hooks
    end

    test "returns false if the actor does not have direct administration access to the organization" do
      refute_able @installation, :read, @org.resources.organization_administration
    end

    test "returns false if the actor does not have direct administration access to the organization for blocking users" do
      refute_able @installation, :read, @org.resources.organization_user_blocking
    end

    test "returns false if the actor does not have direct administration access to the organization for reading the plan" do
      refute_able @installation, :read, @org.resources.organization_plan
    end

    test "User actor can read the plan for an org if they have admin permission" do
      assert_able @org.admins.first, :read, @org.resources.organization_plan
    end

    if GitHub.enterprise?
      test "returns false if the actor does not have direct administration access to the repository for pre-receive hooks" do
        pub_repo = create(:repository, :minimal, owner: @org)
        refute_able @installation, :read, pub_repo.resources.repository_pre_receive_hooks
      end

      test "returns false if the actor does not have direct administration access to the organization for pre-receive hooks" do
        refute_able @installation, :read, @org.resources.organization_pre_receive_hooks
      end
    end

    test "returns false if the actor has no direct access to the repo and the repo no longer has an owner" do
      owner = create(:paid_user, login: "owner")
      repo = create(:private_repository, owner: owner)
      user = create(:user)

      owner.delete

      refute_able user, :read, repo.resources.issues
    end

    test "returns true if neither the actor nor current installation have specific permission, but the Repository allows their access" do
      user = create(:user)
      org = create(:organization)
      org_repo = create(:public_repository, :minimal, owner: org)
      version = @integration.versions.create(
        default_permissions: { "statuses" => :write },
      )

      installation = @integration.install_on(
        org, repositories: [],
        version: version,
        installer: org.admins.first,
        entry_point: :test_case
      ).installation

      user.access_context = installation

      assert_able user, :read, org_repo.resources.issues
    end

    test "returns true if the actor and their current installation (on all repos) context has permission" do
      user = create(:user)
      org = create(:organization, admin: user)
      org_repo = create(:private_repository, :minimal, owner: org)
      version = @integration.versions.create(
        default_permissions: { "issues" => :write },
      )

      installation = @integration.install_on(
        org, repositories: [],
        version: version,
        installer: org.admins.first,
        entry_point: :test_case
      ).installation

      user.access_context = installation

      assert_able user, :write, org_repo.resources.issues
    end

    test "returns true if the actor and their current installation (on specific repos) context has permission" do
      user = create(:user)
      org = create(:organization, admin: user)
      org_repo = create(:private_repository, :minimal, owner: org)
      version = @integration.versions.create(
        default_permissions: { "issues" => :write },
      )

      installation = @integration.install_on(
        org, repositories: [org_repo],
        version: version,
        installer: org.admins.first,
        entry_point: :test_case
      ).installation

      user.access_context = installation

      assert_able user, :write, org_repo.resources.issues
    end

    test "returns false if the actor has permission, but their current installation (on all repos) context does not" do
      user = create(:user)
      org = create(:organization, admin: user)
      org_repo = create(:private_repository, :minimal, owner: org)
      version = @integration.versions.create(
        default_permissions: { "issues" => :read },
      )

      installation = @integration.install_on(
        org, repositories: [],
        version: version,
        installer: org.admins.first,
        entry_point: :test_case
      ).installation

      user.access_context = installation

      refute_able user, :write, org_repo.resources.issues
    end

    test "returns false if the actor has permission, but their current installation (on specific repos) context does not" do
      user = create(:user)
      org = create(:organization, admin: user)
      org_repo = create(:private_repository, :minimal, owner: org)
      version = @integration.versions.create(
        default_permissions: { "issues" => :read },
      )

      installation = @integration.install_on(
        org, repositories: [org_repo],
        version: version,
        installer: org.admins.first,
        entry_point: :test_case
      ).installation

      user.access_context = installation

      refute_able user, :write, org_repo.resources.issues
    end

    test "returns false if the actor does not have permission, and their current installation context does" do
      random_user = create(:user)
      org = create(:organization)
      org_repo = create(:private_repository, :minimal, owner: org)
      version = @integration.versions.create(
        default_permissions: { "issues" => :read },
      )

      installation = @integration.install_on(
        org, repositories: [org_repo],
        version: version,
        installer: org.admins.first,
        entry_point: :test_case
      ).installation

      random_user.access_context = installation

      refute_able random_user, :read, org_repo.resources.issues
    end

    test "gracefully handles missing repository owners" do
      installation = make_integration_installation(repository: @repo, permissions: { "metadata" => :read })

      @org.delete; @repo.reload
      assert_nil @repo.async_owner.sync

      refute_able installation, :read, @repo.resources.issues
    end

    context "PullRequest" do
      test "returns true if the actor has permission on the parent of the collection" do
        collaborator = create(:user)
        @repo.add_member(collaborator)

        collection = @pull.resources.sarifs
        assert_able collaborator, :write, collection
      end

      test "returns true if the actor has permission on the collection" do
        collection = @pull.resources.sarifs
        row = Permissions::Service.app_attributes(actor: @installation, subject: collection, action: :write)

        Permissions::Service.grant_permissions([row], entry_point: :test_case)
        collection.add_actor(@installation, action: :write)

        assert_able @installation, :write, collection
      end

      test "returns true if the actor has permission on the single private repo" do
        installation = make_integration_installation(repository: @repo, permissions: { "metadata" => :read, "pull_requests" => :write })

        collection = @pull.resources.sarifs
        assert_able installation, :write, collection
      end

      test "returns false if the actor does not have proper action but has permission on the single private repo" do
        installation = make_integration_installation(repository: @repo, permissions: { "metadata" => :read, "pull_requests" => :read })

        collection = @pull.resources.sarifs
        refute_able installation, :write, collection
      end

      test "returns true if the actor has a permission for all private repos for this association" do
        installation = make_integration_installation(target: @org, permissions: { "metadata" => :read, "pull_requests" => :write })
        assert_able installation, :read, @pull.resources.sarifs
      end

      test "returns false if the actor does not have direct or indirect permission on this association" do
        installation = make_integration_installation(target: @org, permissions: { "metadata" => :read })
        refute_able installation, :read, @pull.resources.sarifs
      end

      test "gracefully handles missing repository owners" do
        installation = make_integration_installation(target: @org, permissions: { "metadata" => :read })

        @org.delete; @repo.reload
        assert_nil @repo.async_owner.sync

        refute_able installation, :read, @pull.resources.sarifs
      end
    end

    context "WorkflowRun" do
      test "returns false if the actor has permission on the parent of the collection" do
        collaborator = create(:user)
        @repo.add_member(collaborator)

        collection = @workflow_run.resources.codespaces_prebuild
        refute_able collaborator, :write, collection
      end

      test "returns true if the actor has permission on the collection" do
        collection = @workflow_run.resources.codespaces_prebuild
        row = Permissions::Service.app_attributes(actor: @installation, subject: collection, action: :write)

        Permissions::Service.grant_permissions([row], entry_point: :test_case)
        collection.add_actor(@installation, action: :write)

        assert_able @installation, :write, collection
      end

      test "returns false if the actor does not have proper action but has permission on the single private repo" do
        installation = make_integration_installation(repository: @repo, permissions: { "metadata" => :read, "actions" => :read })

        collection = @workflow_run.resources.codespaces_prebuild
        refute_able installation, :write, collection
      end

      test "returns false if the actor does not have direct or indirect permission on this association" do
        installation = make_integration_installation(target: @org, permissions: { "metadata" => :read })
        refute_able installation, :read, @workflow_run.resources.codespaces_prebuild
      end
    end

    context "advisory workspaces" do
      context "with indirect access" do
        test "returns false if the installation is installed on the target" do
          GitHub.flipper[:maintainer_love_advisory_workspaces_can_use_actions].disable
          repository = create(:repository, :minimal)
          author     = repository.owner
          advisory   = create(:repository_advisory, repository: repository, author: author)

          GitHub.context.push(actor_id: author.id)
          workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, author).tap(&:save!)
          installation   = make_integration_installation(target: author, permissions: { "metadata" => :read })

          # Even if we have indirect access by way of a target installation,
          # we should not be able to access the workspace repository
          assert_able installation, :read, author.repository_resources.metadata
          refute_able installation, :read, workspace_repo.resources.metadata
        end
      end

      context "with direct access" do
        test "returns false if the installation is installed directly on the workspace repo" do
          owner            = create(:user)
          workspace_parent = create(:repository, owner: owner)

          GitHub.context.push(actor_id: owner.id)
          advisory       = create(:repository_advisory, repository: workspace_parent, author: owner)
          workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, owner).tap(&:save!)

          installation = make_integration_installation(repository: workspace_parent, permissions: { "metadata" => :read })
          assert_able installation, :read, workspace_parent.resources.metadata

          # Even if we directly add the workspace repository to the installation
          # doesn't have access to it.
          workspace_repo.resources.metadata.add_actor(installation, action: :read)
          refute_able installation, :read, workspace_repo.resources.metadata
        end
      end

      context "pull request permission" do
        context "with indirect access" do
          test "returns false if the installation is installed on the target" do
            GitHub.flipper[:maintainer_love_advisory_workspaces_can_use_actions].disable
            workspace_parent, _, pull = create_workspace_pull_request
            author = workspace_parent.owner

            installation = make_integration_installation(target: author, permissions: { "metadata" => :read, "pull_requests" => :write })

            # Even if we have indirect access by way of a target installation,
            # we should not be able to access the workspace repository
            assert_able installation, :write, author.repository_resources.pull_requests
            refute_able installation, :write, pull.resources.sarifs
          end
        end

        context "with direct access" do
          test "returns false if the installation is installed directly on the workspace repo" do
            GitHub.flipper[:maintainer_love_advisory_workspaces_can_use_actions].disable
            workspace_parent, workspace_repo, pull = create_workspace_pull_request

            installation = make_integration_installation(repository: workspace_parent, permissions: { "metadata" => :read, "pull_requests" => :write })
            assert_able installation, :write, workspace_parent.resources.pull_requests

            # Even if we directly add the workspace repository to the installation
            # doesn't have access to it.
            row = Permissions::Service.app_attributes(actor: installation, subject: workspace_repo.resources.pull_requests, action: :write)
            Permissions::Service.grant_permissions([row], entry_point: :test_case)

            refute_able installation, :write, pull.resources.sarifs
          end

          test "returns false if the installation has been granted explicit permission on the pull request" do
            GitHub.flipper[:maintainer_love_advisory_workspaces_can_use_actions].disable
            workspace_parent, _, pull = create_workspace_pull_request

            installation = make_integration_installation(repository: workspace_parent, permissions: { "metadata" => :read, "pull_requests" => :write })
            assert_able installation, :write, workspace_parent.resources.pull_requests

            # Even if we directly add the workspace repository to the installation
            # doesn't have access to it.
            row = Permissions::Service.app_attributes(actor: installation, subject: pull.resources.sarifs, action: :write)
            Permissions::Service.grant_permissions([row], entry_point: :test_case)

            refute_able installation, :write, pull.resources.sarifs
          end
        end
      end
    end

    # It is known that these tests will fail when using a resource that uses Authzd permission checks (currently just contents)
    # because Authzd intentionally does not yet support global installation actors
    # https://github.com/github/ecosystem-apps/issues/4006
    context "global installations" do
      test "returns true if the actor has permission on the collection" do
        assert @global_installation.permissions.key?("issues"), "expected the global installation to have issues permission"
        assert_able @global_installation, :read, @collection
      end

      test "returns false if the actor does not have direct permission on this association" do
        refute @global_installation.permissions.key?("deployments"), "expected the global installation to not have deployments permission"
        refute_able @global_installation, :read, @repo.resources.deployments
      end

      test "returns false if the actor does not have direct administration access to the repository" do
        refute @global_installation.permissions.key?("administration"), "expected the global installation to not have repository administration permission"
        refute_able @global_installation, :read, @repo.resources.administration
      end

      test "returns true if the actor does not have specific permission, but the Repository allows their access" do
        org_repo = create(:public_repository, :minimal)

        refute @global_installation.permissions.key?("deployments"), "expected the global installation to not have deployments permission"
        assert_able @global_installation, :read, org_repo.resources.deployments
      end

      test "returns true if neither the actor nor the installation have specific permission, but the Repository allows their access" do
        user = create(:user)

        org      = create(:organization)
        org_repo = create(:public_repository, :minimal, owner: org)

        user.access_context = @global_installation
        assert_able user, :read, org_repo.resources.issues
      end

      test "returns true if the actor and the installation context has permission" do
        user = create(:user)

        org      = create(:organization, admin: user)
        org_repo = create(:private_repository, :minimal, owner: org)

        user.access_context = @global_installation
        assert_able user, :read, org_repo.resources.issues
      end

      test "returns false if the actor has permission, but the installation does not" do
        user = create(:user)

        org      = create(:organization, admin: user)
        org_repo = create(:private_repository, :minimal, owner: org)

        user.access_context = @global_installation
        refute_able user, :write, org_repo.resources.deployments
      end

      test "returns false if the actor does not have permission, and the installation does" do
        random_user = create(:user)

        org      = create(:organization)
        org_repo = create(:private_repository, :minimal, owner: org)

        random_user.access_context = @global_installation
        refute_able random_user, :read, org_repo.resources.issues
      end
    end

    test "it tracks actor and subjects" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @collection.add_actor(@installation, action: :read)
      assert_able @installation, :read, @collection
      key = "platform.loaders.permission.fetch.actor_and_subject_ids"
      assert_equal 1, GitHub.dogstats.distributions(key).first.value
    end
  end

  private

  def create_workspace_pull_request
    workspace_parent = create(:repository, from_example: :simple)

    author   = workspace_parent.owner
    advisory = create(:repository_advisory, repository: workspace_parent, author: author)

    workspace_repo = perform_enqueued_jobs(only: [RepositoryCloneJob]) do
      GitHub.context.push(actor_id: author.id)
      RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(advisory, author).tap(&:save!).tap(&:reload)
    end

    ref = workspace_repo.heads.find("master")
    ref.append_commit({ message: "blah", committer: author }, author) do |files|
      files.add("README.md", "change")
    end

    pull = PullRequest.create(
      repository:      workspace_repo,
      base_repository: workspace_parent,
      base_user:       workspace_parent.owner,
      base_ref:        "master",
      head_repository: workspace_repo,
      head_user:       workspace_repo.owner,
      head_ref:        "master",
      issue:           create(:issue, user: author, repository: workspace_repo),
      user:            author,
    )

    assert_predicate pull, :valid?
    assert_predicate pull, :persisted?

    [workspace_parent, workspace_repo, pull]
  end
end
