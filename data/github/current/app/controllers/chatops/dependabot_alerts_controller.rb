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
        if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
          Repositories.domain.by_id(nwo_or_id)
        else
          Repository.find_by(id: nwo_or_id)
        end
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

    chatop :update_repo,
      /update repo (?<repo>.*)?/,
      "update repo [repo] - Enqueue an UpdateRepositoryVulnerabilityAlertsJob for repo" do
        repo = validate_repo(jsonrpc_params.fetch(:repo))
        if repo.nil?
          chatop_send "Could not find repo: #{jsonrpc_params.fetch(:repo)}"
        else
          UpdateRepositoryVulnerabilityAlertsJob.enqueue_for_repository(repo)
          chatop_send "Enqueued UpdateRepositoryVulnerabilityAlertsJob for: #{repo.name_with_owner}"
        end
      end

    chatop :restart_process,
      /restart process(?:\s+(?<process_id>\S+))(?:\s*(?<cursor>\S+)?)/,
      "restart process [process_id] [cursor] - Restart a stalled VulnerableVersionRangeCreateVulnerabilityAlertsJob with optional cursor" do
        process = VulnerableVersionRangeAlertingProcess.find_by(id: jsonrpc_params.fetch(:process_id))
        cursor = jsonrpc_params.fetch(:cursor, nil)

        if process.nil?
          chatop_send "Could not find process with id: #{jsonrpc_params.fetch(:process_id)}"
        else
          if cursor.present?
            VulnerableVersionRangeCreateVulnerabilityAlertsJob.perform_later(process.id, cursor: cursor)
            chatop_send "Restarted VulnerableVersionRangeCreateVulnerabilityAlertsJob for process id: #{process.id} with cursor: #{cursor}"
          else
            VulnerableVersionRangeCreateVulnerabilityAlertsJob.perform_later(process.id, cursor: nil)
            chatop_send "Restarted VulnerableVersionRangeCreateVulnerabilityAlertsJob for process id: #{process.id}"
          end
        end
      end
  end
end
