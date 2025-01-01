# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"
require "test_helpers/aqueduct_test_client"

class AutomaticAppInstallation::Handlers::FileAddedTest < GitHub::TestCase
  fixtures do
    Spokesd.enable_spokesd

    @app = create(:integration, default_permissions: { "contents" => :read })

    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)

    @repo = create(:repository, from_example: :initial_commit_ruby_library)
    @push = push_changes(repository: @repo, changes: { path: ".github/README", content: "irrelevant" })
    assert_equal 1, @push.changed_files.count
    @flowfile_push = push_changes(repository: @repo, changes: { path: ".github/workflows/main.yml", content: "irrelevant" })
    @dependabot_config_push = push_changes(repository: @repo, changes: { path: ".github/dependabot.yml", content: "irrelevant" })
    example_repo_snapshot
  end

  include PushTestHelper

  setup do
    example_repo_restore
    GitHub.stubs(:actions_enabled?).returns(true)

    @push = push_to_ref_update(@push)
    @flowfile_push = push_to_ref_update(@flowfile_push)
    @dependabot_config_push = push_to_ref_update(@dependabot_config_push)
  end

  context "File Added" do
    test "installs integration on configured App" do
      triggers = [
        create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/README"),
      ]

      handler = AutomaticAppInstallation::Handlers::FileAdded.new(
        install_triggers: triggers,
        originator: @push,
        actor: @push.pusher,
      )

      Timecop.freeze do
        assert_enqueued_with job: InstallAutomaticIntegrationsJob, args: [
          @push.repository.owner.id,
          triggers.first.integration.id,
          triggers.first.id,
          Array(@push.repository.id),
          {
            enqueued_timestamp: Time.now.to_i,
            entry_point: :automatic_app_installation_handler_file_added,
            pusher: @push.pusher,
            before: @push.before,
            after: @push.after,
            ref: @push.ref
          },
        ] do
          handler.install_integration
        end
      end
    end

    test "should install when adding an originating file path that matches configured path" do
      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/README")
      assert_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], @push), trigger
    end

    test "should install when renaming an originating file path that matches configured path" do
      push_to_ref_update(push_changes(repository: @repo, changes: { path: "not-the-trigger-file.md", contents: "irrelevant" }))
      push = push_to_ref_update(push_changes(repository: @repo, changes: { path: "not-the-trigger-file.md", new_path: ".github/some-file.md" }))
      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/some-file.md")

      assert_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], push), trigger
    end

    test "should install when an originating file path that matches configured path pattern" do
      push_to_ref_update(push_changes(repository: @repo, changes: { path: "not-the-trigger-file.md", contents: "irrelevant" }))
      push = push_to_ref_update(push_changes(repository: @repo, changes: { path: "not-the-trigger-file.md", new_path: ".github/some-file.md" }))
      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/some(-|_)file.md")
      assert_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], push), trigger

      push = push_to_ref_update(push_changes(repository: @repo, changes: { path: ".github/some-file.md", new_path: ".github/some_file.md" }))
      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/some(-|_)file.md")
      assert_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], push), trigger
    end

    test "should install when an originating file is created path that matches configured path pattern" do
      push = push_to_ref_update(push_changes(repository: @repo, changes: { path: ".github/other-file.md" }))
      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/other(-|_)file.md")
      assert_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], push), trigger
    end

    test "should not install when originating file path does not match configured path" do
      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/other-file")
      refute_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], @push), trigger
    end

    test "should not install when originating file path does not match configured path pattern" do
      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/README\\.(txt|rdoc)")
      refute_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], @push), trigger

      # sanity check our escaping.
      push = push_to_ref_update(push_changes(repository: @repo, changes: { path: ".github/README.rdoc", contents: "irrelevant" }))
      assert_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], push), trigger
    end

    test "should not install when file name changed" do
      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/other-file")
      push = push_to_ref_update(push_changes(repository: @repo, changes: { path: "README.md", new_path: "README" }))

      refute_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], push), trigger
    end

    test "should install on initial push to default (master) branch" do
      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/README")
      assert_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], @push), trigger
    end

    test "limits number of commits processed on large initial push on enterprise", enterprise_only: true do
      push = push_changes(
        repository: @repo,
        changes: [{ path: ".github/MATCH", content: "irrelevant" }, { path: "SOMEPATH", content: "irrelevant" }],
        split_changes_distinct_commits: true
      )
      push.before = GitHub::NULL_OID
      push.push_type = :branch_creation
      push = push_to_ref_update(push)
      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/MATCH")

      match_commit, non_match_commit = push.commits_pushed.last(2)

      # No matched commits since we only process the most recent Pushes::CommitsHelper::LARGE_PUSH_THRESHOLD (2048)
      push.stubs(:commits_pushed).returns([match_commit] + ([non_match_commit] * (Pushes::CommitsHelper::LARGE_PUSH_THRESHOLD)))
      assert_empty AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], push)

      # When the most recent commits contains the match, we trigger install
      push.stubs(:commits_pushed).returns(([non_match_commit] * (Pushes::CommitsHelper::LARGE_PUSH_THRESHOLD)) + [match_commit])
      assert_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], push), trigger
    end

    test "should install on adding a file during the initial push to non-default branch" do
      repo = create(:repository, from_example: :initial_commit_ruby_library)

      user = repo.owner
      repo.heads.create("topic", repo.heads.read("master").target, user)
      push = push_to_ref_update(push_changes(repository: repo, branch_name: "topic", changes: { path: ".github/some-file.md", content: "irrelevant" }))

      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/some-file.md")

      assert_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], push), trigger
    end

    test "should not install on the initial push to a non-default branch where the trigger file exists in the default branch" do
      repo = create(:repository, from_example: :initial_commit_ruby_library)

      user = repo.owner
      repo.heads.create("topic", repo.heads.read("master").target, user)
      push = push_to_ref_update(push_changes(repository: repo, branch_name: "topic", changes: { path: "README.md", content: "irrelevant" }))

      # This repo has a Gemfile in the fixture.
      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/Gemfile")

      refute_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], push), trigger
    end

    test "should install when renaming a file during the initial push to non-default branch" do
      repo = create(:repository, from_example: :initial_commit_ruby_library)
      push_to_ref_update(push_changes(repository: repo, changes: { path: "not-the-trigger.md", content: "irrelevant" }))

      user = repo.owner
      repo.heads.create("topic", repo.heads.read("master").target, user)
      push = push_to_ref_update(push_changes(repository: repo, branch_name: "topic", changes: { path: "not-the-trigger.md", new_path: ".github/some-file.md" }))

      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/some-file.md")

      assert_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], push), trigger
    end

    test "should not install when branch is deleted" do
      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/other-file")

      branch_name = "master"
      branch = @repo.heads.find(branch_name)

      push = push_to_ref_update(create :push,
        before: branch.target.first_parent_oid,
        after: GitHub::NULL_OID,
        ref: "refs/heads/#{branch_name}",
        repository_id: @repo.id,
        pusher_id: @repo.owner.id,
        pushed_at: Time.now
      )

      refute_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], push), trigger
    end

    test "gracefully handles changed_files returning nil" do
      repo = create(:repository, from_example: :initial_commit_ruby_library)
      push_to_ref_update(push_changes(repository: repo, changes: { path: "not-the-trigger.md", content: "irrelevant" }))

      user = repo.owner
      repo.heads.create("topic", repo.heads.read("master").target, user)
      push = push_to_ref_update(push_changes(repository: repo, branch_name: "topic", changes: { path: "not-the-trigger.md", new_path: ".github/some-file.md" }))
      push.changed_files
      trigger = create(:integration_install_trigger, integration: @app, install_type: :file_added, path: "\\A\\.github/some-file.md")

      repo.spokes_api.class.any_instance.stubs(:compare_oids).raises(SpokesAPI::Error)

      refute_includes AutomaticAppInstallation::Handlers::FileAdded.matched_install_triggers([trigger], push), trigger
    end
  end

  context "Workflow File Added" do
    test "integration with single_repo_installs_required? and Actions enabled" do
      triggers = [
        create(:integration_install_trigger,
               integration: @launch_app,
               install_type: :file_added,
               path: "\\A\\.github/workflows/main.yml"),
      ]

      handler = AutomaticAppInstallation::Handlers::FileAdded.new(
        install_triggers: triggers,
        originator: @flowfile_push,
        actor: @flowfile_push.pusher,
      )

      Timecop.freeze do
        assert_enqueued_with job: InstallAutomaticIntegrationsJob, args: [
          @flowfile_push.repository.owner.id,
          triggers.first.integration.id,
          triggers.first.id,
          Array(@flowfile_push.repository.id),
          {
            enqueued_timestamp: Time.now.to_i,
            entry_point: :automatic_app_installation_handler_file_added,
            pusher: @flowfile_push.pusher,
            before: @flowfile_push.before,
            after: @flowfile_push.after,
            ref: @flowfile_push.ref
          },
        ] do
          handler.install_integration
        end
      end
    end

    test "does not attempt install when Actions is disabled" do
      GitHub.stubs(:actions_enabled?).returns(false)

      triggers = [
        create(:integration_install_trigger,
               integration: @launch_app,
               install_type: :file_added,
               path: "\\A\\.github/workflows/main.yml"),
      ]

      handler = AutomaticAppInstallation::Handlers::FileAdded.new(
        install_triggers: triggers,
        originator: @flowfile_push,
        actor: @flowfile_push.pusher,
      )
      handler.install_integration

      assert_no_enqueued_jobs only: InstallAutomaticIntegrationsJob
    end
  end

  context "Dependabot Config File Added" do
    test "installs Dependabot" do
      triggers = [
        create(:dependabot_config_file_added_trigger),
      ]

      handler = AutomaticAppInstallation::Handlers::FileAdded.new(
        install_triggers: triggers,
        originator: @dependabot_config_push,
        actor: @dependabot_config_push.pusher,
      )

      Timecop.freeze do
        assert_enqueued_with job: InstallAutomaticIntegrationsJob, args: [
          @dependabot_config_push.repository.owner.id,
          triggers.first.integration.id,
          triggers.first.id,
          Array(@dependabot_config_push.repository.id),
          {
            enqueued_timestamp: Time.now.to_i,
            entry_point: :automatic_app_installation_handler_file_added,
            pusher: @dependabot_config_push.pusher,
            before: @dependabot_config_push.before,
            after: @dependabot_config_push.after,
            ref: @dependabot_config_push.ref
          },
        ] do
          handler.install_integration
        end
      end
    end
    # GitHub.dependabot_app is always nil in enterprise, so we fail over to
    # behaving like a default app, which means we do not check the feature flag.
    #
    # It is acceptable to skip this test as we will not create the trigger
    # in Enterprise installs until we are shipping the app itself.
  end unless GitHub.enterprise?

  context "Trigger validation" do
    test "errors on invalid path" do
      invalid_trigger = build(:integration_install_trigger, install_type: :file_added, path: "\\Afoo/")
      refute_predicate invalid_trigger, :valid?
      assert_match "Path must start with one of", invalid_trigger.errors.full_messages.first
    end

    test "allows valid path" do
      trigger = build(:integration_install_trigger, install_type: :file_added, path: "\\A\\.github/test.yml\\z")
      assert_predicate trigger, :valid?

      trigger = build(:integration_install_trigger, install_type: :file_added, path: "\\A\\.github\\/test.yaml\\z")
      assert_predicate trigger, :valid?
    end

    test "allows nil path for deactivated trigger" do
      trigger = build(:integration_install_trigger, install_type: :file_added, deactivated: true, path: nil)
      assert_predicate trigger, :valid?
    end
  end
