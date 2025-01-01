# typed: true
# frozen_string_literal: true

require "chatops-controller"
require "resqued/worker_management"
require "github_chatops_extensions"
require "github_chatops_extensions/checks"

module Chatops
  class ResquedController < ApplicationController
    include ::Chatops::Controller
    include ::GitHubChatopsExtensions::Checks::Includable::Room

    chatops_namespace :resqued
    chatops_help "Commands for managing resqued workers"

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    ALLOWED_ROOMS = %w{
      #data-pipelines-ops
      #dotcom-ops
      #incident-command
    }

    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

    before_action -> { T.cast(self, Chatops::ResquedController).require_in_room(ALLOWED_ROOMS) }, except: :list

    chatop(
      :"stop-workers",
      /stop-workers (?<hostname>[\w\-\.]+)/i,
      "stop-workers <host> - Stop job workers on a given host.",
    ) do
      user = params[:user]
      room_id = params[:room_id]
      permitted = jsonrpc_params.permit(:hostname, :message_id)
      Resqued::WorkerManagement.stop_workers(hostname: permitted[:hostname], user: user, room_id: room_id)
      chatop_send "Initiated worker shutdown on #{permitted[:hostname]}"
    rescue ArgumentError => error
      chatop_send "Failed to stop workers: #{error.message}"
    end

    chatop(
      :"stopped-workers",
      /stopped-workers/i,
      "stopped-workers - List hosts with stopped workers.",
    ) do
      formatted = Resqued::WorkerManagement.stopped_workers.map do |line|
        line.reject { |_, v| v.blank? }.map { |k, v| [k, v.to_s].join("=") }.join(" ")
      end.join("\n")

      if formatted.empty?
        chatop_send "No stopped workers found."
      else
        chatop_send formatted
      end
    end

    chatop(
      :"start-workers",
      /start-workers (?<hostname>[\w\-\.]+)/i,
      "start-workers <hostname> - Start job workers on a given host.",
    ) do
      permitted = jsonrpc_params.permit(:hostname, :message_id)
      Resqued::WorkerManagement.start_workers(hostname: permitted[:hostname])
      chatop_send "Workers on #{permitted[:hostname]} will start during the next deploy."
    rescue ArgumentError => error
      chatop_send "Failed to start workers: #{error.message}"
    end

    private

    def verify_authenticity_token?
      false
    end
  end
end
