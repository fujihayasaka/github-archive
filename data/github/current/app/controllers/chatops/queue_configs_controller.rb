# typed: true
# frozen_string_literal: true

require "chatops-controller"
require "github_chatops_extensions"
require "github_chatops_extensions/checks"

module Chatops
  class QueueConfigsController < ApplicationController
    include ::Chatops::Controller
    include ::GitHubChatopsExtensions::Checks::Includable::Room

    chatops_namespace :queue_configs
    chatops_help "Commands for retrieving Background Job Queue configs"

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    ALLOWED_ROOMS = %w{
      #data-pipelines-ops
      #dotcom-ops
      #incident-command
    }

    ALLOWED_ENVIRONMENTS = %w{
      dotcom
      proxima
      enterprise
      staff
      development
    }

    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

    before_action -> { T.cast(self, Chatops::QueueConfigsController).require_in_room(ALLOWED_ROOMS) }, except: :list

    chatop(
      :"all",
      /all/i,
      "all - Gets all the job queues configured in the monolith.",
    ) do
      queue_config_keys = BackgroundJobQueues.queue_configurations.keys
      chatop_send print_queue_list(queue_config_keys)
    end

    chatop(
      :"environment",
      /environment (?<environment>[\w\-\.]+)/i,
      "environment <dotcom|development|staff|enterprise|proxima> - Gets the queues for a certain environment in the monolith.",
    ) do
      rpc_params = jsonrpc_params.permit(:environment, :message_id)
      config_environment = rpc_params.fetch(:environment, "")

      if ALLOWED_ENVIRONMENTS.include?(config_environment)
        queue_config_keys = BackgroundJobQueues.queue_configurations_for_environment(environment: config_environment.to_sym).keys
        chatop_send print_queue_list(queue_config_keys)
      else
        chatop_send "Environment \"#{config_environment}\" is not valid. Try one of the following: [#{ALLOWED_ENVIRONMENTS.join(",")}]"
      end
    rescue ArgumentError => error
      chatop_send "Failed to get queue configurations: #{error.message}"
    end

    chatop(
      :"queue",
      /queue (?<queue>.+)/i,
      "queue <queue_name> - Gets the config for a specific queue name.",
    ) do
      rpc_params = jsonrpc_params.permit(:queue, :message_id)
      queue = rpc_params.fetch(:queue)

      queue_config = BackgroundJobQueues.queue_configurations[queue]
      if queue_config.nil?
        chatop_send "Queue [#{queue}] does not exist in the monolith."
      else
        chatop_send JSON.pretty_generate(queue_config)
      end
    rescue ArgumentError => error
      chatop_send "Failed to get queue configurations: #{error.message}"
    end

    private

    def verify_authenticity_token?
      false # robots do this
    end

    def print_queue_list(queue_list = [])
      "There are no queues for this environment" if queue_list.size == 0
      queue_list.join("\n")
    end
  end
end
