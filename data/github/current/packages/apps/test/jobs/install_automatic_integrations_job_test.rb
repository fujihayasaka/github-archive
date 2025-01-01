# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/spokesd"

class InstallAutomaticIntegrationsJobTest < GitHub::TestCase
  include PushTestHelper
  include JobTestHelper

  fixtures do
    @app = create(
      :integration,
      name: "Don't worry, be Appy",
      default_permissions: { "contents" => :read },
    )
    @file_added_trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/README")

    @repo = create(:repository, from_example: :initial_commit_ruby_library)
    Spokesd.enable_spokesd
    @push = push_changes(repository: @repo, changes: { path: ".github/README", content: "irrelevant" })
    assert_equal 1, @push.changed_files.count
    @push.freeze
  end

  setup do
    Spokesd.enable_spokesd
    @job = InstallAutomaticIntegrationsJob
    # TODO: Remove me when default_to_write_connection? is removed from the job.
    # We're doing awful things with class variables, so this is necessary to
    # make sure tests don't interfere with each other.
    @job.instance_variable_set(:@default_to_write_connection, nil)
  end

  context "install on all repositories" do
    test "installs automatic app" do
      owner = @repo.owner
      second_repo = create(:repository, :minimal, owner: owner)
      refute_predicate @app.installations, :any?

      target_id = owner.id
      integration_id = @app.id
      trigger_id = @file_added_trigger.id

      result = @job.perform_now(target_id, integration_id, trigger_id, [], { entry_point: :test_case })

      assert_predicate result, :success?
      assert_equal [], result.repositories

      installations = @app.installations
      assert_predicate installations, :any?

      assert installation = installations.with_repository(@repo).first
      assert_equal installation, result.installation

      assert_equal trigger_id, installation.integration_install_trigger_id
      assert installation.installed_on_all_repositories?
      assert_same_elements [@repo, second_repo], installation.repositories
    end

    test "halts installations on before_installation callbacks that return false" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @job.any_instance.expects(:should_install?).returns(false)
      result = @job.perform_now(@repo.owner.id, @app.id, @file_added_trigger.id, [], { entry_point: :test_case })

      assert_predicate result, :failed?
      assert_equal :canceled, result.reason

      refute_predicate @app.installations, :any?

      stats = GitHub.dogstats.increments("jobs.install_automatic_integrations.canceled")
      assert_equal 1, stats.count
    end

    test "does not install automatic app if automatic app has been deactivated" do
      IntegrationInstallTrigger.deactivate(integration: @app, install_type: :file_added)

      target_id = @push.repository.owner.id
      integration_id = @app.id
      trigger_id = @file_added_trigger.id

      result = @job.perform_now(target_id, integration_id, trigger_id, [], { entry_point: :test_case })

      assert_predicate result, :failed?
      assert_equal :deactivated, result.reason

      installations = @app.installations
      refute_predicate installations, :any?
    end

    test "does not attempt install if app has already been installed" do
      admin = create(:paid_user)
      integration = create(:integration, default_permissions: { "metadata" => :read })
      org = create(:organization, admin: admin)
      _repo  = create(:private_repository, :minimal, owner: org)

      _installation = make_integration_installation(integration: integration, target: org)
      assert_predicate integration.installations, :any?

      Integration.any_instance.expects(:install_on).never
      result = @job.perform_now(org.id, integration.id, @file_added_trigger.id, { entry_point: :test_case })

      assert_predicate result, :success?
      assert_predicate result, :already_installed?
    end

    test "does not install on invalid installations updates and returns a result when running in the foreground" do
      user = create(:user)
      repo = create(:repository, owner: user)
      make_integration_installation(integration: @app, repository: repo)

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      GitHub.stubs(:foreground?).returns(true)
      # attempts to append a non-owned repo to an existing installation
      result = @job.perform_now(user.id, @app.id, @file_added_trigger.id, [@repo.id], { entry_point: :test_case })

      assert_predicate result, :failed?
      assert_equal :failed_to_update, result.reason

      refute_predicate @app.installations.with_repository(@repo), :any?
      stats = GitHub.dogstats.increments("jobs.install_automatic_integrations.failed_to_update")
      assert_equal 1, stats.count
    end

    test "does not install on invalid installations updates and discards when AppUpdateError raises in the background" do
      user = create(:user)
      repo = create(:repository, owner: user)
      make_integration_installation(integration: @app, repository: repo)

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      GitHub.stubs(:foreground?).returns(false)

      # If discard isn't working, this test will cause an error
      perform_enqueued_jobs(only: [@job]) do
        # attempts to append a non-owned repo to an existing installation
        @job.perform_later(user.id, @app.id, @file_added_trigger.id, [@repo.id], { entry_point: :test_case })
      end

      refute_predicate @app.installations.with_repository(@repo), :any?
      stats = GitHub.dogstats.increments("jobs.install_automatic_integrations.failed_to_update")
      assert_equal 1, stats.count
    end

    test "discards if the installation wasn't successful" do
      refute_predicate @app.installations, :any?

      failed_result = IntegrationInstallation::Creator::Result.failed("This failed to happen")
      IntegrationInstallation::Creator.any_instance.stubs(:perform).returns(failed_result)

      # If discard isn't working, this test will cause an error
      perform_enqueued_jobs(only: [@job]) do
        @job.perform_later(@push.repository.owner_id, @app.id, @file_added_trigger.id, [], { entry_point: :test_case })
      end

      assert_predicate @app.installations, :none?
    end
  end

  context "installs on selected repositories" do
    test "installs automatic app on only selected repository" do
      refute_predicate @app.installations, :any?

      target_id = @push.repository.owner.id
      integration_id = @app.id
      trigger_id = @file_added_trigger.id

      result = @job.perform_now(target_id, integration_id, trigger_id, [@repo.id], { entry_point: :test_case })
      assert_predicate result, :success?

      installations = @app.installations
      assert_predicate installations, :any?

      assert installation = installations.with_repository(@repo).first
      assert_equal installation, result.installation

      assert_equal trigger_id, installation.integration_install_trigger_id
      refute installation.installed_on_all_repositories?
      assert_same_elements [@repo], installation.repositories
      assert_same_elements [@repo], result.repositories
    end

    test "does not install automatic app if automatic app has been deactivated" do
      IntegrationInstallTrigger.deactivate(integration: @app, install_type: :file_added)

      target_id = @push.repository.owner.id
      integration_id = @app.id
      trigger_id = @file_added_trigger.id

      result = @job.perform_now(target_id, integration_id, trigger_id, [@repo.id], { entry_point: :test_case })
      assert_predicate result, :failed?
      assert_equal :deactivated, result.reason

      installations = @app.installations
      refute_predicate installations, :any?
    end

    test "does not attempt install for specific repo if app has already been installed on all" do
      admin = create(:paid_user)
      integration = create(:integration, default_permissions: { "metadata" => :read })
      org   = create(:organization, admin: admin)
      repo  = create(:private_repository, owner: org)

      _installation = make_integration_installation(integration: integration, target: org)
      assert_predicate integration.installations, :any?

      Integration.any_instance.expects(:install_on).never
      result = @job.perform_now(org.id, integration.id, @file_added_trigger.id, [repo.id], { entry_point: :test_case })
      assert_predicate result, :success?
      assert_predicate result, :already_installed?
    end

    test "still works if app has already been installed on repo" do
      admin = create(:paid_user)
      integration = create(:integration, default_permissions: { "metadata" => :read })
      org   = create(:organization, admin: admin)
      repo  = create(:private_repository, owner: org)

      _installation = make_integration_installation(integration: integration, repository: repo)
      assert_predicate integration.installations, :any?

      result = @job.perform_now(org.id, integration.id, @file_added_trigger.id, [repo.id], { entry_point: :test_case })
      assert_predicate result, :success?
      assert_predicate result, :already_installed?

      assert_equal 1, integration.installations.count
      assert_equal repo, integration.installations.first.repositories.first
    end

    test "updates an existing installation if the app has not already been installed on repo" do
      repo = create(:repository)
      admin = create(:paid_user)
      integration = create(:integration, default_permissions: { "metadata" => :read })
      org   = create(:organization, admin: admin)
      repo  = create(:private_repository, owner: org)
      repo2 = create(:private_repository, owner: org)

      make_integration_installation(integration: integration, repository: repo)
      assert_predicate integration.installations, :any?

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      result = @job.perform_now(org.id, integration.id, @file_added_trigger.id, [repo2.id], { entry_point: :test_case })
      assert_predicate result, :success?

      assert_equal 1, integration.installations.count

      installation = integration.installations.first
      assert_equal installation, result.installation

      assert_equal 2, installation.repositories.count
      assert_includes installation.repositories, repo
      assert_includes installation.repositories, repo2
      assert_equal [repo2], result.repositories

      stats = GitHub.dogstats.increments(
        "jobs.install_automatic_integrations.repositories_added",
        tags: ["installation_type:selected", "installation_queue:install_automatic_integrations",
               "integration:#{integration.slug}", "owner:#{integration.owner.login}"],
      )
      assert_equal 1, stats.count
    end

    test "masks the actor when adding a repo to an existing installation" do
      integration = create(:integration, default_permissions: { "metadata" => :read })

      admin = create(:paid_user)
      org = create(:organization, admin: admin)

      repo  = create(:private_repository, owner: org)
      repo2 = create(:private_repository, owner: org)

      installation = make_integration_installation(integration: integration, repository: repo)
      events = subscribe "integration_installation.repositories_added"

      result = @job.perform_now(org.id, integration.id, @file_added_trigger.id, [repo2.id], { entry_point: :test_case })
      assert_predicate result, :success?

      expected_payload = {
        app:                        integration.name,
        org:                        org.login,
        application_client_id:      integration.key,
        name:                       integration.name,
        slug:                       integration.slug,
        actor:                      integration.bot.display_login,
        app_id:                     integration.id,
        org_id:                     org.id,
        actor_id:                   integration.bot.id,
        integration:                integration.name,
        requester_id:               nil,
        integration_id:             integration.id,
        installation_id:            installation.id,
        repositories_added:         [repo2.id],
        repositories_added_names:   [repo2.full_name],
        added_automatically:        true,
        repository_selection:       "selected",
      }

      assert event = events.pop, "expected an instrument repositories added event"
      assert_equal "integration_installation.repositories_added", event.name
      assert_same_hash expected_payload, event.payload
    end

    test "gracefully exits if repo deleted while updating an existing installation" do
      repo = create(:repository)
      admin = create(:paid_user)
      integration = create(:integration, default_permissions: { "metadata" => :read })
      org   = create(:organization, admin: admin)
      repo  = create(:private_repository, owner: org)
      repo2 = create(:private_repository, owner: org)
      repo2.destroy

      make_integration_installation(integration: integration, repository: repo)
      assert_predicate integration.installations, :any?

      result = @job.perform_now(org.id, integration.id, @file_added_trigger.id, [repo2.id], { entry_point: :test_case })
      assert_predicate result, :success?
    end

    test "does not trigger after_integration_installation if app is already installed on repo" do
      repo = create(:repository)
      admin = create(:paid_user)
      integration = create(:integration, default_permissions: { "metadata" => :read })
      org   = create(:organization, admin: admin)
      repo  = create(:private_repository, owner: org)

      make_integration_installation(integration: integration, repository: repo)
      assert_predicate integration.installations, :any?

      AutomaticAppInstallation::Handlers::FileAdded.expects(:after_integration_installed).never

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      result = @job.perform_now(org.id, integration.id, @file_added_trigger.id, [repo.id], { entry_point: :test_case })
      assert_predicate result, :success?
      assert_predicate result, :already_installed?

      stats = GitHub.dogstats.increments("jobs.install_automatic_integrations.already_installed")
      assert_equal 1, stats.count
    end

    test "does not trigger integration_already_installed if a new installation was created" do
      repo = create(:repository)
      admin = create(:paid_user)
      integration = create(:integration, default_permissions: { "metadata" => :read })
      org   = create(:organization, admin: admin)
      repo  = create(:private_repository, owner: org)

      AutomaticAppInstallation::Handlers::FileAdded.expects(:integration_already_installed).never

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      result = @job.perform_now(org.id, integration.id, @file_added_trigger.id, [repo.id], { entry_point: :test_case })
      assert_predicate result, :success?
      refute_predicate result, :already_installed?

      stats = GitHub.dogstats.increments("jobs.install_automatic_integrations.installed")
      assert_equal 1, stats.count
    end

    test "triggers integration_already_installed if the app is already installed on repo" do
      repo = create(:repository)
      admin = create(:paid_user)
      integration = create(:integration, default_permissions: { "metadata" => :read })
      org   = create(:organization, admin: admin)
      repo  = create(:private_repository, owner: org)

      make_integration_installation(integration: integration, repository: repo)
      assert_predicate integration.installations, :any?

      AutomaticAppInstallation::Handlers::FileAdded.expects(:integration_already_installed).once

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      result = @job.perform_now(org.id, integration.id, @file_added_trigger.id, [repo.id], { entry_point: :test_case })
      assert_predicate result, :success?
      assert_predicate result, :already_installed?

      stats = GitHub.dogstats.increments("jobs.install_automatic_integrations.already_installed")
      assert_equal 1, stats.count
    end

    test "does not install on invalid installations and returns a result when running in the foreground" do
      refute_predicate @app.installations, :any?

      GitHub.stubs(:foreground?).returns(true)

      failed_result = IntegrationInstallation::Creator::Result.failed("This failed to happen")
      IntegrationInstallation::Creator.any_instance.stubs(:perform).returns(failed_result)

      args = [
        @push.repository.owner.id,
        @app.id,
        @file_added_trigger.id,
        [@repo.id],
      ]

      result = @job.perform_now(*args)
      assert_predicate result, :failed?
      assert_equal :failed_to_create, result.reason
      assert_predicate result.exception, :present?
      assert_equal "This failed to happen", result.exception.message
    end

    test "does not install on invalid installations and discards when AppInstallError is raised when running in the background" do
      refute_predicate @app.installations, :any?

      GitHub.stubs(:foreground?).returns(false)

      failed_result = IntegrationInstallation::Creator::Result.failed("This failed to happen")
      IntegrationInstallation::Creator.any_instance.stubs(:perform).returns(failed_result)

      # If discard isn't working, this test will cause an error
      perform_enqueued_jobs(only: [@job]) do
        @job.perform_later(@push.repository.owner_id, @app.id, @file_added_trigger.id, [@repo.id], { entry_point: :test_case })
      end

      refute_predicate @app.installations, :any?
    end

    test "discards if the installation wasn't successful when running in the background" do
      refute_predicate @app.installations, :any?

      GitHub.stubs(:foreground?).returns(false)

      failed_result = IntegrationInstallation::Creator::Result.failed("This failed to happen")
      IntegrationInstallation::Creator.any_instance.stubs(:perform).returns(failed_result)

      # If discard isn't working, this test will cause an error
      perform_enqueued_jobs(only: [@job]) do
        @job.perform_later(@push.repository.owner_id, @app.id, @file_added_trigger.id, [@repo.id], { entry_point: :test_case })
      end

      refute_predicate @app.installations, :any?
    end
  end

  context "instrumentation" do
    test "records information about the installed App" do
      admin = create(:paid_user)
      app_owner = create(:user, login: "dat-app-owner")
      integration = create(:integration, name: "Some Great App", owner: app_owner, default_permissions: { "metadata" => :read })
      org   = create(:organization, admin: admin)
      repo  = create(:private_repository, owner: org)

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      @job.perform_now(org.id, integration.id, @file_added_trigger.id, [repo.id], { entry_point: :test_case })

      stats = GitHub.dogstats.increments(
        "jobs.install_automatic_integrations.installed",
        tags: ["installation_queue:install_automatic_integrations", "integration:some-great-app", "owner:dat-app-owner"],
      )
      assert_equal 1, stats.count
    end
  end

  context "handling errors" do
    test "gracefully handles spammy users", skip_enterprise: true do
      refute_predicate @app.installations, :any?

      spammy_user = create(:spammy_user, login: "spammy")

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      result = @job.perform_now(spammy_user.id, @app.id, @file_added_trigger.id, [], { entry_point: :test_case })
      assert_predicate result, :failed?
      assert_equal :failed_to_create, result.reason

      installations = @app.installations
      refute_predicate installations, :any?

      stats = GitHub.dogstats.increments(
        "jobs.install_automatic_integrations.failed_to_create",
        tags: ["installation_queue:install_automatic_integrations", "integration:#{@app.slug}",
               "owner:#{@app.owner.login}", "reason:spammy_target"],
      )
      assert_equal 1, stats.count
    end

    test "gracefully handles spammy actors (org admins)", skip_enterprise: true do
      refute_predicate @app.installations, :any?

      spammy_user = create(:spammy_user, login: "spammy")
      org = create(:organization, admin: spammy_user)

      @job.perform_now(org.id, @app.id, @file_added_trigger.id, { entry_point: :test_case })

      installations = @app.installations
      refute_predicate installations, :any?
    end

    test "gracefully handles deleted users" do
      refute_predicate @app.installations, :any?

      user = create :user
      target_id = user.id
      user.destroy

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      result = @job.perform_now(target_id, @app.id, @file_added_trigger.id, { entry_point: :test_case })
      assert_predicate result, :failed?
      assert_equal :deleted_target, result.reason

      installations = @app.installations
      refute_predicate installations, :any?

      stats = GitHub.dogstats.increments(
        "jobs.install_automatic_integrations.deleted_target",
        tags: ["installation_queue:install_automatic_integrations",
               "integration:#{@app.slug}",
               "owner:#{@app.owner.login}"],
      )
      assert_equal 1, stats.count
    end

    test "retry conditions" do
      assert_retry_on_dirty_exit job: InstallAutomaticIntegrationsJob, args: [@push.repository.owner_id, @app.id, @file_added_trigger.id, [@repo.id]]
    end
  end
end
