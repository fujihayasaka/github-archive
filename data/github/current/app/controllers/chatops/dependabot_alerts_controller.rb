# typed: true
# frozen_string_literal: true

require "chatops-controller"
require "github_chatops_extensions"

module Chatops
  class DependabotAlertsController < ApplicationController
    include ::Chatops::Controller
    include ::GitHubChatopsExtensions::Checks::Includable::Room

    ALLOWED_ROOMS = ["#dependabot-ops", "#incident-command"].freeze

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

    def validate_repo(nwo_or_id) # rubocop:todo GitHub/UseRestfulActions
      repo = if /\A[0-9]+\Z/.match(nwo_or_id)
        Repositories.domain.by_id(nwo_or_id)
      else
        Repository.nwo(nwo_or_id)
      end
      repo.present? && repo
    end

    chatop :list_stalled,
      /list stalled/,
      "list stalled - list out stalled alerting processes" do
        stalled_events = ActiveRecord::Base.connected_to(role: :reading) { VulnerabilityAlertingEvent.where(processed_at: nil, reason: :on_process_alerts).to_a.select(&:processing_stalled?) }
        stalled_processes = ActiveRecord::Base.connected_to(role: :reading) { stalled_events.flat_map(&:vulnerable_version_range_alerting_processes).select(&:processing_stalled?) }

        if stalled_processes.empty?
          chatop_send "No stalled alerting processes found"
        else
          chatop_send "Stalled alerting process ids: #{stalled_processes.map(&:id).join(", ")}"
        end
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
        events.each do |event|
          if !event.delivery_stalled?
            delivery_not_stalled_events << event
          elsif event.alert_count == -1 || event.notification_count == -1
            TriggerCombinedVulnerabilityAlertEmailsJob.perform_later(event.id)
            delivery_restarted_events << event
          else
            messages << "Delivery was not restarted for event with id: #{event.id}. Alert count: #{event.alert_count}, Notification count: #{event.notification_count}. Use gh-console to manually restart or mark the alerting event complete."
          end
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

        Search::DependabotAlerts::BatchUpdateReconciliationTimestampJob.perform_later(updated_model: model_to_sync)
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