end

class AutomaticAppInstallation::Handlers::FileAddedWithAfterInstallHookDelivieriesTest < GitHub::TestCase
  fixtures do
    @app = create(:integration, :with_active_hook, default_permissions: { "contents" => :read })
    @repo = create(:repository, from_example: :initial_commit_ruby_library)
    @flowfile_push = push_changes(repository: @repo, changes: { path: ".github/workflows/main.yml", content: "irrelevant" })
  end

  setup do
    Spokesd.enable_spokesd
    GitHub.stubs(:actions_enabled?).returns(true)

    @flowfile_push = push_to_ref_update(@flowfile_push)
  end

  include PushTestHelper
  include HookIntegrationTestHelper

  context "Workflow File Added" do
    test "triggers Push hook event after installation and uses actions aqueduct client" do
      GitHub.stubs(:launch_github_app).returns(@app)
      GitHub.stubs(:aqueduct_gateway_circuit_breaker).returns(nil)
      client = AqueductTestClient.new(app: "actions-test")
      client.stubs(:send_job).returns(stub("http-response", status: 200, body: "OK"))
      GitHub.expects(:build_aqueduct_client).with(app: "actions-test",
        url: GitHub.aqueduct_gateway_url,
        circuit_breaker: nil,
        api_key: nil,
        api_key_version: nil).once.returns(client)

      triggers = [
        create(:integration_install_trigger,
              integration: @app,
              install_type: :file_added,
              path: "\\A\\.github/workflows/main.yml"),
      ]

      handler = AutomaticAppInstallation::Handlers::FileAdded.new(
        install_triggers: triggers,
        originator: @flowfile_push,
        actor: @flowfile_push.pusher,
      )

      deliveries = subscribe_to_hook_delivery "push"

      only = [InstallAutomaticIntegrationsJob, PostPushEventToHookshotJob]
      perform_enqueued_jobs(only: only) do
        handler.install_integration
      end

      assert_equal 1, deliveries.count
      assert_includes deliveries.hooks, @app.hook

      payload = deliveries.payload_for_hook(@app.hook)
      assert_equal @flowfile_push.before, payload[:before]
      assert_equal @flowfile_push.after, payload[:after]
      assert_equal @flowfile_push.ref, payload[:ref]
    end
  end
end
