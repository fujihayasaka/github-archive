# typed: true
# frozen_string_literal: true

class MigrateSemverReleasesToImmutableActionsJob < ApplicationJob
  include GitHub::Tracing
  include RegistryTwo::PackagesMigrationHelper

  retry_on_dirty_exit

  queue_as :migrate_semver_releases_to_immutable_actions

  MAX_RETRY_COUNT_PER_TAG = 5
  ATTEMPT_NEXT_TAG_MIGRATION_AFTER = 30.seconds
  CHECK_WORKFLOW_RUN_STATUS_AFTER = 30.seconds
  RETRY_FAILED_TAG_MIGRATION_AFTER = 2.minutes

  MIGRATION_IN_PROGRESS = "in_progress".freeze
  MIGRATION_FAILED = "failed".freeze
  MIGRATION_COMPLETED = "completed".freeze

  def perform(repository, actor)
    return unless repository.feature_enabled?(:migrate_to_immutable_actions)

    tags_to_migrate = find_tags_to_migrate(repository, actor)
    return if tags_to_migrate.empty?

    # set migration status to in progress
    set_status_key_value_pair(repository, MIGRATION_IN_PROGRESS)

    total_tags_to_migrate = tags_to_migrate.size
    num_tags_left_to_migrate = total_tags_to_migrate

    tags_to_migrate.each do |tag|
      set_in_progress_key_value_pair(repository, num_tags_left_to_migrate)

      external_id = queue_dynamic_workflow_run_with_retry(repository, actor, tag, total_tags_to_migrate, num_tags_left_to_migrate)

      if external_id.nil? # this is the failure case
        remove_in_progress_key_value_pair(repository)
        set_status_key_value_pair(repository, MIGRATION_FAILED)
        return
      else
        # dynamic run successfully enqueued
        check_suite = wait_for_completed_workflow_run_with_retry(repository, external_id, tag)
        if check_suite.nil? # this is the failure case
          remove_in_progress_key_value_pair(repository)
          set_status_key_value_pair(repository, MIGRATION_FAILED)
          return
        end
      end
      num_tags_left_to_migrate -= 1
    end

    remove_in_progress_key_value_pair(repository)
    GitHub.dogstats.increment("packages.migrate_to_immutable_actions_job.finished_migration")
    GitHub.logger.info(
      "Immutable Actions migration for repository #{repository.name_with_display_owner} has finished",
      "code.namespace": self.class.name,
      "gh.repo.id": repository.id,
    )
    set_status_key_value_pair(repository, MIGRATION_COMPLETED)
  end

  private

  def queue_dynamic_workflow_run_with_retry(repository, actor, tag, total_tags_to_migrate, num_tags_left_to_migrate)
    attempt_number = 1
    loop do
      if attempt_number > MAX_RETRY_COUNT_PER_TAG
        GitHub.dogstats.increment("packages.migrate_to_immutable_actions_job.failed_to_enqueue")
        GitHub.logger.error(
          "Maximum number of attempts reached for migrating tag in repository #{repository.name_with_display_owner} to immutable actions",
          "code.namespace": self.class.name,
          "gh.repo.id": repository.id,
          "gh.repo.tag": tag
        )
        return nil
      end

      external_id = enqueue_dynamic_workflow_for_tag(repository, actor, tag, total_tags_to_migrate, num_tags_left_to_migrate)
      if external_id.nil?
        attempt_number += 1
        sleep(RETRY_FAILED_TAG_MIGRATION_AFTER)
      else
        return external_id
      end
    end
  end

  def wait_for_completed_workflow_run_with_retry(repository, external_id, tag)
    sleep(ATTEMPT_NEXT_TAG_MIGRATION_AFTER)
    attempt_number = 1

    loop do
      if attempt_number > MAX_RETRY_COUNT_PER_TAG
        GitHub.dogstats.increment("packages.migrate_to_immutable_actions_job.max_retries_reached")
        GitHub.logger.error(
          "Maximum number of attempts reached for migrating tag #{tag} in #{repository.name_with_display_owner} to immutable actions. Previous dynamic workflow run is still in progress",
          "code.namespace": self.class.name,
          "gh.repo.id": repository.id,
          "gh.repo.tag": tag,
          "gh.check_suite.external_id": external_id
        )
        return nil
      end

      # by_external_id_per_app is the only index with external_id so we have to use it. The GitHub App ID is required so we also need to include that.
      # There can also be the lab launch GitHub App ID but migrations should never be kicked off for that environment so it can be ignored
      check_suite = CheckSuite.from("check_suites FORCE INDEX(by_external_id_per_app)").find_by(
        repository_id: repository.id,
        github_app_id: GitHub.launch_github_app.id,
        external_id: external_id,
      )

      if check_suite.nil?
        # This should never happen. Log and exit. Do not even retry
        GitHub.dogstats.increment("packages.migrate_to_immutable_actions_job.no_check_suite_found")
        GitHub.logger.error(
          "Unable to find check suite for previously enqueued dynamic workflow in #{repository.name_with_display_owner} during immutable actions migration",
          "code.namespace": self.class.name,
          "gh.repo.id": repository.id,
          "gh.check_suite.external_id": external_id
        )
        return nil
      elsif check_suite.completed?
        # Fail the job upon first workflow run
        # Log failed workflow runs just for internal telemetry
        if check_suite.failed?
          GitHub.dogstats.increment("packages.migrate_to_immutable_actions_job.failed_workflow_run")
          GitHub.logger.info(
            "Failed workflow run in #{repository.name_with_display_owner} during immutable actions migration. Not retrying",
            "code.namespace": self.class.name,
            "gh.repo.id": repository.id,
            "gh.check_suite.id": check_suite.id,
            "gh.check_suite.external_id": external_id
          )
          return nil
        end

        return check_suite
      else
        # still in-progress or queued
        sleep(CHECK_WORKFLOW_RUN_STATUS_AFTER)
        attempt_number += 1
      end
    end
  end

  # The order of tags to migrate is dictated by the order of the repository releases
  # This is currently ordered by creation time but this should change to ordered by semver. See https://github.com/github/package-registry-team/issues/7804
  def find_tags_to_migrate(repository, actor)
    tag_names = repository.releases.pluck(:tag_name).uniq # this determines the order of tags to migrate
    @semver_parser = Actions::Resolver::V2::Internal::SemverParser.new
    uniq_tags = tag_names.select { |tag| @semver_parser.is_full_semver?(tag) }

    existing_package_version_tags = Set.new
    package_metadata = packages_v2_client.get_package_metadata(namespace: repository.owner.display_login, name: repository.name.downcase, ecosystem: "CONTAINER", actor: actor)

    if package_metadata&.package.nil?
      # this just means that the package has not been migrated at all yet
    else
      package_versions = package_metadata.package_versions
      package_versions.each do |package_version|
        tags = package_version.tags.map { |tag| tag.name }
        existing_package_version_tags.merge(tags)
      end
    end

    tags_to_skip = []
    tags_to_migrate = []

    uniq_tags.each do |tag|
      # Noramlize the tags that are being migrated over
      if existing_package_version_tags.include?(tag.sub(/\Av/, ""))
        tags_to_skip << tag
        next
      end
      tags_to_migrate << tag
    end

    GitHub.logger.info(
      "Found tags for immutable actions migrations in #{repository.name_with_display_owner }. Tags to migrate: #{tags_to_migrate.join(", ")}. Tags to skip: #{tags_to_skip.join(", ")}",
      "code.namespace": self.class.name,
      "gh.repo.id": repository.id,
    )

    tags_to_migrate
  end

  # When dynamically queueing a workflow run, the returned check suite ID maps to the external_id field in the check_suites table
  # This external_id can later be used to check if the enqueued job has completed
  def enqueue_dynamic_workflow_for_tag(repository, actor, tag, total_tags_to_migrate, num_tags_left_to_migrate)
    # TODO update publish-action-package reference to tag instead of main when we get closer to release
    # TODO locally queue with self-hosted, in production queue with ubuntu-latest
    current_tag_number = total_tags_to_migrate - num_tags_left_to_migrate + 1
    workflow_yaml = %{
      name: 'Migrate Actions Release #{tag} to Immutable Action (job #{current_tag_number} of #{total_tags_to_migrate})'
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
            uses: actions/publish-immutable-action@0.x
            with:
              github-token: ${{ secrets.GITHUB_TOKEN }}
    }

    result = repository.run_dynamic_workflow(
        actor: actor,
        workflow: workflow_yaml,
        ref: "refs/tags/#{tag}",
        inputs: nil,
        workflow_name: "Migrate Actions Release to Immutable Action",
        slug: "migrate_release",
        integration_name: "immutable-actions-migration",
        entry_point: :rest_api_trigger_actions_dynamic_workflow_for_immutable_actions_migration
    )

    if result.call_succeeded?
      GitHub.dogstats.increment("packages.migrate_to_immutable_actions_job.enqueue_success")
      result.value.execution_id
    else
      GitHub.dogstats.increment("packages.migrate_to_immutable_actions_job.enqueue_failure")
      nil
    end
  end

  def packages_v2_client
    @client ||= ::PackageRegistry::Twirp.metadata_client
  end

  def set_in_progress_key_value_pair(repository, num_tags_left_to_migrate)
    value = num_tags_left_to_migrate.to_s
    job_key = key_for_migration_versions(repository)
    ActiveRecord::Base.connected_to(role: :writing) do
      kv(job_key).set(job_key, value, expires: 15.minutes.from_now)
    end
  end

  def remove_in_progress_key_value_pair(repository)
    job_key = key_for_migration_versions(repository)
    ActiveRecord::Base.connected_to(role: :writing) do
      kv(job_key).del(job_key)
    end
  end

  def set_status_key_value_pair(repository, status)
    job_key = key_for_migration_status(repository)
    ActiveRecord::Base.connected_to(role: :writing) do
      kv(job_key).set(job_key, status, expires: nil)
    end
  end

  def key_for_migration_versions(repository)
    "immutable_actions_migration_versions_left:repo:#{repository.id}"
  end

  def kv(job_key)
    Actions::KV.for_key(job_key)
  end
end
