# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroCodespacesOnPushJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include CodespacesPlanFixtures

  setup do
    make_trusted_oauth_apps_owner
    @organization = create(:organization)
    @user = create(:user)
    @repository = create(:repository, owner: @user, from_example: :post_receive_job_test)
    @commit_sha_before = "4c8124ffcf4039d292442eeccabdeca5af5c5017"
    @commit_sha_after = "a47fd41f3aa4610ea527dcc1669dfdb9c15c5425"
    @branch = "master"
    @ref = "refs/heads/master"
    @updates = [Git::Ref::Update.new(repository: @repository, refname: @ref, before_oid: @commit_sha_before, after_oid: @commit_sha_after)]
    @time = Time.current
    @message = {
      repository_id: @repository.id,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      ref_updates: @updates.map { |u| { ref: u.refname, before: u.before_oid, after: u.after_oid } },
      pushed_at: @time,
      push_options: Hydro::EntitySerializer.push_options(["pull.ready"]),
      oauth_access_id: 1,
      user_programmatic_access_id: 2,
      installation_id: 3,
      installation_type: "IntegrationInstallation",
      excluded_pull_ids: [1],
      merge_method: "merge",
      merge_action: "merge_queue",
      pusher: @user.login
    }

    @codespaces_app = create(:codespaces_integration)
    @actions_app = create(:launch_integration)
    @codespace = create(:codespace, repository: @repository, billable_owner: @organization, owner: @user)
  end

  context "trigger CreatePrebuildTemplateDynamicWorkflowJob", skip_enterprise: true do
    test "does not call :perform_later on Codespaces::CreatePrebuildTemplateDynamicWorkflowJob when cannot find a prebuild configuration" do
      Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.expects(:perform_later).never

      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_codespaces_on_push")
    end

    test "does not call :perform_later on Codespaces::CreatePrebuildTemplateDynamicWorkflowJob when actions are disabled" do
      repo = create(:repository, owner: @user, from_example: :refs_test)
      locations = %w[
        EastUs
        WestEurope
        WestUs2
      ]
      configuration = create(:codespace_prebuild_configuration, repository: repo, branch: @branch, with_locations: locations)
      repo.disable_actions(actor: @user)


      Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.expects(:perform_later).never

      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_codespaces_on_push")
    end

    test "call :perform_later on Codespaces::CreatePrebuildTemplateDynamicWorkflowJob with no vscs_target" do
      example_repo :refs_test, @repository
      locations = %w[
        EastUs
        EastUs2
        UkSouth
        WestEurope
        WestUs2
        WestUs3
      ]
      configuration = create(:codespace_prebuild_configuration, repository: @repository, branch: @branch, with_locations: locations)

      Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.expects(:perform_later).with(
        repository: @repository,
        branch: @branch,
        locations: locations,
        commit_sha: @commit_sha_after,
        concurrency_modifier: configuration.id.to_s,
        vscs_target: :production,
        vscs_target_url: nil,
        configuration: configuration,
        devcontainer_path: nil,
        previous_sha: nil
      )

      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_codespaces_on_push")
    end

    test "call :perform_later on Codespaces::CreatePrebuildTemplateDynamicWorkflowJob with vscs_target" do
      example_repo :refs_test, @repository
      locations = [
        "WestUs2",
      ]
      configuration = create(
        :codespace_prebuild_configuration,
        repository: @repository,
        branch: @branch,
        vscs_target: "development",
        with_locations: locations)

      Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.expects(:perform_later).with(
        repository: @repository,
        branch: @branch,
        locations: locations,
        commit_sha: @commit_sha_after,
        concurrency_modifier: configuration.id.to_s,
        vscs_target: :development,
        vscs_target_url: nil,
        configuration: configuration,
        devcontainer_path: nil,
        previous_sha: nil,
      )

      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_codespaces_on_push")
    end

    test "call :perform_later on Codespaces::CreatePrebuildTemplateDynamicWorkflowJob when Push trigger selected" do
      example_repo :refs_test, @repository
      locations = %w[
        EastUs
        EastUs2
        UkSouth
        WestEurope
        WestUs2
        WestUs3
      ]
      configuration = create(:codespace_prebuild_configuration, repository: @repository, branch: @branch, with_locations: locations, trigger: Codespaces::PrebuildConfiguration.triggers["push"])

      Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.expects(:perform_later).with(
        repository: @repository,
        branch: @branch,
        locations: locations,
        commit_sha: @commit_sha_after,
        concurrency_modifier: configuration.id.to_s,
        vscs_target: :production,
        vscs_target_url: nil,
        configuration: configuration,
        devcontainer_path: nil,
        previous_sha: nil
      )

      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_codespaces_on_push")
    end

    test "call :perform_later on Codespaces::CreatePrebuildTemplateDynamicWorkflowJob when Configuration trigger selected and hash changed" do
      example_repo :refs_test, @repository
      locations = %w[
        EastUs
        EastUs2
        UkSouth
        WestEurope
        WestUs2
        WestUs3
      ]
      configuration = create(:codespace_prebuild_configuration, repository: @repository, branch: @branch, with_locations: locations, trigger: Codespaces::PrebuildConfiguration.triggers["configuration"])

      Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.expects(:perform_later).with(
        repository: @repository,
        branch: @branch,
        locations: locations,
        commit_sha: @commit_sha_after,
        concurrency_modifier: configuration.id.to_s,
        vscs_target: :production,
        vscs_target_url: nil,
        configuration: configuration,
        devcontainer_path: nil,
        previous_sha: @commit_sha_before
      )

      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_codespaces_on_push")
    end

    test "call :perform_later on Codespaces::CreatePrebuildTemplateDynamicWorkflowJob for correct locations" do
      example_repo :refs_test, @repository
      geos = %w[
        UsEast
        EuropeWest
        UsWest
      ]

      configuration = create(:codespace_prebuild_configuration, repository: @repository, branch: @branch, with_geos: geos)

      locations = Codespaces::Locations::Region.where(geo: geos).map(&:id)

      # checks if configuration.region_names is a subset of locations
      assert_operator (configuration.region_names & locations).size, :==, configuration.region_names.size


      Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.expects(:perform_later).with(
        repository: @repository,
        branch: @branch,
        locations: configuration.region_names,
        commit_sha: @commit_sha_after,
        concurrency_modifier: configuration.id.to_s,
        vscs_target: :production,
        vscs_target_url: nil,
        configuration: configuration,
        devcontainer_path: nil,
        previous_sha: nil
      )

      perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_codespaces_on_push")
    end

    test "can update the codespace if necessary" do
      # this setup is needed to meet all the condititions in VerifyCreationMetadata#perform that cause an update of the codespace
      oid = SecureRandom.hex(20)
      create(:codespace, owner: @user, repository: @repository, ref: oid)
      Codespaces::GetTargetRef.any_instance.stubs(:call).returns(Git::Ref.new(@repository, "refs/heads/master", SecureRandom.hex(20)))

      perform_hydro_message_job(@message.merge({ ref_updates: [{ ref: oid, before: SecureRandom.hex(20), after: SecureRandom.hex(20) }] }), schema: "github.repositories.v1.Pushed", queue: "hydro_codespaces_on_push")
    end
  end

  test "triggers Codespaces::PrebuildConfiguration.destroy_prebuilds", skip_enterprise: true do
    Codespaces::PrebuildConfiguration.expects(:destroy_prebuilds).with(branch: @branch, repository: @repository)
    perform_hydro_message_job(
      @message.merge({
        ref_updates: [{ before: @commit_sha_before, after: GitHub::NULL_OID, ref: @ref }],
      }),
      schema: "github.repositories.v1.Pushed",
      queue: "hydro_codespaces_on_push")
  end

  test "calls Codespace#exported! on export branch create", skip_enterprise: true do
    Codespace.any_instance.expects(:exported!).once
    perform_hydro_message_job(
      @message.merge({
        ref_updates: [{ before: GitHub::NULL_OID, after: @commit_sha_after, ref: "refs/heads/" + Codespace::EXPORT_BRANCH_PREFIX + @codespace.name }]
      }),
      schema: "github.repositories.v1.Pushed",
      queue: "hydro_codespaces_on_push")
  end

  test "does not query when the branch name does not match export format" do
    Codespace.expects(:find_by).never
    perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "hydro_codespaces_on_push")
  end

  test "receiving an export branch leaves `last_export_end_at` if the codespace is not exporting", skip_enterprise: true do
    assert_no_changes -> { @codespace.reload.last_export_end_at } do
      perform_hydro_message_job(
        @message.merge({
          ref_updates: [{ before: GitHub::NULL_OID, after: @commit_sha_after, ref: "refs/heads/#{@codespace.export_branch_name}" }],
        }),
        schema: "github.repositories.v1.Pushed",
        queue: "hydro_codespaces_on_push")
    end
  end

  test "receiving an export branch updates `last_export_end_at` if the codespace is exporting", skip_enterprise: true do
    @codespace.exporting!

    assert_changes -> { @codespace.reload.last_export_end_at } do
      perform_hydro_message_job(
        @message.merge({
          ref_updates: [{ before: GitHub::NULL_OID, after: @commit_sha_after, ref: "refs/heads/#{@codespace.export_branch_name}" }],
        }),
        schema: "github.repositories.v1.Pushed",
        queue: "hydro_codespaces_on_push")
    end
  end

  test "is enqueued by RepositoryPushJobTrigger", skip_enterprise: true do
    locations = %w[
      WestEurope
      WestUs2
    ]
    configuration = create(
      :codespace_prebuild_configuration,
      repository: @repository,
      branch: @branch,
      vscs_target: "development",
      with_locations: locations)

    trigger = RepositoryPushJobTrigger.new(@repository, @pusher, @updates, @time, nil)

    perform_enqueued_hydro_jobs(publisher: GitHub.sync_hydro_publisher, only: [HydroCodespacesOnPushJob], allowed_primary_query_count: 4) do
      trigger.enqueue
    end

    assert_enqueued_jobs 1, only: Codespaces::CreatePrebuildTemplateDynamicWorkflowJob
  end
end
