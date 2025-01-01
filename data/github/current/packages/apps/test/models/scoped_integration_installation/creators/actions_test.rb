# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dogstats_test_helpers"
require "test_helpers/permissions_helper"

class ScopedIntegrationInstallation::Creators::ActionsTest < GitHub::TestCase
  include DogstatsTestHelpers
  include PermissionsHelper
  include GitHub::LoggerHelper

  fixtures do
    make_trusted_oauth_apps_owner
    @actions_app = create(:launch_integration)

    @user   = create(:user)
    @forker = create(:user)

    @repository       = create(:public_repository, owner: @user, from_example: :pull_request_fork)
    @other_repository = create(:public_repository, :minimal, owner: @user)

    repository_fork = create(:fork_repository, forker: @forker, fork_repo: @repository, from_example: :pull_request_fork)

    issue = create(:issue, repository: @repository, user: @forker, created_at: 5.hours.ago, assignee: @user)
    @pull  = PullRequest.create_for(@repository, user: @forker, base: "master", head: "#{@forker}:topic", title: "some title", body: "some body", issue: issue)

    @parent_installation = make_integration_installation(repository: @repository, permissions: { "metadata" => :read, "pull_requests" => :write, "actions" => :write })
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    GitHub.stubs(:launch_github_app).returns(@actions_app)
  end

  def create_workflow_run
    check_suite = create(:check_suite_for_actions_app, repository: @repository)
    check_suite.workflow_run
  end

  context "validation" do
    test "ensures the parent has access to all of the repositories requested" do
      result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
        "repositories" => [
          { "id" => @repository.id,           "permissions" => { "metadata" => "read" } },
          { "name" => @other_repository.name, "permissions" => { "metadata" => "read" } }
        ],
      }, entry_point: :test_case)

      assert_predicate result, :failed?
      assert_equal "There is at least one repository that does not exist or is not accessible to the parent installation.", result.error
    end

    test "ensures the parent has the appropriate level of access" do
      result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
        "repositories" => [
          { "id" => @repository.id, "permissions" => { "metadata" => "read", "contents" => "write" } },
        ],
      }, entry_point: :test_case)

      assert_predicate result, :failed?
      assert_equal "The permissions requested are not granted to this installation.", result.error
    end


    context "workflow_runs" do
      test "parent must have actions permission in order to request more granular permissions" do
        workflow_run = create_workflow_run
        version = IntegrationVersion.create(integration: @parent_installation.integration, default_permissions: { "metadata" => :read })
        @parent_installation.update_version(editor: @user, version: version, entry_point: :test_case); @parent_installation.reload

        result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
          "repositories" => [
            {
              "id" => @repository.id,
              "permissions" => { "metadata" => "read" },
              "workflow_runs" => [
                { "id" => workflow_run.id, "permissions" => { "codespaces_prebuild" => "write" } }
              ]
            },
          ],
        }, entry_point: :test_case)

        assert_predicate result, :failed?
        assert_equal ScopedIntegrationInstallation::Creators::Actions::MISSING_ACTIONS_ACCESS, result.error
      end

      test "does not allow invalid resources" do
        workflow_run = create_workflow_run
        result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
          "repositories" => [
            {
              "id" => @repository.id,
              "permissions" => { "metadata" => "read" },
              "workflow_runs" => [
                { "id" => workflow_run.id, "permissions" => { "contents" => "read" } }
              ]
            },
          ],
        }, entry_point: :test_case)

        assert_predicate result, :failed?
        assert_equal "There is at least one permission resource that is not supported.", result.error
      end

      test "does not allow invalid actions" do
        workflow_run = create_workflow_run
        result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
          "repositories" => [
            {
              "id" => @repository.id,
              "permissions" => { "metadata" => "read" },
              "workflow_runs" => [
                { "id" => workflow_run.id, "permissions" => { "codespaces_prebuild" => "foo" } }
              ]
            },
          ],
        }, entry_point: :test_case)

        assert_predicate result, :failed?
        assert_equal "There is at least one permission action that is not supported. It should be one of: \"read\", \"write\" or \"admin\".", result.error
      end

      test "ensure we don't escalate privilege" do
        workflow_run = create_workflow_run
        version = IntegrationVersion.create(integration: @parent_installation.integration, default_permissions: { "metadata" => :read, "actions" => :read })
        @parent_installation.update_version(editor: @user, version: version, entry_point: :test_case); @parent_installation.reload

        result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
          "repositories" => [
            {
              "id" => @repository.id,
              "permissions" => { "metadata" => "read" },
              "workflow_runs" => [
                { "id" => workflow_run.id, "permissions" => { "codespaces_prebuild" => "write" } }
              ]
            },
          ],
        }, entry_point: :test_case)

        assert_predicate result, :failed?
        assert_equal "The level of access for permissions requested are not granted to this installation.", result.error
      end

      test "does not allow duplicate workflow runs" do
        workflow_run = create_workflow_run
        result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
          "repositories" => [
            {
              "id" => @repository.id,
              "permissions" => { "metadata" => "read" },
              "workflow_runs" => [
                { "id" => workflow_run.id, "permissions" => { "codespaces_prebuild" => "write" } },
                { "id" => workflow_run.id, "permissions" => { "codespaces_prebuild" => "write" } }
              ]
            },
          ],
        }, entry_point: :test_case)

        assert_predicate result, :failed?
        assert_equal "There is at least one workflow run that has multiple entries", result.error
      end

      test "report ActiveRecord failures when inserting permissions and feature enabled" do
        workflow_run = create_workflow_run
        Permission.stubs(:insert_all!).raises(ActiveRecord::RecordInvalid)

        Failbot.expects(:report!).with do |e|
          assert_equal ActiveRecord::RecordInvalid, e.class
          assert_equal "Record invalid", e.message
        end

        result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
          "repositories" => [
            {
              "id" => @repository.id,
              "permissions" => { "metadata" => "read" },
              "workflow_runs" => [
                { "id" => workflow_run.id, "permissions" => { "codespaces_prebuild" => "write" } }
              ]
            },
          ],
        }, entry_point: :test_case)

        assert_predicate result, :failed?
        assert_equal "Failed to grant permissions.", result.error
      end
    end

    context "pull requests" do
      test "parent must have pull_request permission in order to request more granular permissions" do
        version = IntegrationVersion.create(integration: @parent_installation.integration, default_permissions: { "metadata" => :read })
        @parent_installation.update_version(editor: @user, version: version, entry_point: :test_case); @parent_installation.reload

        result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
          "repositories" => [
            {
              "id" => @repository.id,
              "permissions" => { "metadata" => "read" },
              "pull_requests" => [
                { "number" => @pull.number, "permissions" => { "sarifs" => "write" } }
              ]
            },
          ],
        }, entry_point: :test_case)

        assert_predicate result, :failed?
        assert_equal "This installation does not have Pull Request access, and therefore cannot grant other pull request based permissions.", result.error
      end

      test "does not allow invalid resources" do
        result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
          "repositories" => [
            {
              "id" => @repository.id,
              "permissions" => { "metadata" => "read" },
              "pull_requests" => [
                { "number" => @pull.number, "permissions" => { "contents" => "read" } }
              ]
            },
          ],
        }, entry_point: :test_case)

        assert_predicate result, :failed?
        assert_equal "There is at least one permission resource that is not supported.", result.error
      end

      test "does not allow invalid actions" do
        result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
          "repositories" => [
            {
              "id" => @repository.id,
              "permissions" => { "metadata" => "read" },
              "pull_requests" => [
                { "number" => @pull.number, "permissions" => { "sarifs" => "foo" } }
              ]
            },
          ],
        }, entry_point: :test_case)

        assert_predicate result, :failed?
        assert_equal "There is at least one permission action that is not supported. It should be one of: \"read\", \"write\" or \"admin\".", result.error
      end

      test "ensure we don't escalate privilege" do
        version = IntegrationVersion.create(integration: @parent_installation.integration, default_permissions: { "metadata" => :read, "pull_requests" => :read })
        @parent_installation.update_version(editor: @user, version: version, entry_point: :test_case); @parent_installation.reload

        result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
          "repositories" => [
            {
              "id" => @repository.id,
              "permissions" => { "metadata" => "read" },
              "pull_requests" => [
                { "number" => @pull.number, "permissions" => { "sarifs" => "write" } }
              ]
            },
          ],
        }, entry_point: :test_case)

        assert_predicate result, :failed?
        assert_equal "The level of access for permissions requested are not granted to this installation.", result.error
      end

      test "does not allow duplicate pull requests" do
        result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
          "repositories" => [
            {
              "id" => @repository.id,
              "permissions" => { "metadata" => "read" },
              "pull_requests" => [
                { "number" => @pull.number, "permissions" => { "sarifs" => "write" } },
                { "number" => @pull.number, "permissions" => { "sarifs" => "write" } }
              ]
            },
          ],
        }, entry_point: :test_case)

        assert_predicate result, :failed?
        assert_equal "There is at least one pull request that has multiple entries", result.error
      end
    end
  end

  test "sets an installation and permissions expiration time" do
    Timecop.freeze do
      result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
        "repositories" => [
          { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
        ],
      }, entry_point: :test_case)

      assert_predicate result, :success?
      refute_predicate result, :found_cached?

      installation = result.installation
      assert_predicate installation.expires_at, :present?

      permissions = Permission.where(actor: installation)
      assert_predicate permissions, :any?
      assert_equal installation.expires_at, permissions.last.expires_at
    end
  end

  test "grants permissions on a single repository" do
    result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
      "repositories" => [
        { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
      ],
    }, entry_point: :test_case)

    assert_predicate result, :success?

    actor   = result.installation
    subject = @repository.resources.metadata

    assert_actor_and_subject_granted_in_permissions_table(actor: actor, subject: subject, action: :read)
  end

  test "fails when duplicate repositories are introduced" do
    result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
      "repositories" => [
        { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
        { "name" => @repository.name, "permissions" => { "metadata" => "read" } },
      ],
    }, entry_point: :test_case)

    msg = "There is at least one repository that has been selected more than once. Please remove duplicate entries and try again."

    assert_predicate result, :failed?
    assert_equal msg, result.error
  end

  test "fails when duplicate repositories are introduced by id" do
    result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
      "repositories" => [
        { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
        { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
      ],
    }, entry_point: :test_case)

    msg = "There is at least one repository that has been selected more than once. Please remove duplicate entries and try again."

    assert_predicate result, :failed?
    assert_equal msg, result.error
  end

  test "fails when duplicate repositories are introduced by name" do
    result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
      "repositories" => [
        { "name" => @repository.name, "permissions" => { "metadata" => "read" } },
        { "name" => @repository.name, "permissions" => { "metadata" => "read" } },
      ],
    }, entry_point: :test_case)

    msg = "There is at least one repository that has been selected more than once. Please remove duplicate entries and try again."

    assert_predicate result, :failed?
    assert_equal msg, result.error
  end

  test "grants different permissions on a different repositories" do
    @parent_installation.edit(repositories: [@repository, @other_repository], editor: @user, entry_point: :test_case)
    @parent_installation.reload

    result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
      "repositories" => [
        { "id" => @repository.id,           "permissions" => { "metadata" => "read" } },
        { "name" => @other_repository.name, "permissions" => { "metadata" => "read", "pull_requests" => :read } },
      ],
    }, entry_point: :test_case)

    assert_predicate result, :success?
    actor = result.installation

    subject = @repository.resources.metadata
    assert_actor_and_subject_granted_in_permissions_table(actor: actor, subject: subject, action: :read)

    subject = @other_repository.resources.metadata
    assert_actor_and_subject_granted_in_permissions_table(actor: actor, subject: subject, action: :read)

    # We only granted metadata read on this repo
    subject = @repository.resources.pull_requests
    refute_actor_and_subject_granted_in_permissions_table(actor: actor, subject: subject, action: :read)

    subject = @other_repository.resources.pull_requests
    assert_actor_and_subject_granted_in_permissions_table(actor: actor, subject: subject, action: :read)
  end

  test "grants permissions on pull requests that belong to a repository" do
    result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
      "repositories" => [
        {
          "id" => @repository.id,
          "permissions" => { "metadata" => "read" },
          "pull_requests" => [
            { "number" => @pull.number, "permissions" => { "sarifs" => "write" } }
          ]
        },
      ],
    }, entry_point: :test_case)

    assert_predicate result, :success?

    actor = result.installation

    subject = @repository.resources.metadata
    assert_actor_and_subject_granted_in_permissions_table(actor: actor, subject: subject, action: :read)

    subject = @pull.resources.sarifs
    assert_actor_and_subject_granted_in_permissions_table(actor: actor, subject: subject, action: :write)
  end

  test "grants permission on workflow runs" do
    workflow_run = create_workflow_run
    result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
      "repositories" => [
        {
          "id" => @repository.id,
          "permissions" => { "metadata" => "read" },
          "workflow_runs" => [
            { "id" => workflow_run.id, "permissions" => { "codespaces_prebuild" => "write" } }
          ]
        },
      ],
    }, entry_point: :test_case)

    assert_predicate result, :success?

    actor = result.installation

    subject = @repository.resources.metadata
    assert_actor_and_subject_granted_in_permissions_table(actor: actor, subject: subject, action: :read)

    subject = workflow_run.resources.codespaces_prebuild
    assert_actor_and_subject_granted_in_permissions_table(actor: actor, subject: subject, action: :write)
  end

  # note: organization packages is a permission that can be granted but it's a special case
  test "doesn't grant organization permissions" do
    org = create :organization
    repo = create :repository, :minimal, owner: org

    integration = create(:integration, default_permissions: { "metadata" => :read, "organization_secrets" => :write })
    parent_installation = make_integration_installation(integration: integration, target: org, repository: repo)

    result = ScopedIntegrationInstallation::Creators::Actions.perform(parent_installation, {
      "repositories" => [
        { "id" => repo.id, "permissions" => { "metadata" => "read", "organization_secrets" => "write" } },
      ],
    }, entry_point: :test_case)

    assert_predicate result, :success?
    installation = result.installation

    refute_actor_and_subject_granted_in_permissions_table(
      actor: installation,
      subject: org.resources.organization_secrets,
      action: :write,
    )
  end

  context "packages" do
    test "grants organization_packages by default for internal apps with the manage_packages_permissions capability" do
      integration = create_internal_app_with_capabilities(
        permissions: { "contents" => :write, "metadata" => :read, "packages" => :write, "pull_requests" => :write },
        capabilities: { manage_packages_permissions: true },
        )

      parent_installation = make_integration_installation(integration: integration, target: @user)
      refute parent_installation.permissions.key?("organization_packages")

      result = ScopedIntegrationInstallation::Creators::Actions.perform(parent_installation, {
        "repositories" => [
          {
            "id" => @repository.id,
            "permissions" => { "metadata" => "read", "packages" => "write" },
            "pull_requests" => [
              { "number" => @pull.number, "permissions" => { "sarifs" => "write" } }
            ]
          },
        ],
      }, entry_point: :test_case)

      assert_predicate result, :success?
      assert scoped_installation = result.installation

      subject = IntegrationInstallation::AbilityCollection.new(parent: @user, name: "organization_packages", ability_type_prefix: "Organization")
      assert_actor_and_subject_granted_in_permissions_table(actor: scoped_installation, subject: subject, action: :write)
    end

    test "grants organization_packages with read-only scope when requested" do
      integration = create_internal_app_with_capabilities(
        permissions: { "contents" => :write, "metadata" => :read, "packages" => :write, "pull_requests" => :write },
        capabilities: { manage_packages_permissions: true },
        )

      parent_installation = make_integration_installation(integration: integration, target: @user)
      refute parent_installation.permissions.key?("organization_packages")

      result = ScopedIntegrationInstallation::Creators::Actions.perform(parent_installation, {
        "repositories" => [
          {
            "id" => @repository.id,
            "permissions" => { "metadata" => "read", "packages" => "read" },
            "pull_requests" => [
              { "number" => @pull.number, "permissions" => { "sarifs" => "write" } }
            ]
          },
        ],
      }, entry_point: :test_case)

      assert_predicate result, :success?
      assert scoped_installation = result.installation

      subject = IntegrationInstallation::AbilityCollection.new(parent: @user, name: "organization_packages", ability_type_prefix: "Organization")
      assert_actor_and_subject_granted_in_permissions_table(actor: scoped_installation, subject: subject, action: :read)
    end

    test "does not grant organization_packages when no packages permission is requested" do
      integration = create_internal_app_with_capabilities(
        permissions: { "contents" => :write, "metadata" => :read, "pull_requests" => :write },
        capabilities: { manage_packages_permissions: true },
        )

      parent_installation = make_integration_installation(integration: integration, target: @user)
      refute parent_installation.permissions.key?("organization_packages")

      result = ScopedIntegrationInstallation::Creators::Actions.perform(parent_installation, {
        "repositories" => [
          {
            "id" => @repository.id,
            "permissions" => { "metadata" => "read" },
            "pull_requests" => [
              { "number" => @pull.number, "permissions" => { "sarifs" => "write" } }
            ]
          },
        ],
      }, entry_point: :test_case)

      assert_predicate result, :success?
      assert scoped_installation = result.installation

      subject = IntegrationInstallation::AbilityCollection.new(parent: @user, name: "organization_packages", ability_type_prefix: "Organization")
      refute_actor_and_subject_granted_in_permissions_table(actor: scoped_installation, subject: subject, action: :write)
    end
  end

  context ".perform_with_cache" do
    test "uses the cached installation if one is available" do
      with_cache_enabled do
        result = ScopedIntegrationInstallation::Creators::Actions.perform_with_cache(@parent_installation, {
          "repositories" => [
            { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
          ],
        }, entry_point: :test_case)

        assert_predicate result, :success?
        installation_id = result.installation.id

        assert_no_difference "ScopedIntegrationInstallation.count" do
          result = ScopedIntegrationInstallation::Creators::Actions.perform_with_cache(@parent_installation, {
            "repositories" => [
              { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
            ],
          }, entry_point: :test_case)

          assert_predicate result, :success?
          assert_predicate result, :found_cached?
        end

        assert_equal installation_id, result.installation.id
      end
    end

    test "does not use the cache if the installation is expired" do
      with_cache_enabled do
        result = ScopedIntegrationInstallation::Creators::Actions.perform_with_cache(@parent_installation, {
          "repositories" => [
            { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
          ],
        }, entry_point: :test_case)
        assert_predicate result, :success?

        installation = result.installation
        installation_id = installation.id
        installation.update_attribute(:expires_at, 2.days.ago)
        assert_predicate installation.reload, :expired?

        assert_difference "ScopedIntegrationInstallation.count", 1 do
          result = ScopedIntegrationInstallation::Creators::Actions.perform_with_cache(@parent_installation, {
            "repositories" => [
              { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
            ],
          }, entry_point: :test_case)
          assert_predicate result, :success?
          refute_predicate result, :found_cached?
        end

        refute_equal installation_id, result.installation.id
      end
    end

    test "asynchronously bumps the installation (and permissions) expiration" do
      with_cache_enabled do
        result = ScopedIntegrationInstallation::Creators::Actions.perform_with_cache(@parent_installation, {
          "repositories" => [
            { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
          ],
        }, entry_point: :test_case)
        assert_predicate result, :success?

        installation = result.installation
        installation_id = installation.id
        installation.update_attribute(:expires_at, 2.hours.from_now)
        refute_predicate installation.reload, :expired?

        Timecop.freeze do
          expected_job = ScopedIntegrationInstallableExpirationExtensionJob
          assert_performed_with(job: expected_job, args: [installation, 25.hours.from_now, { entry_point: :test_case }]) do
            assert_no_difference "ScopedIntegrationInstallation.count" do
              result = ScopedIntegrationInstallation::Creators::Actions.perform_with_cache(@parent_installation, {
                "repositories" => [
                  { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
                ],
              }, entry_point: :test_case)
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
        result = ScopedIntegrationInstallation::Creators::Actions.perform_with_cache(@parent_installation, {
          "repositories" => [
            { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
          ],
        }, entry_point: :test_case)
        assert_predicate result, :success?

        installation = result.installation
        installation_id = installation.id

        Timecop.freeze do
          installation.update_attribute(:expires_at, 6.hours.from_now)
          refute_predicate installation.reload, :expired?
          assert_no_performed_jobs(only: ScopedIntegrationInstallableExpirationExtensionJob) do
            assert_no_difference "ScopedIntegrationInstallation.count" do
              result = ScopedIntegrationInstallation::Creators::Actions.perform_with_cache(@parent_installation, {
                "repositories" => [
                  { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
                ],
              }, entry_point: :test_case)
              assert_predicate result, :success?
            end
          end

          assert_equal 6.hours.from_now.to_i, installation.reload.expires_at.to_i, "Expected expires_at not to be bumped"
          assert_equal installation_id, result.installation.id
        end
      end
    end

    test "creates a new record if the cached record was destroyed" do
      with_cache_enabled do
        result = ScopedIntegrationInstallation::Creators::Actions.perform_with_cache(@parent_installation, {
          "repositories" => [
            { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
          ],
        }, entry_point: :test_case)

        assert_predicate result, :success?
        cached_installation_id = result.installation.id

        result.installation.destroy

        assert_difference "ScopedIntegrationInstallation.count", 1 do
          result = ScopedIntegrationInstallation::Creators::Actions.perform_with_cache(@parent_installation, {
            "repositories" => [
              { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
            ],
          }, entry_point: :test_case)

          assert_predicate result, :success?
        end

        refute_equal cached_installation_id, result.installation.id
      end
    end

    test "does not use the cached scoped installation if repositories requested are no longer available" do
      with_cache_enabled do
        @parent_installation.edit(repositories: [@repository, @other_repository], editor: @user, entry_point: :test_case)
        @parent_installation.reload

        result = ScopedIntegrationInstallation::Creators::Actions.perform_with_cache(@parent_installation, {
          "repositories" => [
            { "id" => @repository.id,           "permissions" => { "metadata" => "read" } },
            { "name" => @other_repository.name, "permissions" => { "metadata" => "read" } }
          ],
        }, entry_point: :test_case)

        assert_predicate result, :success?

        @parent_installation.edit(repositories: [@repository], editor: @user, entry_point: :test_case)
        @parent_installation.reload

        assert_no_difference "ScopedIntegrationInstallation.count" do
          result = ScopedIntegrationInstallation::Creators::Actions.perform_with_cache(@parent_installation, {
            "repositories" => [
              { "id" => @repository.id,           "permissions" => { "metadata" => "read" } },
              { "name" => @other_repository.name, "permissions" => { "metadata" => "read" } }
            ],
          }, entry_point: :test_case)

          assert_predicate result, :failed?
        end
      end
    end

    test "does not use cached installation if the permissions requested are no longer available" do
      with_cache_enabled do
        result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
          "repositories" => [
            {
              "id" => @repository.id,
              "permissions" => { "metadata" => "read" },
              "pull_requests" => [
                { "number" => @pull.number, "permissions" => { "sarifs" => "write" } }
              ]
            },
          ],
        }, entry_point: :test_case)

        assert_predicate result, :success?

        integration = @parent_installation.integration
        integration.update(default_permissions: { "metadata" => :read }); integration.reload

        latest_version = integration.latest_version
        @parent_installation.update_version(editor: @user, version: latest_version, entry_point: :test_case)

        assert_no_difference "ScopedIntegrationInstallation.count" do
          result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
            "repositories" => [
              {
                "id" => @repository.id,
                "permissions" => { "metadata" => "read" },
                "pull_requests" => [
                  { "number" => @pull.number, "permissions" => { "sarifs" => "write" } }
                ]
              },
            ],
          }, entry_point: :test_case)

          assert_predicate result, :failed?
        end
      end
    end
  end

  context "instrumentation" do
    test "on creation" do
      events = subscribe "scoped_integration_installation.create"

      created_at = 2.hours.ago.beginning_of_hour
      result = Timecop.freeze(created_at) do
        ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
          "repositories" => [
            { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
          ],
        }, entry_point: :test_case)
      end

      assert_predicate result, :success?

      scoped_installation = result.installation
      integration = @parent_installation.integration

      expected_payload = {
        scoped_integration_installation:    scoped_installation.name,
        scoped_integration_installation_id: scoped_installation.id,
        parent_integration_installation_id: @parent_installation.id,
        integration:                        integration.name,
        integration_id:                     integration.id,
        repository_selection:               "selected",
        repository_ids:                     [@repository.id],
        user:                               @user.to_s,
        user_id:                            @user.id,
        permissions:                        { "metadata" => :read },
        created_at:                         created_at
      }

      assert event = events.pop, "expected an instrument creation event"
      assert_equal "scoped_integration_installation.create", event.name
      assert_same_hash expected_payload, event.payload
    end

    test "does instrument proper stats" do
      result = ScopedIntegrationInstallation::Creators::Actions.perform(@parent_installation, {
        "repositories" => [
          { "id" => @repository.id, "permissions" => { "metadata" => "read" } },
        ]
      }, entry_point: :test_case)

      assert_predicate result, :success?

      expected_tags = ["result:success", "version:2"]
      assert_dogstats_increment("scoped_integration_installation.create", tags: expected_tags)
    end
  end
end
