# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/launch/dynamic_workflow_helper"

class MigrateSemverReleasesToImmutableActionsJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper
  include Launch::DynamicWorkflowHelper

  PackageMetadataMock = Struct.new(:package, :latest_version, :versions, :total_version_count, :total_tagged_versions_count, :total_untagged_versions_count)
  VersionMock = Struct.new(:id, :package_id, :name, :original_name, :description, :blob_store, :ecosystem, :containerMetadata, :created_at, :updated_at, :deleted_at, :npmMetadata)
  PackageMock = Struct.new(:id, :namespace, :name, :original_name, :ecosystem, :created_at, :updated_at, :author_id, :visibility, :repo_id, :deleted_at, :migrated_at)
  TimeMock = Struct.new(:seconds, :nanos)
  ContainerMetadataMock = Struct.new(:manifest, :tags, :labels)
  LabelsMock = Struct.new(:all_labels)
  TagMock = Struct.new(:name, :digest)

  fixtures do
    @repo = create(:repository, from_example: :simple)
    @actor = create(:user)

    METADATA_CLIENT = ::PackageRegistry::Twirp::MetadataClient
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(@launch_app)
  end

  test "successfully triggers a dynamic workflow for one tag", skip_if_feature_disabled: :migrate_to_immutable_actions do
    create(:release, repository: @repo, state: :published, tag_name: "v3.11.9")

    mock_meta = mock_package_metadata(namespace: @repo.name, author_id: @actor.id)
    mock_pkg = mock_meta.package
    mock_pkg.repo_id = @repo.id
    mock_version = mock_meta.latest_version

    METADATA_CLIENT.any_instance.stubs(:get_package_metadata).returns(mock_meta)
    ::PackageRegistry::Twirp::ActionPackages::Client.any_instance.stubs(:get_action_package_resolution_settings).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new)

    mock_check_suite_external_id = "236e6ad1-d8d4-47cd-9f12-136993621eb7"
    mock_run_dynamic_workflow(
      repo: @repo,
      integration_name: "immutable-actions-migration",
      workflow: expected_workflow_yaml("v3.11.9"),
      actor: @actor,
      ref: "refs/tags/v3.11.9",
      inputs: nil,
      workflow_name: "Migrate Actions Release to Immutable Action",
      slug: "migrate_release",
      execution_id: mock_check_suite_external_id,
    )

    actions_check_suite = create(:check_suite_for_actions_app, :success, repository: @repo, external_id: mock_check_suite_external_id)

    MigrateSemverReleasesToImmutableActionsJob.stub_const(:WAIT_UNTIL_NEXT_JOB_AFTER, 0.seconds) do
      MigrateSemverReleasesToImmutableActionsJob.stub_const(:ATTEMPT_NEXT_TAG_MIGRATION_AFTER, 0.seconds) do
        perform_enqueued_jobs only: [MigrateSemverReleasesToImmutableActionsJob] do
          MigrateSemverReleasesToImmutableActionsJob.perform_now(@repo, @actor)
        end
      end
    end

    assert_equal kv_get("immutable_actions_migration_status:repo:#{@repo.id}"), "completed"
    assert_dogstats_increment 1, "packages.migrate_to_immutable_actions_job.enqueue_success"
    assert_dogstats_increment 1, "packages.migrate_to_immutable_actions_job.finished_migration"
    refute_dogstats_count "packages.migrate_to_immutable_actions_job.enqueue_failure"
  end

  test "successfully triggers a dynamic workflow for one non-strict semver tag", skip_if_feature_disabled: :migrate_to_immutable_actions do
    create(:release, repository: @repo, state: :published, tag_name: "3.11.9")

    mock_meta = mock_package_metadata(namespace: @repo.name, author_id: @actor.id)

    METADATA_CLIENT.any_instance.stubs(:get_package_metadata).returns(mock_meta)
    ::PackageRegistry::Twirp::ActionPackages::Client.any_instance.stubs(:get_action_package_resolution_settings).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new)

    mock_check_suite_external_id = "236e6ad1-d8d4-47cd-9f12-136993621eb7"
    mock_run_dynamic_workflow(
      repo: @repo,
      integration_name: "immutable-actions-migration",
      workflow: expected_workflow_yaml("3.11.9"),
      actor: @actor,
      ref: "refs/tags/3.11.9",
      inputs: nil,
      workflow_name: "Migrate Actions Release to Immutable Action",
      slug: "migrate_release",
      execution_id: mock_check_suite_external_id,
    )

    actions_check_suite = create(:check_suite_for_actions_app, :success, repository: @repo, external_id: mock_check_suite_external_id)

    MigrateSemverReleasesToImmutableActionsJob.stub_const(:WAIT_UNTIL_NEXT_JOB_AFTER, 0.seconds) do
      MigrateSemverReleasesToImmutableActionsJob.stub_const(:ATTEMPT_NEXT_TAG_MIGRATION_AFTER, 0.seconds) do
        perform_enqueued_jobs only: [MigrateSemverReleasesToImmutableActionsJob] do
          MigrateSemverReleasesToImmutableActionsJob.perform_now(@repo, @actor)
        end
      end
    end

    assert_equal kv_get("immutable_actions_migration_status:repo:#{@repo.id}"), "completed"
    assert_dogstats_increment 1, "packages.migrate_to_immutable_actions_job.enqueue_success"
    assert_dogstats_increment 1, "packages.migrate_to_immutable_actions_job.finished_migration"
    refute_dogstats_count "packages.migrate_to_immutable_actions_job.enqueue_failure"
  end

  test "successfully triggers a dynamic workflow if multiple paginated get_package_metadata calls are made", skip_if_feature_disabled: :migrate_to_immutable_actions do
    create(:release, repository: @repo, state: :published, tag_name: "3.11.9")

    total_version_count = 2
    mock_offset_per_call = 1
    package_id = 822

    # first metadata response returns 1 package version if there are 2 total versions which will warrant a second call
    first_mock_metadata_response = mock_package_metadata(namespace: @repo.name, author_id: @actor.id, package_id: package_id, total_version_count: total_version_count)
    second_mock_metadata_response = mock_package_metadata(namespace: @repo.name, author_id: @actor.id, package_id: package_id, total_version_count: total_version_count)

    METADATA_CLIENT.any_instance.stubs(:get_package_metadata).returns(first_mock_metadata_response, second_mock_metadata_response)
    ::PackageRegistry::Twirp::ActionPackages::Client.any_instance.stubs(:get_action_package_resolution_settings).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new)

    mock_check_suite_external_id = "236e6ad1-d8d4-47cd-9f12-136993621eb7"
    mock_run_dynamic_workflow(
      repo: @repo,
      integration_name: "immutable-actions-migration",
      workflow: expected_workflow_yaml("3.11.9"),
      actor: @actor,
      ref: "refs/tags/3.11.9",
      inputs: nil,
      workflow_name: "Migrate Actions Release to Immutable Action",
      slug: "migrate_release",
      execution_id: mock_check_suite_external_id,
    )

    actions_check_suite = create(:check_suite_for_actions_app, :success, repository: @repo, external_id: mock_check_suite_external_id)

    expected_log = {
      "Body" =>  "Subsequent get package metadata call in #{@repo.name_with_display_owner } since there are more than #{mock_offset_per_call} total versions.",
      "gh.repo.id" => @repo.id,
      "gh.package.id" => package_id,
      "gh.package.total_version_count" => total_version_count,
      "gh.job.version_offset" => mock_offset_per_call,
    }

    perform_enqueued_jobs only: [MigrateSemverReleasesToImmutableActionsJob] do
      MigrateSemverReleasesToImmutableActionsJob.stub_const(:WAIT_UNTIL_NEXT_JOB_AFTER, 0.seconds) do
        MigrateSemverReleasesToImmutableActionsJob.stub_const(:ATTEMPT_NEXT_TAG_MIGRATION_AFTER, 0.seconds) do
          MigrateSemverReleasesToImmutableActionsJob.stub_const(:MAX_VERSION_LIMIT_PER_CALL, mock_offset_per_call) do
            MigrateSemverReleasesToImmutableActionsJob.stub_const(:GET_PACKAGE_METADATA_PAGINATE_AFTER, 0.seconds) do
              assert_logged(**expected_log) do
                MigrateSemverReleasesToImmutableActionsJob.perform_now(@repo, @actor)
              end
            end
          end
        end
      end
    end

    assert_equal kv_get("immutable_actions_migration_status:repo:#{@repo.id}"), "completed"
    assert_dogstats_increment 1, "packages.migrate_to_immutable_actions_job.enqueue_success"
    assert_dogstats_increment 1, "packages.migrate_to_immutable_actions_job.finished_migration"
    refute_dogstats_count "packages.migrate_to_immutable_actions_job.enqueue_failure"
  end

  test "fails if unable to find a check_suite from enqueued dynamic workflow", skip_if_feature_disabled: :migrate_to_immutable_actions do
    create(:release, repository: @repo, state: :published, tag_name: "v3.11.9")

    mock_meta = mock_package_metadata(namespace: @repo.name, author_id: @actor.id)
    mock_pkg = mock_meta.package
    mock_pkg.repo_id = @repo.id
    mock_version = mock_meta.latest_version

    METADATA_CLIENT.any_instance.stubs(:get_package_metadata).returns(mock_meta)
    ::PackageRegistry::Twirp::ActionPackages::Client.any_instance.stubs(:get_action_package_resolution_settings).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new)

    mock_check_suite_external_id = "bd79e0f8-268d-4b11-979e-1ee753550352"
    check_suite_external_id_that_will_not_exist = "236e6ad1-d8d4-47cd-9f12-136993621eb7"

    mock_run_dynamic_workflow(
      repo: @repo,
      integration_name: "immutable-actions-migration",
      workflow: expected_workflow_yaml("v3.11.9"),
      actor: @actor,
      ref: "refs/tags/v3.11.9",
      inputs: nil,
      workflow_name: "Migrate Actions Release to Immutable Action",
      slug: "migrate_release",
      execution_id: check_suite_external_id_that_will_not_exist,
    )

    actions_check_suite = create(:check_suite_for_actions_app, :success, repository: @repo, external_id: mock_check_suite_external_id)

    MigrateSemverReleasesToImmutableActionsJob.stub_const(:WAIT_UNTIL_NEXT_JOB_AFTER, 0.seconds) do
      MigrateSemverReleasesToImmutableActionsJob.stub_const(:ATTEMPT_NEXT_TAG_MIGRATION_AFTER, 0.seconds) do
        perform_enqueued_jobs only: [MigrateSemverReleasesToImmutableActionsJob] do
          MigrateSemverReleasesToImmutableActionsJob.perform_now(@repo, @actor)
        end
      end
    end

    assert_equal kv_get("immutable_actions_migration_status:repo:#{@repo.id}"), "failed"
    assert_dogstats_increment 1, "packages.migrate_to_immutable_actions_job.enqueue_success"
    assert_dogstats_increment 1, "packages.migrate_to_immutable_actions_job.no_check_suite_found"
    refute_dogstats_count "packages.migrate_to_immutable_actions_job.finished_migration"
  end

  test "fails if check_suite from enqueued dynamic workflow is complete but in a failed state", skip_if_feature_disabled: :migrate_to_immutable_actions do
    create(:release, repository: @repo, state: :published, tag_name: "v3.11.9")

    mock_meta = mock_package_metadata(namespace: @repo.name, author_id: @actor.id)

    METADATA_CLIENT.any_instance.stubs(:get_package_metadata).returns(mock_meta)
    ::PackageRegistry::Twirp::ActionPackages::Client.any_instance.stubs(:get_action_package_resolution_settings).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new)

    mock_check_suite_external_id = "bd79e0f8-268d-4b11-979e-1ee753550352"
    mock_run_dynamic_workflow(
      repo: @repo,
      integration_name: "immutable-actions-migration",
      workflow: expected_workflow_yaml("v3.11.9"),
      actor: @actor,
      ref: "refs/tags/v3.11.9",
      inputs: nil,
      workflow_name: "Migrate Actions Release to Immutable Action",
      slug: "migrate_release",
      execution_id: mock_check_suite_external_id,
    )

    failed_check_suite = create(:check_suite_for_actions_app, :failure, repository: @repo, external_id: mock_check_suite_external_id)

    MigrateSemverReleasesToImmutableActionsJob.stub_const(:WAIT_UNTIL_NEXT_JOB_AFTER, 0.seconds) do
      MigrateSemverReleasesToImmutableActionsJob.stub_const(:ATTEMPT_NEXT_TAG_MIGRATION_AFTER, 0.seconds) do
        perform_enqueued_jobs only: [MigrateSemverReleasesToImmutableActionsJob] do
          MigrateSemverReleasesToImmutableActionsJob.perform_now(@repo, @actor)
        end
      end
    end

    assert_equal kv_get("immutable_actions_migration_status:repo:#{@repo.id}"), "failed"
    assert_dogstats_increment 1, "packages.migrate_to_immutable_actions_job.enqueue_success"
    assert_dogstats_increment 1, "packages.migrate_to_immutable_actions_job.failed_workflow_run"
    refute_dogstats_count "packages.migrate_to_immutable_actions_job.finished_migration"
  end

  test "fails if enqueued workflow run remains in-progress and retries are exhausted", skip_if_feature_disabled: :migrate_to_immutable_actions do
    create(:release, repository: @repo, state: :published, tag_name: "v3.11.9")

    mock_meta = mock_package_metadata(namespace: @repo.name, author_id: @actor.id)

    METADATA_CLIENT.any_instance.stubs(:get_package_metadata).returns(mock_meta)
    ::PackageRegistry::Twirp::ActionPackages::Client.any_instance.stubs(:get_action_package_resolution_settings).returns(Proto::RegistryMetadata::V1::ActionPackages::GetActionPackageResolutionSettingsResponse.new)

    mock_check_suite_external_id = "bd79e0f8-268d-4b11-979e-1ee753550352"
    mock_run_dynamic_workflow(
      repo: @repo,
      integration_name: "immutable-actions-migration",
      workflow: expected_workflow_yaml("v3.11.9"),
      actor: @actor,
      ref: "refs/tags/v3.11.9",
      inputs: nil,
      workflow_name: "Migrate Actions Release to Immutable Action",
      slug: "migrate_release",
      execution_id: mock_check_suite_external_id,
    )

    stuck_check_suite = create(:check_suite_for_actions_app, :in_progress, repository: @repo, external_id: mock_check_suite_external_id)

    MigrateSemverReleasesToImmutableActionsJob.stub_const(:WAIT_UNTIL_NEXT_JOB_AFTER, 0.seconds) do
      MigrateSemverReleasesToImmutableActionsJob.stub_const(:ATTEMPT_NEXT_TAG_MIGRATION_AFTER, 0.seconds) do
        MigrateSemverReleasesToImmutableActionsJob.stub_const(:RETRY_FAILED_TAG_MIGRATION_AFTER, 0.seconds) do
          MigrateSemverReleasesToImmutableActionsJob.stub_const(:CHECK_WORKFLOW_RUN_STATUS_AFTER, 0.seconds) do
            perform_enqueued_jobs only: [MigrateSemverReleasesToImmutableActionsJob] do
              MigrateSemverReleasesToImmutableActionsJob.perform_now(@repo, @actor)
            end
          end
        end
      end
    end

    assert_equal kv_get("immutable_actions_migration_status:repo:#{@repo.id}"), "failed"
    assert_dogstats_increment 1, "packages.migrate_to_immutable_actions_job.enqueue_success"
    assert_dogstats_increment 1, "packages.migrate_to_immutable_actions_job.max_retries_reached"
    refute_dogstats_count "packages.migrate_to_immutable_actions_job.finished_migration"
  end

  private

  def mock_package_metadata(namespace:, author_id:, package_id: rand(1000), visibility: :private, repo_id: 0, total_version_count: 1)
    tag = TagMock.new(name: "3.11.8", digest: "sha256:6b40b12ba9feaf046a277c7b711c3b0e1043d05339f3d501df34842dd9c6b265")

    version = VersionMock.new(
      id: 2,
      package_id: package_id,
      name: "3.12.1",
      description: "Version readme 2",
      blob_store: "filesystem",
      ecosystem: :container,
      containerMetadata: ContainerMetadataMock.new(
        manifest: tag,
        tags: [tag],
        labels: LabelsMock.new(
          all_labels: {}
        )
      ),
      created_at: TimeMock.new(seconds: 1599107251, nanos: 948286000),
      updated_at: TimeMock.new(seconds: 1599542839, nanos: 333573000)
    )

    versions = [version]

    ::PackageRegistry::PackageMetadata.new(PackageMetadataMock.new(
      package: PackageMock.new(
        id: package_id,
        namespace: namespace,
        name: "alpine",
        ecosystem: :container,
        created_at: TimeMock.new(seconds: 1599107251, nanos: 948286000),
        updated_at: TimeMock.new(seconds: 1599542839, nanos: 333573000),
        author_id: author_id,
        visibility: visibility,
        repo_id: repo_id
      ),
      total_version_count: total_version_count,
      latest_version: version,
      versions: versions
    ))
  end

  def expected_workflow_yaml(tag)
    %{
      name: 'Migrate Actions Release #{tag} to Immutable Action (job 1 of 1)'
      'on': dynamic
      jobs:
        migration:
          runs-on: ubuntu-latest
          permissions:
            contents: read
            attestations: write
            id-token: write
            packages: write
          steps:
          - name: Checkout
            uses: actions/checkout@v4
          - name: Publish
            id: Publish
            uses: actions/publish-immutable-action@v0
            with:
              github-token: ${{ secrets.GITHUB_TOKEN }}
    }
  end

  def kv_exists?(key)
    Actions::KV.for_key(key).exists(key).value!
  end

  def kv_set(key, value)
    Actions::KV.for_key(key).set(key, value)
  end

  def kv_get(key)
    Actions::KV.for_key(key).get(key).value!
  end
end
