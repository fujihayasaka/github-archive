# typed: true
# frozen_string_literal: true

require "chatops-controller"
require "github_chatops_extensions"

module Chatops
  class DependabotAlertsController < ApplicationController
    include ::Chatops::Controller
    include ::GitHubChatopsExtensions::Checks::Includable::Room

    ALLOWED_ROOMS = ["#dependabot-ops", "#incident-command"].freeze
    MAX_REPUBLISH_VULNERABILITY_IDS = 10

    # Opt-out of all conditional access and secondary authn checks, since these chatops are run by Hubbers
    # from Slack and the routes for triggering them are only accessible through our internal network
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

    before_action :check_room, except: :list

    chatops_namespace :dependabot_alerts
    chatops_help "Commands for working with Dependabot alerts"

    CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
      Chatops::DependabotAlertsController,
    ]

    depends_on_clusters ApplicationRecord::Notify, ApplicationRecord::Mysql1,
      only: [:list]

    private

    def verify_authenticity_token?
      false # robots do this
    end

    def check_room
      require_in_room(ALLOWED_ROOMS)
    end

    def validate_repo(nwo_or_id)
      repo = if /\A[0-9]+\Z/.match(nwo_or_id)
        Repositories.domain.by_id(nwo_or_id)
      else
        Repository.nwo(nwo_or_id)
      end
      repo.present? && repo
    end

    def stalled_alerting_processes_by_event
      cutoff_time = 5.minutes.ago
      grouped = {}
      ActiveRecord::Base.connected_to(role: :reading) do
        VulnerabilityAlertingEvent
          .processing_alerts_since(cutoff_time)
          .where(processed_at: nil, reason: :on_process_alerts)
          .find_each(batch_size: 1000) do |event|
            next unless event.processing_stalled?
            stalled = event.vulnerable_version_range_alerting_processes.select(&:processing_stalled?)
            grouped[event] = stalled if stalled.any?
          end
      end
      grouped
    end

    chatop :list_stalled,
      /list stalled/,
      "list stalled - list out stalled alerting processes grouped by alerting event" do
        grouped = stalled_alerting_processes_by_event

        if grouped.empty?
          chatop_send "No stalled alerting processes found"
        else
          rows = grouped.map do |event, processes|
            vulnerability = event.vulnerability
            ghsa_id = vulnerability&.ghsa_id || "N/A"
            vuln_id = vulnerability&.id || "N/A"
            process_ids = processes.map(&:id).join(", ")
            "| #{event.id} | #{vuln_id} | #{ghsa_id} | #{process_ids} |"
          end

          table = "| Event ID | Vulnerability ID | GHSA ID | Stalled Process IDs |\n"
          table += "| --- | --- | --- | --- |\n"
          table += rows.join("\n")

          chatop_send table
        end
      end

    chatop :abandon_stalled,
      /abandon stalled(\s+(?<process_ids>\d+(,\s*\d+)*))?/,
      "abandon stalled [--event <event_id>] [process_ids] - abandon stalled alerting processes and report affected vulnerability ids. If --event is provided, only stalled processes for that event will be abandoned. If process ids are provided, only those stalled processes will be abandoned." do
        grouped = stalled_alerting_processes_by_event
        event_id_param = jsonrpc_params[:event]
        event_id = event_id_param.present? ? event_id_param.to_i : nil

        if event_id
          matching_event = grouped.keys.find { |e| e.id == event_id }
          if matching_event.nil?
            chatop_send "No stalled alerting processes found for event #{event_id}"
            return
          end
          stalled_processes = grouped[matching_event]
        else
          stalled_processes = grouped.values.flatten
        end

        if stalled_processes.empty?
          chatop_send "No stalled alerting processes found"
          return
        end

        requested_ids = (jsonrpc_params[:process_ids] || "").split(",").map(&:strip).map(&:to_i)

        if requested_ids.any?
          stalled_ids = stalled_processes.map(&:id)
          not_stalled_ids = requested_ids - stalled_ids
          stalled_processes = stalled_processes.select { |p| requested_ids.include?(p.id) }

          if stalled_processes.empty?
            chatop_send "None of the provided process ids are stalled: #{not_stalled_ids.join(", ")}"
            return
          end
        end

        abandoned_ids = []
        vulnerability_ids = Set.new

        stalled_processes.each do |process|
          process.abandon!
          abandoned_ids << process.id
          vuln_id = process.vulnerability_alerting_event&.vulnerability_id
          vulnerability_ids << vuln_id if vuln_id
        end

        messages = []
        messages << "Abandoned #{abandoned_ids.size} stalled alerting process(es): #{abandoned_ids.join(", ")}"
        if vulnerability_ids.any?
          messages << "Affected vulnerability ids: #{vulnerability_ids.to_a.join(", ")}"
        end

        if requested_ids.any?
          not_stalled_ids = requested_ids - abandoned_ids
          if not_stalled_ids.any?
            messages << "Process ids not found in stalled processes: #{not_stalled_ids.join(", ")}"
          end
        end

        chatop_send messages.join("\n")
      end

    chatop :republish,
      /republish\s+(?<vulnerability_ids>\d+(,\s*\d+)*)(?<force>\s+--force)?/,
      "republish <vulnerability_ids> [--force] - republish stalled vulnerabilities to re-trigger alerting (max #{MAX_REPUBLISH_VULNERABILITY_IDS}). Use --force to skip completed event check." do
        vulnerability_ids = jsonrpc_params.fetch(:vulnerability_ids, "").split(",").map(&:strip).map(&:to_i)
        force = jsonrpc_params[:force].present?

        if vulnerability_ids.count > MAX_REPUBLISH_VULNERABILITY_IDS
          chatop_send "Cannot republish more than #{MAX_REPUBLISH_VULNERABILITY_IDS} vulnerabilities at a time."
          return
        end

        messages = []
        vulnerability_ids.each do |vuln_id|
          # rubocop:disable GitHub/PreventUnscopedVulnerabilityQueries This chatop needs direct access to the vulnerability outside of a scope
          vulnerability = Vulnerability.find_by(id: vuln_id)
          if vulnerability.nil?
            messages << "Vulnerability #{vuln_id}: not found"
            next
          end

          unless vulnerability.published?
            messages << "Vulnerability #{vuln_id} (#{vulnerability.ghsa_id}): not published, skipping"
            next
          end

          active_event_id = vulnerability.vulnerability_alerting_events
            .where(reason: :on_process_alerts, processed_at: nil)
            .where("created_at > ?", 1.day.ago)
            .pluck(:id)

          if active_event_id.any?
            messages << "Vulnerability #{vuln_id} (#{vulnerability.ghsa_id}): active event #{active_event_id.first} exists, skipping"
            next
          end

          unless force
            has_completed_event = vulnerability.vulnerability_alerting_events
              .where.not(processed_at: nil)
              .where.not(finished_at: nil)
              .exists?

            if has_completed_event
              messages << "Vulnerability #{vuln_id} (#{vulnerability.ghsa_id}): completed event exists, skipping (use --force to override)"
              next
            end
          end

          event = vulnerability.process_alerts
          if event
            messages << "Vulnerability #{vuln_id} (#{vulnerability.ghsa_id}): republished (event #{event.id})"
          else
            messages << "Vulnerability #{vuln_id} (#{vulnerability.ghsa_id}): not alertable, skipping"
          end
        end

        chatop_send messages.join("\n")
      end

    chatop :list_delivery_stalled,
      /list delivery stalled/,
      "list delivery stalled - list out events stalled during delivery" do
        stalled_events = ActiveRecord::Base.connected_to(role: :reading) do
          VulnerabilityAlertingEvent.where.not(processed_at: nil).where(finished_at: nil, reason: :on_process_alerts).to_a.select(&:delivery_stalled?)
        end

        if stalled_events.empty?
          chatop_send "No stalled alerting events found"
        else
          chatop_send "Stalled alerting event ids: #{stalled_events.map(&:id).join(", ")}"
        end
      end

    chatop :update_repo,
      /update repo (?<repo>.*)?/,
      "update repo [repo] - Enqueue an UpdateRepositoryVulnerabilityAlertsJob for repo" do
        repo = validate_repo(jsonrpc_params.fetch(:repo))
        if repo.nil?
          chatop_send "Could not find repo: #{jsonrpc_params.fetch(:repo)}"
        else
          UpdateRepositoryVulnerabilityAlertsJob.enqueue_for_repository(repo, { enforce_repo_readiness: true })
          chatop_send "Enqueued UpdateRepositoryVulnerabilityAlertsJob for: #{repo.name_with_owner}"
        end
      end

    chatop :restart_process,
      /restart process(?:\s+(?<process_ids>\d+(,\s*\d+)*))(?:\s*(?<cursor>\S+)?)/,
      "restart process [process_ids] [cursor] - Restart stalled VulnerableVersionRangeCreateVulnerabilityAlertsJob. Optionally specify a cursor for a single process." do
        process_ids = jsonrpc_params.fetch(:process_ids, "").split(",").map(&:strip).map(&:to_i)
        cursor = jsonrpc_params.fetch(:cursor, nil)
        if cursor.present? && process_ids.count > 1
          chatop_send "A cursor can only be specified when restarting a single process. Please provide only one process id if you want to specify a cursor."
          return
        end

        if process_ids.count > 100
          chatop_send "Cannot restart more than 100 processes at a time. Please provide 100 or fewer process ids."
          return
        end

        messages = []
        processes = VulnerableVersionRangeAlertingProcess.where(id: process_ids).order(id: :asc).to_a
        missing_processes = process_ids - processes.map(&:id)
        if missing_processes.any?
          messages << "Could not find processes with ids: #{missing_processes.join(", ")}"
        end

        if processes.empty?
          chatop_send messages.join("\n")
          return
        end

        processes.each do |process|
          VulnerableVersionRangeCreateVulnerabilityAlertsJob.perform_later(process.id, cursor: cursor)
        end

        if processes.count > 1
          messages << "Restarted VulnerableVersionRangeCreateVulnerabilityAlertsJob for process ids: #{processes.map(&:id).join(", ")}"
        else
          message  = "Restarted VulnerableVersionRangeCreateVulnerabilityAlertsJob for process id: #{processes.first&.id}"
          message += " with cursor: #{cursor}" if cursor.present?
          messages << message
        end

        chatop_send messages.join("\n")
      end

    chatop :restart_delivery,
      /restart delivery\s+(?<event_ids>\d+(,\s*\d+)*)/,
      "restart delivery [event_ids] - Restart stalled VulnerabilityAlertingEvent deliveries" do
        event_ids = jsonrpc_params.fetch(:event_ids, "").split(",").map(&:strip).map(&:to_i)
        if event_ids.count > 100
          chatop_send "Cannot restart delivery for more than 100 events at a time. Please provide 100 or fewer event ids."
          return
        end

        events = ActiveRecord::Base.connected_to(role: :reading) do
          VulnerabilityAlertingEvent.where(id: event_ids).order(id: :asc).to_a
        end

        messages = []
        missing_events = event_ids - events.map(&:id)
        if missing_events.any?
          messages << "Could not find events with ids: #{missing_events.join(", ")}"
        end

        delivery_not_stalled_events = []
        delivery_restarted_events = []
        delivery_finished_events = []
        events.each do |event|
          if !event.delivery_stalled?
            delivery_not_stalled_events << event
          elsif event.alert_count == 0 && event.notification_count == 0
            event.finished!
            delivery_finished_events << event
          elsif event.alert_count == -1 || event.notification_count == -1 || event.alert_count > 0 || event.notification_count > 0
            TriggerCombinedVulnerabilityAlertEmailsJob.perform_later(event.id)
            delivery_restarted_events << event
          else
            messages << "Delivery was not restarted for event with id: #{event.id}. Alert count: #{event.alert_count}, Notification count: #{event.notification_count}. Use gh-console to manually restart or mark the alerting event complete."
          end
        end

        if delivery_finished_events.any?
          messages << "Marked events as finished (0 alerts, 0 notifications) for event ids: #{delivery_finished_events.map(&:id).join(", ")}"
        end

        if delivery_restarted_events.any?
          messages << "Restarted TriggerCombinedVulnerabilityAlertEmailsJob for event ids: #{delivery_restarted_events.map(&:id).join(", ")}"
        end

        if delivery_not_stalled_events.any?
          messages << "Delivery is not stalled for event ids: #{delivery_not_stalled_events.map(&:id).join(", ")}"
        end

        chatop_send messages.join("\n")
      end

    SEARCH_INDEX_REPAIR_FILTER_TYPES_UNION = Regexp.union(RepairDependabotAlertsIndexJob::FILTERS.keys.map(&:to_s)).source.freeze
    chatop :search_repair,
      /search repair\s+(?<command>start|stop|status|reset)(\s+(?<model_type>#{SEARCH_INDEX_REPAIR_FILTER_TYPES_UNION}))?(\s+(?<id>\d+))?/,
      "search repair <start|stop|status|reset> [<#{SEARCH_INDEX_REPAIR_FILTER_TYPES_UNION}> <id>] [--count <num>] - Execute the search index repair command for Dependabot alerts associated to the specified model" do
        rpc_params = jsonrpc_params.permit(:command, :model_type, :id, :count, :message_id)
        model_type = rpc_params.fetch(:model_type, nil)
        repair_filter_value = rpc_params.fetch(:id, nil)&.to_i
        if model_type.nil? != repair_filter_value.nil?
          chatop_send "Both model type and id are required to run a filtered repair"
          return
        end

        opts = {
          # Args for the repair command method
          command: rpc_params[:command],
          index_name: Elastomer::Indexes::DependabotAlerts.index_name,
          args: [],
        }

        if model_type.present? && repair_filter_value.present?
          # Repair options for the RepairDependabotAlertsIndexJob
          opts[:target_scope] = model_type.to_sym
          opts[:target_scope_id] = repair_filter_value
        end

        if opts[:command] == "start"
          count = rpc_params[:count] || 1
          opts[:args].push(count)
        end

        result = Search::Chatops::RepairIndex.run(**opts)
        chatop_send result
      end

    SEARCH_INDEX_SYNC_TYPES_UNION = Regexp.union(
      Search::DependabotAlerts::BatchUpdateNormalizedDataJob::DependabotAlertsNormalizedDataModels.filter_map(&:name).map(&:underscore)
    ).source.freeze
    chatop :search_sync,
      /search sync(\s+(?<model_type>#{SEARCH_INDEX_SYNC_TYPES_UNION}))?(\s+(?<id>\d+))?/,
      "search sync <#{SEARCH_INDEX_SYNC_TYPES_UNION}> <id> - Sync the reconciliation timestamp and data for Dependabot alerts associated with the specified model. This only performs updates, for a full reconciliation please use .dependabot_alerts search repair instead." do
        rpc_params = jsonrpc_params.permit(:model_type, :id, :message_id)
        if rpc_params.fetch(:model_type, nil).nil? || rpc_params.fetch(:id, nil).nil?
          chatop_send "Both model type and id are required to start a sync"
          return
        end

        # The model type name is required to map to a valid ActiveRecord model class name that's been underscored.
        # That means we should be able to safely classify and constantize it without a case/where or if/elsif chain.
        begin
          model_type = rpc_params.fetch(:model_type).classify.constantize
        rescue NameError
          chatop_send "Cannot find a valid model for type input: #{rpc_params.fetch(:model_type)}"
          return
        end

        id = rpc_params.fetch(:id)&.to_i
        model_to_sync = model_type.find_by(id: id)
        if model_to_sync.nil?
          chatop_send "Could not find #{model_type} with id: #{id}"
          return
        end

        Search::DependabotAlerts::BatchUpdateElasticsearchJob.perform_later(updated_model: model_to_sync)
        chatop_send "Sync has been started for #{model_type} #{id}"
      end

    chatop :epss_sync,
      /epss sync/,
      "epss sync - Download and sync the latest EPSS values from public records" do
        EPSSIngestionJob.perform_later
        chatop_send "EPSS sync has been started"
      end
  end
end
