# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"
require "test_helpers/spokesd"

class HydroAppsOnPushJobTest < GitHub::TestCase
  include HookIntegrationTestHelper
  include PushTestHelper
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @repo = create(:repository, from_example: :simple)

    @initial_commit_repo = create(:repository, from_example: :workflow)

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    @actions_app = create(:launch_integration)
    @dependabot_app = create(:dependabot_integration)
  end

  context "enqueues app install job" do
    test "initial commit" do
      Spokesd.enable_spokesd

      app = create(:integration, default_permissions: { "contents" => :read })
      create(:integration_install_trigger, integration: app, install_type: :file_added, path: "\\A\\.github/main\\.workflow")

      assert_enqueued_jobs 1, only: [InstallAutomaticIntegrationsJob] do
        perform_push_hydro_job(
          repository: @initial_commit_repo,
          job_class: HydroAppsOnPushJob,
        )
      end
    end

    test "subsequent commit" do
      Spokesd.enable_spokesd

      app = create(:integration, default_permissions: { "contents" => :read })
      create(:integration_install_trigger, integration: app, install_type: :file_added, path: "\\A\\.github/README")

      assert_enqueued_jobs 1, only: [InstallAutomaticIntegrationsJob] do
        perform_push_hydro_job(
          repository: @repo,
          job_class: HydroAppsOnPushJob,
          changes: { path: ".github/README", content: "irrelevant" }
        )
      end
    end
  end

  test "enqueues hook job" do
    create(:hook, name: "web", events: %w(push), installation_target: @repo)

    assert_enqueued_jobs 1, only: [PostPushEventToHookshotJob] do
      perform_push_hydro_job(
        repository: @repo,
        job_class: HydroAppsOnPushJob,
        changes: { path: "README", content: "irrelevant" }
      )
    end
  end

  test "handles nil pusher" do
    create(:hook, name: "web", events: %w(push), installation_target: @repo)

    message = {
      repository_id: @repo.id,
      ref_updates: [{ ref: "refs/heads/foo", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }],
      pushed_at: Time.now,
      pusher: nil,
      run_hydro_job: true,
    }

    assert_enqueued_with(job: PostPushEventToHookshotJob, args: ->(job_args) { assert job_args[0][0].dig(:payload, :sender, :id) == User.ghost.id }) do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")
    end
  end

  test "skips wiki push" do
    create(:hook, name: "web", events: %w(push), installation_target: @repo)

    message = {
      repository_id: @repo.id,
      ref_updates: [{ ref: "refs/heads/master", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }],
      pushed_at: Time.now,
      pusher: nil,
      run_hydro_job: true,
      path: @repo.unsullied_wiki.shard_path,
    }

    AutomaticAppInstallation.expects(:trigger).never

    assert_enqueued_jobs 0, only: [PostPushEventToHookshotJob] do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")
    end
  end

  test "retries" do
    Repository.any_instance.stubs(:network).raises(Repositories::PushHydroMessageJob::RepositoryNotFound)
    HydroMessageJob.any_instance.expects(:retry).once

    message = {
      repository_id: @repo.id,
      ref_updates: [{ ref: "refs/heads/foo", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }],
      pushed_at: Time.now,
      pusher: nil,
      run_hydro_job: true,
    }

    assert_nothing_raised do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")
    end
  end

  test "skips webhook delivery on retry after failure installing apps" do
    HydroAppsOnPushJob.any_instance.stubs(:install_apps).raises(SpokesAPI::ResourceExhausted).then.returns(nil)
    HydroAppsOnPushJob.any_instance.expects(:deliver_webhooks).once

    message = {
      repository_id: @repo.id,
      ref_updates: [{ ref: "refs/heads/foo", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }],
      pushed_at: Time.now,
      pusher: nil,
      run_hydro_job: true,
    }

    assert_nothing_raised do
      perform_enqueued_hydro_jobs(only: [HydroAppsOnPushJob]) do
        perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")
      end
    end
  end

  test "noops for large push" do
    message = {
      repository_id: @repo.id,
      ref_updates: [{ ref: "refs/heads/foo", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }, { ref: "refs/heads/bar", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }],
      pushed_at: 1.minute.ago,
      pusher: @repo.owner_login,
      total_branch_count: 2,
      total_ref_count: 2,
      request_context: { "request_id" => "123" },
    }

    HydroAppsOnPushJob.any_instance.expects(:pushes).never
    HydroAppsOnPushJob.any_instance.expects(:deliver_webhooks).never
    HydroAppsOnPushJob.any_instance.expects(:install_apps).never

    expected_log = {
      "Body" => "Skipping HydroAppsOnPushJob for large push.",
      :"ref_updates.count" => 2,
      :"code.namespace" => "HydroAppsOnPushJob",
      :"gh.request_id" => "123",
      :"gh.repo.id" => @repo.id,
    }

    Pushes::CommitsHelper.stub_const(:LARGE_BRANCH_COUNT_THRESHOLD, 1) do
      assert_logged(**expected_log) do
        perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")
      end
    end

    assert_dogstats_increment(1, "hydro_apps_on_push_job.large_push_skip")
  end

  context "app installation" do
    test "installs when actions is needed, skips otherwise" do
      GitHub.stubs(:launch_github_app).returns(@actions_app)
      create(:integration_install_trigger, integration: @actions_app, install_type: :file_added)

      message = {
        repository_id: @repo.id,
        ref_updates: [{ ref: "refs/heads/master", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }, { ref: "refs/heads/foo", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }, { ref: "refs/heads/bar", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }],
        pushed_at: Time.now,
        pusher: @repo.owner_login,
      }

      # should trigger app installation for each ref update since the app is not installed
      AutomaticAppInstallation.expects(:trigger).times(message[:ref_updates].count)
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")

      # shouldn't trigger app installation once the app is installed
      make_integration_installation(integration: @actions_app, repository: @repo)
      AutomaticAppInstallation.expects(:trigger).never
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")
    end

    test "installs when actions-lab is needed for staff repo, skips otherwise" do
      GitHub.stubs(:launch_lab_github_app).returns(@actions_app)
      GitHub.stubs(:launch_github_app).returns(nil)
      create(:integration_install_trigger, integration: @actions_app, install_type: :file_added)

      repo = create :repository, owner: Organization.find_by_login("github")

      message = {
        repository_id: repo.id,
        ref_updates: [{ ref: "refs/heads/master", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }, { ref: "refs/heads/foo", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }, { ref: "refs/heads/bar", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }],
        pushed_at: Time.now,
        pusher: repo.owner_login,
      }

      # doesn't install for non allowed
      GitHub.flipper[:launch_lab].disable
      AutomaticAppInstallation.expects(:trigger).never
      perform_hydro_message_job(message.merge(repository_id: repo.id), schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")

      # installs for allowed repo
      GitHub.flipper[:launch_lab].enable(repo.owner)
      AutomaticAppInstallation.expects(:trigger).times(message[:ref_updates].count)
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")

      # skips if installed
      make_integration_installation(integration: @actions_app, repository: repo)
      AutomaticAppInstallation.expects(:trigger).never
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")
    end unless GitHub.enterprise?

    test "installs when default branch is updated and dependabot is needed, skips otherwise" do
      GitHub.stubs(:dependabot_github_app).returns(@dependabot_app)
      create(:integration_install_trigger, integration: @dependabot_app, install_type: :file_added)

      message = {
        repository_id: @repo.id,
        ref_updates: [{ ref: "refs/heads/foo", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }, { ref: "refs/heads/bar", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }],
        pushed_at: Time.now,
        pusher: @repo.owner_login,
      }

      # skips if default branch is not updated
      AutomaticAppInstallation.expects(:trigger).never
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")

      # installs when default branch is updated
      AutomaticAppInstallation.expects(:trigger).once
      ref_updates = message[:ref_updates] + [{ ref: "refs/heads/master", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }]
      perform_hydro_message_job(message.merge(ref_updates:), schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")

      # skips if already installed
      make_integration_installation(integration: @dependabot_app, repository: @repo)
      AutomaticAppInstallation.expects(:trigger).never
      perform_hydro_message_job(message.merge(ref_updates:), schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")
    end

    test "installs for arbitrary app with file_added trigger" do
      app = create(:integration, default_permissions: { "contents" => :read })
      create(:integration_install_trigger, integration: app, install_type: :file_added)
      message = {
        repository_id: @repo.id,
        ref_updates: [{ ref: "refs/heads/foo", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }, { ref: "refs/heads/bar", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }],
        pushed_at: Time.now,
        pusher: @repo.owner_login,
      }

      AutomaticAppInstallation.expects(:trigger).times(message[:ref_updates].count)
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")
    end

    test "counts installations correctly for the pushed repository" do
      create(:integration_install_trigger, integration: @actions_app, install_type: :file_added)
      other_repo = create :repository, owner: @repo.owner
      make_integration_installation(integration: @actions_app, repository: other_repo)

      message = {
        repository_id: @repo.id,
        ref_updates: [{ ref: "refs/heads/foo", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }],
        pushed_at: Time.now,
        pusher: @repo.owner_login,
      }

      AutomaticAppInstallation.expects(:trigger).never
      perform_hydro_message_job(message.merge(repository_id: other_repo.id), schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")

      # installation on the other repo should not prevent installation being triggered for this repo.
      AutomaticAppInstallation.expects(:trigger).once
      perform_hydro_message_job(message.merge(repository_id: @repo.id), schema: "github.repositories.v1.Pushed", queue: "hydro_apps_on_push")
    end
  end
end
