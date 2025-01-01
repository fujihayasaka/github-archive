# typed: true
# frozen_string_literal: true

module Codespaces
  class ProcessWebhook < Command
    include GitHub::Memoizer

    attr_reader :raw_data, :environment_data

    def initialize(raw_data)
      @raw_data = raw_data.with_indifferent_access
      @environment_data = Codespaces::Environment.from_json(raw_data)
    end

    def perform
      return unless codespace

      if !codespace.provisioned? && codespace.spammy?
        handle_spammy_codespace
        return
      end

      if codespace.guid && environment_data.id && codespace.guid != environment_data.id
        GitHub.logger.info(
          "codespace webhook received from orphanced codespace with mismatched guid",
          {
            "gh.codespaces.name" => codespace.name,
            "gh.codespaces.guid" => codespace.guid,
            "gh.codespaces.orphaned_guid" => environment_data.id,
          }
        )
        GitHub.dogstats.increment("codespaces.process_webhook.mismatched_guids")
        return
      end

      if environment_data.state.blank?
        ::Codespaces::ErrorReporter.report(::Codespaces::NullStateCodespaceError.new, codespace: codespace)
        GitHub.dogstats.increment("codespaces.process_webhook.null_state_codespace_error")
        return
      end

      if codespace.copilot_workspace?
        handle_copilot_workspace
      end

      if codespace.workspace_editor_cloud_environment?
        handle_task_environment
      end

      if codespace.ephemeral_cloud_environment?
        handle_ephemeral_environment
      end

      # TODO: For now, we are enforcing the same limits for all instead of the type-specific limits
      # We should change this to use the correct concurrency policy for the type of codespace
      # Would make sense to emit an event for this so that each experience can handle it in their own way
      if codespace.owner && environment_data.state && ::Codespaces::Vscs::State::CONSUMING_COMPUTE_STATES.include?(environment_data.state)
        ::Codespaces::ConcurrencyPolicy.new(codespace.owner, billable_owner: codespace.billable_owner).enforce_concurrency_limits!
      end

      track_git_changes
      deprovision_if_failed_to_provision
      check_for_completed_async_operations
      track_codespace_webhook
      update_codespace_environment_data
    end

    private

    memoize def codespace
      Codespace.include_deleted.find_by!(name: environment_data.friendly_name) if environment_data.present?
    end

    def handle_spammy_codespace
      guid = codespace.environment_data&.id
      if guid
        codespace.update!(state: :provisioned, guid: codespace.environment_data&.id)
      end
      codespace.deprovision!
    end

    # Updates `codespace`'s attributes. If an ActiveRecord::RecordInvalid occurs this will
    # fall back to `assign_attributes`/`save` without validations to ensure we save the data
    def update_codespace_environment_data
      return unless codespace.owner
      if codespace.environment_data.nil?
        # This should never happen as far as we know so log some information about the offending codespace when it does.
        GitHub.logger.info(
          "codespace webhook received for codespace with nil environment data",
          {
            "gh.codespaces.name" => codespace.name,
            "gh.codespaces.created_at" => codespace.created_at,
            "gh.codespaces.updated_at" => codespace.updated_at,
            "gh.codespaces.state" => codespace.state,
          }
        )
        GitHub.dogstats.increment("codespaces.process_webhook.codespace_nil_environment_data")
      end
      if environment_data.updated && codespace.environment_data&.updated && environment_data.updated < codespace.environment_data.updated
        GitHub.dogstats.increment("codespaces.process_webhook.skipped_stale_data")
        return
      end

      GitHub.dogstats.increment("codespaces.process_webhook.last_state_update_reason", tags: ["reason:#{environment_data.last_state_update_reason}"]) if environment_data.last_state_update_reason.present?

      if GitHub.flipper[:codespaces_prevent_no_git_repo_bug].enabled?(codespace.owner) && environment_data.no_git_repo? && !codespace.from_codespace_template?
        # This should never happen but is, in fact, happening for reasons we haven't bothered to figure out yet in the
        # service. Rather than wait, we will just ignore this invalid update by reusing what is currently cached on the
        # codespace.
        raw_data = environment_data.to_h
        raw_data["gitStatus"] = codespace.environment_data.git_status
        @environment_data = Codespaces::Environment.from_json(raw_data)
      end

      update_data = {}
      update_data[:environment_data] = environment_data

      # current_branch comes from environment info and is generally the most accurate but it's NOT set initially on the
      # codespace so fallback on the ref instead for the initial state. This should prevent an unnecessary check of the
      # current PR below.
      previous_branch = codespace.current_branch || codespace.ref

      if codespace.guid.nil?
        GitHub.dogstats.increment("codespaces.process_webhook.missing_guid")
      end

      # Any -> "Shutdown"
      if codespace.shutdown_at.nil? && environment_data.state == ::Codespaces::Vscs::State::SHUTDOWN
        update_data[:shutdown_at] = Time.now
        ::Codespaces::InstrumentSuspend.call(codespace:) if GitHub.flipper[:codespaces_improved_shutdown_auditing].enabled?(codespace.owner)
      elsif codespace.shutdown_at.present? && ::Codespaces::Vscs::State::CONSUMING_COMPUTE_STATES.include?(environment_data.state)
        # If we currently think the codespace is shutdown and get a webhook indicating it's now consuming compute then
        # wipe out the value.
        update_data[:shutdown_at] = nil
      end

      if environment_data.current_branch && environment_data.current_branch != previous_branch
        pull = ::Codespaces::FindPullRequest.call(owner: codespace.owner, repository: codespace.repository, ref: environment_data.current_branch)
        update_data[:pull_request] = pull
      end

      begin
        codespace.update!(**update_data)
        codespace.track_pr_source!
      rescue ActiveRecord::RecordInvalid => e
        ::Codespaces::ErrorReporter.report(e)

        codespace.update_attribute(:environment_data, environment_data)
        GitHub.dogstats.increment("codespaces.process_webhook.forced_environment_data_update")
      end
    end

    def deprovision_if_failed_to_provision
      if environment_data.failed?
        GitHub.dogstats.increment("codespaces.process_webhook.deprovisioned_failed_codespace")
        codespace.deprovision!(reason: Codespace.deletion_reasons[:service_provisioning_failed])
      end
    end

    def check_for_completed_async_operations
      ::Codespaces::AsyncOperation.check_for_completed_operations(codespace, env: environment_data)
    end

    def track_codespace_webhook
      return unless raw_data.present?

      client_usage = nil

      # the payload and the event are slightly different
      if raw_data["clientUsage"].present?
        client_usage = {
          "session_id" => raw_data["clientUsage"]["sessionId"],
          "clients" => raw_data["clientUsage"]["usageData"].each do |client, usage|
            last_activity = begin
              Time.parse(usage["lastActivity"])
            rescue ArgumentError
              nil
            end
            raw_data["clientUsage"]["usageData"][client] = usage.transform_keys { |usage_keys| usage_keys.underscore }
            raw_data["clientUsage"]["usageData"][client]["last_activity"] = Google::Protobuf::Timestamp.new(seconds: last_activity.to_i) if last_activity
          end
        }
      end

      client_usage = nil unless ::Codespaces::Events.client_usage_is_valid?(client_usage)

      # Always send this event it tracks that the webhook was received
      ::Codespaces::Events.interaction(codespace: codespace, type: :WEBHOOK_HEARTBEAT, client_usage: client_usage)
    end

    def track_git_changes
      return unless codespace.environment_data.present?
      previous_environment = codespace.environment_data

      # Check for file edits
      new_uncommitted_changes = environment_data.has_uncommitted_changes? && (previous_environment.blank? || !previous_environment.has_uncommitted_changes?)
      new_unpushed_changes = environment_data.has_unpushed_changes? && (previous_environment.blank? || !previous_environment.has_unpushed_changes?)
      if new_uncommitted_changes || new_unpushed_changes
        # If we have any unpushed or uncommitted changes from the environment then I think it's safe to assume some edits have been made.
        ::Codespaces::Events.interaction(codespace: codespace, type: :FILE_CHANGED)
      end

      # Check for pushes
      if previous_environment.has_unpushed_changes? && !environment_data.has_unpushed_changes? && previous_environment.branch == environment_data.branch
        # We had unpushed changes but now we don't. Technically this could just mean they reverted so we do some additional commit checks.
        if codespace.repository.commits.exist?(environment_data.commit)
          # If we have the commit the VM is reportingthey're on then they must have pushed
          ::Codespaces::Events.interaction(codespace: codespace, type: :PUSHED_UPSTREAM)
        end
      end
    end

    def handle_copilot_workspace
      return unless codespace.copilot_workspace?
      if environment_data.state == ::Codespaces::Vscs::State::SHUTDOWN
        # Hard deletes on shutdown. Copilot Workspace syncs the changes, so no data is lost.
        codespace.deprovision! unless codespace.owner&.feature_enabled?(:codespaces_cw_no_delete_on_shutdown)

      end
    end

    def handle_task_environment
      return unless codespace.workspace_editor_cloud_environment?
      if environment_data.state == ::Codespaces::Vscs::State::SHUTDOWN
        # Soft deletes on shutdown. Diff is synced to user's browser.
        codespace.deprovision! unless codespace.owner&.feature_enabled?(:codespaces_hadron_no_delete_on_shutdown)
      end
    end

    def handle_ephemeral_environment
      return unless codespace.ephemeral_cloud_environment?
      if environment_data.state == ::Codespaces::Vscs::State::SHUTDOWN
        codespace.deprovision! unless codespace.owner&.feature_enabled?(:codespaces_ephemeral_no_delete_on_shutdown)
      end
    end
  end
end
