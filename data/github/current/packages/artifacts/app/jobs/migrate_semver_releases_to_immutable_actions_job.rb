# typed: true
# frozen_string_literal: true

class MigrateSemverReleasesToImmutableActionsJob < ApplicationJob
  include GitHub::Tracing
  include RegistryTwo::PackagesMigrationHelper

  retry_on_dirty_exit

  queue_as :migrate_semver_releases_to_immutable_actions

  MAX_RETRY_COUNT_PER_TAG = 5
  MAX_VERSION_LIMIT_PER_CALL = 100
  MAX_GET_PACKAGE_METADATA_TIME = 4.minutes
  GET_PACKAGE_METADATA_PAGINATE_AFTER = 5.seconds
  RETRY_QUEUE_DYNAMIC_WORKFLOW_AFTER = 10.seconds
  RETRY_WORKFLOW_RUN_STILL_IN_PROGRESS_AFTER = 2.minutes
  WAIT_UNTIL_NEXT_JOB_AFTER = 30.seconds

  MIGRATION_IN_PROGRESS = "in_progress".freeze
  MIGRATION_FAILED = "failed".freeze
  MIGRATION_COMPLETED = "completed".freeze

  sig do
    params(
      repository: Repository,
      actor: User,
      check_suite_external_id: T.nilable(String), # nil if this migration job is running for the first time for a repository
      attempt_number: Integer,
      total_number_of_tags_to_migrate: Integer,
      tags_left_to_migrate: T::Array[String]
    ).returns(T.nilable(MigrateSemverReleasesToImmutableActionsJob)) # nil unless a dynamic workflow run is enqueued to migrate a tag
  end
  def perform(repository, actor, check_suite_external_id = nil, attempt_number = 1, total_number_of_tags_to_migrate = 0, tags_left_to_migrate = [])
    # failsafe feature flag to disable the job if something goes wrong during rollout
    return unless repository.feature_flag_enabled?(:migrate_to_immutable_actions, default: false) || T.must(repository.owner).feature_flag_enabled?(:migrate_to_immutable_actions, default: false)

    # The first time the job is enqueued for a repository and no tags have been migrated yet there will be no check_suite_external_id passed in
    migration_starting_for_repository = check_suite_external_id.nil?

    if migration_starting_for_repository
      # no check_suite_external_id means that this is the first time we are running this job for the repository
      set_status_key_value_pair(repository, MIGRATION_IN_PROGRESS)

      all_tags_to_migrate = find_all_tags_to_migrate(repository, actor)
      if all_tags_to_migrate.empty?
        # Before showing the migration banner to run this job we need to ensure there is at least one tag to migrate over, so we should never get in this state
        GitHub.logger.error(
          "No tags found for immutable actions migration in repository_id #{repository.id}",
          "gh.repo.id": repository.id,
        )
        return
      end

      tag_to_migrate = all_tags_to_migrate.first
      remaining_tags_to_migrate_after_dynamic_workflow_enqueued = all_tags_to_migrate[1..]
      number_of_tags = all_tags_to_migrate.size

      external_id = queue_dynamic_workflow_run_with_retry(repository, actor, tag_to_migrate, number_of_tags, number_of_tags)
      if external_id.nil?
        remove_in_progress_key_value_pair(repository)
        set_status_key_value_pair(repository, MIGRATION_FAILED)
      else
        MigrateSemverReleasesToImmutableActionsJob.set(wait_until: WAIT_UNTIL_NEXT_JOB_AFTER.from_now).perform_later(repository, actor, external_id, 1, number_of_tags, remaining_tags_to_migrate_after_dynamic_workflow_enqueued)
      end
    else
      # There was a previously enqueued workflow run, we have to check to make sure it completed before enqueuing a new dynamic workflow run for a new tag
      check_suite = search_for_previously_enqueued_dynamic_workflow_run(repository, check_suite_external_id)

      if check_suite.nil?
        # This should never happen. Log and exit
        GitHub.dogstats.increment("packages.migrate_to_immutable_actions_job.no_check_suite_found")
        GitHub.logger.error(
          "Unable to find check suite for previously enqueued dynamic workflow in repository_id #{repository.id} during immutable actions migration",
          "gh.repo.id": repository.id,
          "gh.check_suite.external_id": check_suite_external_id
        )

        remove_in_progress_key_value_pair(repository)
        set_status_key_value_pair(repository, MIGRATION_FAILED)
      else
        if check_suite.completed?
          if check_suite.failed?
            # Fail the job if a workflow run fails
            # Log failed workflow runs just for internal telemetry
            GitHub.dogstats.increment("packages.migrate_to_immutable_actions_job.failed_workflow_run")
            GitHub.logger.info(
              "Failed workflow run in #{repository.name_with_display_owner} during immutable actions migration. Not retrying",
              "gh.repo.id": repository.id,
              "gh.check_suite.id": check_suite.id,
              "gh.check_suite.external_id": check_suite_external_id
            )

            remove_in_progress_key_value_pair(repository)
            set_status_key_value_pair(repository, MIGRATION_FAILED)
            return
          end

          # enqueue a new job or finish the migration if nothing is left
          tag_to_migrate = tags_left_to_migrate.first
          if tag_to_migrate.nil?
            remove_in_progress_key_value_pair(repository)
            GitHub.dogstats.increment("packages.migrate_to_immutable_actions_job.finished_migration")
            GitHub.logger.info(
              "Immutable Actions migration for repository #{repository.name_with_display_owner} has finished",
              "gh.repo.id": repository.id,
            )
            set_status_key_value_pair(repository, MIGRATION_COMPLETED)
          else
            remaining_tags_to_migrate_after_dynamic_workflow_enqueued = tags_left_to_migrate[1..]
            external_id = queue_dynamic_workflow_run_with_retry(repository, actor, tag_to_migrate, total_number_of_tags_to_migrate, tags_left_to_migrate.size)

            if external_id.nil?
              remove_in_progress_key_value_pair(repository)
              set_status_key_value_pair(repository, MIGRATION_FAILED)
            else
              MigrateSemverReleasesToImmutableActionsJob.set(wait_until: WAIT_UNTIL_NEXT_JOB_AFTER.from_now).perform_later(repository, actor, external_id, 1, total_number_of_tags_to_migrate, remaining_tags_to_migrate_after_dynamic_workflow_enqueued)
            end
          end
        else
          attempt_number += 1
          if attempt_number > MAX_RETRY_COUNT_PER_TAG
            GitHub.dogstats.increment("packages.migrate_to_immutable_actions_job.max_retries_reached")
            GitHub.logger.error(
              "Maximum number of attempts reached for migrating tag in #{repository.name_with_display_owner} to immutable actions. Previous dynamic workflow run is still in progress",
              "gh.repo.id": repository.id,
              "gh.check_suite.external_id": external_id
            )

            remove_in_progress_key_value_pair(repository)
            set_status_key_value_pair(repository, MIGRATION_FAILED)
          else
            MigrateSemverReleasesToImmutableActionsJob.set(wait_until: RETRY_WORKFLOW_RUN_STILL_IN_PROGRESS_AFTER.from_now).perform_later(repository, actor, check_suite_external_id, attempt_number, total_number_of_tags_to_migrate, tags_left_to_migrate)
          end
        end
      end
    end
  end

  private

  # The order of tags to migrate is dictated by the order of the repository releases
  def find_all_tags_to_migrate(repository, actor)
    tag_names = repository.releases.pluck(:tag_name).uniq # this determines the order of tags to migrate
    @semver_parser = Actions::Resolver::V2::Internal::SemverParser.new
    uniq_tags = tag_names.select { |tag| @semver_parser.is_full_semver?(tag) }

    # The get package metadata call returns at most 100 package versions. If there are more than 100 versions than we need to make multiple calls to determine which tags have already been migrated
    # We can't use elastic search as that does not keep track of all the different versions of a package
    version_offset = 0

    existing_package_version_tags = Set.new
    package_metadata = packages_v2_client.get_package_metadata(namespace: repository.owner.display_login, name: repository.name.downcase, ecosystem: "CONTAINER", actor: actor, version_limit: MAX_VERSION_LIMIT_PER_CALL, version_offset: version_offset)

    if package_metadata&.package.nil?
      # this just means that the package has not been migrated at all yet
    else
      total_version_count = package_metadata.total_version_count
      max_end_at = MAX_GET_PACKAGE_METADATA_TIME.from_now # For proxima we are limited to jobs running for a maximum of 5 minutes. We are limiting this to 4 minutes which makes the maximum number of tags we can fetch equal to 4800 which is very large and should be sufficient

      GitHub.logger.info(
        "Found existing package versions for migration in #{repository.name_with_display_owner }.",
        "gh.repo.id": repository.id,
        "gh.package.id": package_metadata.package.id,
        "gh.package.total_version_count": total_version_count,
        "gh.job.version_offset": version_offset
      )

      loop do
        version_offset += MAX_VERSION_LIMIT_PER_CALL

        package_versions = package_metadata.package_versions
        package_versions.each do |package_version|
          tags = package_version.tags.map { |tag| tag.name }
          existing_package_version_tags.merge(tags)
        end

        break if version_offset >= total_version_count

        GitHub.logger.info(
          "Subsequent get package metadata call in #{repository.name_with_display_owner } since there are more than #{MAX_VERSION_LIMIT_PER_CALL} total versions.",
          "gh.repo.id": repository.id,
          "gh.package.id": package_metadata.package.id,
          "gh.package.total_version_count": total_version_count,
          "gh.job.version_offset": version_offset,
        )

        sleep(GET_PACKAGE_METADATA_PAGINATE_AFTER)
        package_metadata = packages_v2_client.get_package_metadata(namespace: repository.owner.display_login, name: repository.name.downcase, ecosystem: "CONTAINER", actor: actor, version_limit: MAX_VERSION_LIMIT_PER_CALL, version_offset: version_offset)

        if package_metadata.nil? # should not happen, but log and break if this does
          GitHub.logger.info(
            "Subseqeuent get metadata call in #{repository.name_with_display_owner } returned no package_metadata.",
            "gh.repo.id": repository.id,
          )

          break
        end

        if Time.now >= max_end_at # safeguard
          GitHub.logger.info(
            "Maximum time limit reached for fetching existing package versions in #{repository.name_with_display_owner }.",
            "gh.repo.id": repository.id,
            "gh.package.id": package_metadata.package.id
          )

          break
        end
      end

      GitHub.logger.info(
        "Finished fetching existing package versions in #{repository.name_with_display_owner }.",
        "gh.repo.id": repository.id,
        "gh.package.id": package_metadata.package.id,
        "gh.package.total_version_count": total_version_count,
        "gh.job.version_offset": version_offset,
        "gh.job.total_existing_tags": existing_package_version_tags.size
      )
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
      "gh.repo.id": repository.id,
    )

    tags_to_migrate
  end

  def queue_dynamic_workflow_run_with_retry(repository, actor, tag, total_tags_to_migrate, num_tags_left_to_migrate)
    attempt_number = 1
    loop do
      if attempt_number > MAX_RETRY_COUNT_PER_TAG
        GitHub.dogstats.increment("packages.migrate_to_immutable_actions_job.failed_to_enqueue")
        GitHub.logger.error(
          "Maximum number of attempts reached for migrating tag in repository #{repository.name_with_display_owner} to immutable actions",
          "gh.repo.id": repository.id,
          "gh.repo.tag": tag
        )
        return nil
      end

      external_id = enqueue_dynamic_workflow_for_tag(repository, actor, tag, total_tags_to_migrate, num_tags_left_to_migrate)
      if external_id.nil?
        attempt_number += 1
        sleep(RETRY_QUEUE_DYNAMIC_WORKFLOW_AFTER)
      else
        return external_id
      end
    end
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
            uses: actions/publish-immutable-action@v0
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

  def search_for_previously_enqueued_dynamic_workflow_run(repository, external_id)
    # by_repo_app_uniqueness_key is the only index with external_id so we have to use it. The GitHub App ID is required so we also need to include that.
    # There can also be the lab launch GitHub App ID but migrations should never be kicked off for that environment so it can be ignored
    CheckSuite.from("check_suites FORCE INDEX(by_repo_app_uniqueness_key)").find_by(
      repository_id: repository.id,
      github_app_id: GitHub.launch_github_app.id,
      external_id: external_id,
    )
  end

  def set_status_key_value_pair(repository, status)
    job_key = key_for_migration_status(repository)
    ActiveRecord::Base.connected_to(role: :writing) do
      kv(job_key).set(job_key, status, expires: nil)
    end
  end

  def remove_in_progress_key_value_pair(repository)
    job_key = key_for_migration_versions(repository)
    ActiveRecord::Base.connected_to(role: :writing) do
      kv(job_key).del(job_key)
    end
  end

  def key_for_migration_versions(repository)
    "immutable_actions_migration_versions_left:repo:#{repository.id}"
  end

  def kv(job_key)
    Actions::KV.for_key(job_key)
  end
end
