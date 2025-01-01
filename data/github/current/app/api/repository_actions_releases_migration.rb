# typed: true
# frozen_string_literal: true

class Api::RepositoryActionsReleasesMigration < Api::App

  # Start migration of semver releases to immutable actions
  post "/repositories/:repository_id/immutable-actions/migrate-semver-releases", operation_id: "repos/migrate-semver-releases" do
    control_access :migrate_semver_releases_to_immutable_actions,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    migrate_to_immutable_actions = repo.feature_enabled?(:migrate_to_immutable_actions) || repo.owner.feature_enabled?(:migrate_to_immutable_actions)
    if !migrate_to_immutable_actions
      deliver_error!(403, message: "Repo is not permitted to migrate to immutable actions")
    end

    deliver_error!(403, message: "Actions is not enabled for this repository") unless repo.actions_enabled?

    MigrateSemverReleasesToImmutableActionsJob.perform_later(repo, current_user)

    deliver_empty status: 202
  end

  # Get migration status of semver releases to immutable actions
  get "/repositories/:repository_id/immutable-actions/migration-status", operation_id: "repos/migrate-semver-releases-status" do
    # reusing the same access control as the migration start endpoint
    control_access :migrate_semver_releases_to_immutable_actions,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    migrate_to_immutable_actions = repo.feature_enabled?(:migrate_to_immutable_actions) || repo.owner.feature_enabled?(:migrate_to_immutable_actions)
    if !migrate_to_immutable_actions
      deliver_error!(403, message: "Repo is not permitted to migrate to immutable actions")
    end

    migration_status_key = "immutable_actions_migration_status:repo:#{repo.id}"
    migration_status = kv(migration_status_key).get(migration_status_key).value!

    if migration_status.nil?
      deliver_raw({ migration_status: "not_started" }, status: 200)
    elsif migration_status == "in_progress"
      repo_id = repo.id
      migration_versions_left_key = "immutable_actions_migration_versions_left:repo:#{repo_id}"

      # the key-value pair should always exist if the job is in progress
      migration_versions_left_key_value = kv(migration_versions_left_key).get(migration_versions_left_key).value!
      deliver_raw({ migration_status: "in_progress", num_versions_to_migrate: migration_versions_left_key_value }, status: 200)
    else
      deliver_raw({ migration_status: migration_status }, status: 200)
    end
  end

  def packages_v2_client
    @client ||= ::PackageRegistry::Twirp.metadata_client
  end

  def kv(job_key)
    Actions::KV.for_key(job_key)
  end
end
