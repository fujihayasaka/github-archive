# typed: strict
# frozen_string_literal: true

# Emits sweagentd.v1.AgentsUpdated when agent config files under .github/agents/
# change on the default branch. sweagentd consumes this to sync configs to CosmosDB.
class HydroAgentsOnPushJob < Repositories::PushHydroMessageJob
  queue_as :hydro_agents_on_push

  AGENT_CONFIG_REGEX = %r{\A\.github/agents/}

  sig { void }
  def perform
    GitHub.logger.info(
      "HydroAgentsOnPushJob: invoked",
      "gh.repo.id": repository.id,
    )
    return if repository.nil? || repository.deleted?
    return unless FeatureFlag.vexi.enabled?(:copilot_swe_agent_config_sync, repository, repository.owner, default: false)

    default_branch_update = push_includes_default_branch?
    unless default_branch_update.present?
      log_skip("no default branch update found")
      return
    end

    if default_branch_update.deleted?
      log_skip("default branch update is deleted")
      return
    end

    all_changed_files = default_branch_update.changed_files
    return if all_changed_files.blank?

    agent_changed_files = all_changed_files.select do |f|
      f.path.match?(AGENT_CONFIG_REGEX) || f.previous_path&.match?(AGENT_CONFIG_REGEX)
    end
    return if agent_changed_files.empty?

    GitHub.logger.info(
      "HydroAgentsOnPushJob: publishing AgentsUpdated event",
      "gh.repo.id": repository.id,
      "gh.request_id": request_id,
      "changed_files_count": agent_changed_files.size,
    )
    publish_agents_updated_event(default_branch_update, agent_changed_files)
  end

  private

  sig { params(message: String).void }
  def log_skip(message)
    GitHub.logger.info(
      "HydroAgentsOnPushJob: skipping - #{message}",
      "gh.repo.id": repository.id,
      "gh.request_id": request_id,
    )
  end

  sig { params(ref_update: Repositories::RefUpdate, agent_changed_files: T::Array[Repositories::ChangedFile]).void }
  def publish_agents_updated_event(ref_update, agent_changed_files)
    message = {
      repository: Hydro::EntitySerializer.repository(repository),
      repository_owner: Hydro::EntitySerializer.user(repository.owner),
      actor: Hydro::EntitySerializer.user(pusher),
      commit_sha: ref_update.after,
      changed_files: agent_changed_files.map do |f|
        change_type = f.change_type_symbol
        change_type = :CHANGE_TYPE_UNKNOWN if change_type == :UNKNOWN
        {
          change_type: change_type,
          current_path: f.path,
          previous_path: f.previous_path,
        }
      end,
    }

    GitHub.aqueduct_fallback_hydro_publisher.publish(
      message,
      schema: "sweagentd.v1.AgentsUpdated",
      partition_key: repository.id,
    )
  end
end
