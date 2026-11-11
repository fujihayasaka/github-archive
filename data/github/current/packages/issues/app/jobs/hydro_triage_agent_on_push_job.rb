# typed: strict
# frozen_string_literal: true

class HydroTriageAgentOnPushJob < Repositories::PushHydroMessageJob
  queue_as :hydro_triage_agent_on_push
  use_primaries ApplicationRecord::Configurations

  sig { returns(T.untyped) }
  def perform
    return if repository.nil? || repository.deleted?

    unless IssuesTriageAgentFeature.enrolled?(repository)
      # No log here - most repos will skip at this stage
      return
    end

    default_branch_update = push_includes_default_branch?
    unless default_branch_update.present?
      log_skip("no default branch update found")
      return
    end

    if default_branch_update.deleted?
      log_skip("default branch update is deleted")
      return
    end

    if default_branch_update.large_push?
      log_skip("large push detected")
      return
    end

    with_write do
      config_change = detect_config_file_change(default_branch_update)

      case config_change
      when :added
        handle_config_file_added(default_branch_update)
      when :deleted
        handle_config_file_deleted
      else
        log_skip("config file not added or deleted in this push")
      end
    end
  end

  private

  sig { params(ref_update: Repositories::RefUpdate).void }
  def handle_config_file_added(ref_update)
    unless config_file_has_content?(ref_update.after)
      log_skip("config file is empty or not found")
      return
    end

    log_config_file_added
  end

  sig { void }
  def handle_config_file_deleted
    log_config_file_deleted
    GitHub.dogstats.increment("triage_agent.config_file_deleted")

    # Auto-disable triage when the config file is deleted and new config is enabled
    if IssuesTriageAgentFeature.new_config_enabled?(repository) && repository.issue_triage_enabled?
      repository.disable_issue_triage(actor: pusher)
      GitHub.dogstats.increment("triage_agent.auto_disabled_config_deleted")
      GitHub.logger.info(
        "HydroTriageAgentOnPushJob: auto-disabled triage after config file deletion",
        "gh.repo.id": repository.id,
        "gh.request_id": request_id,
      )
    end
  end

  sig { params(message: String).void }
  def log_skip(message)
    GitHub.logger.info(
      "HydroTriageAgentOnPushJob: skipping - #{message}",
      "gh.repo.id": repository.id,
      "gh.request_id": request_id,
    )
  end

  sig { void }
  def log_config_file_added
    GitHub.logger.info(
      "HydroTriageAgentOnPushJob: triage agent config file added",
      "gh.repo.id": repository.id,
      "gh.request_id": request_id,
    )
    GlobalInstrumenter.instrument("analytics.event", {
      category: "issue_triage_agent",
      action: "triage_add_instruction",
      label: "repository_nwo:#{repository.name_with_display_owner}"
    })
  end

  sig { void }
  def log_config_file_deleted
    GitHub.logger.info(
      "HydroTriageAgentOnPushJob: triage agent config file deleted",
      "gh.repo.id": repository.id,
      "gh.request_id": request_id,
    )
    GlobalInstrumenter.instrument("analytics.event", {
      category: "issue_triage_agent",
      action: "triage_remove_instruction",
      label: "repository_nwo:#{repository.name_with_display_owner}"
    })
  end

  # Detects whether the config file was added, deleted, or something else in this push
  # Returns :added, :deleted, or :none
  sig { params(ref_update: Repositories::RefUpdate).returns(Symbol) }
  def detect_config_file_change(ref_update)
    # When before is a null OID (new repo or new branch), use EMPTY_TREE_OID
    # to get a diff for all the files added
    before = ref_update.before
    before = GitHub::EMPTY_TREE_OID if before == GitHub::NULL_OID

    changed_files = repository.rpc.native_read_diff_toc(before, ref_update.after, nil)
    return :none unless changed_files.present?

    config_file_change = changed_files.find { |file| file.path == TriageAgent::Configuration::CONFIG_FILE_PATH }
    return :none unless config_file_change

    case config_file_change.status
    when Repositories::ChangedFile::ADDITION
      :added
    when Repositories::ChangedFile::DELETION
      :deleted
    else
      # File was modified, not added or deleted - no action needed
      :none
    end
  end

  sig { params(commit_sha: String).returns(T::Boolean) }
  def config_file_has_content?(commit_sha)
    # Verify the file exists at the commit and has non-empty content.
    # Note: Since we already detected an addition in the diff, the file should exist.
    # We read the contents to ensure it is not empty.
    blob = repository.blob(commit_sha, TriageAgent::Configuration::CONFIG_FILE_PATH)
    blob&.data.present?
  rescue StandardError
    false
  end
end
