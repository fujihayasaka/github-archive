# typed: true
# frozen_string_literal: true

require "chatops-controller"
require "github_chatops_extensions"
require "github_chatops_extensions/checks"

module Chatops
  class FastlyController < ApplicationController
    include ::Chatops::Controller
    include ::GitHubChatopsExtensions::Checks::Includable::Entitlements
    include ::GitHubChatopsExtensions::Checks::Includable::Fido
    include ::GitHubChatopsExtensions::Checks::Includable::Room

    SENTRY_QUERY = "is%3Aunresolved+controller%3A%22Chatops%3A%3AFastlyController%22".freeze
    SENTRY_URL = "https://github.sentry.io/issues/?query=#{SENTRY_QUERY}".freeze

    ALLOWED_PURGE_ALL_SERVICES = ["raw"].freeze

    CONTROLLED_ACTIONS = [:"purge-all"].freeze
    CONTROLLED_ACTIONS_GROUP = ["apps/chatops/github-fastly"].freeze
    ALLOWED_ROOMS = [
      "#git-systems-ops",
      "#sre-ops",
      "#support-ops",
      "#support-security-ops",
      "#incident-command",
    ].freeze

    MAGIC_WORDS = %w(
      keqing
      eula
      mercy
      sombra
      sage
      fishsticks
      fade
    ).freeze

    # Bypass CAP for internal only chatops
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

    before_action -> { T.cast(self, Chatops::FastlyController).require_in_room(ALLOWED_ROOMS) }, except: :list
    before_action -> { T.cast(self, Chatops::FastlyController).require_ldap_entitlement(CONTROLLED_ACTIONS_GROUP) }, only: CONTROLLED_ACTIONS
    before_action :require_fido_2fa_with_magic_word, only: CONTROLLED_ACTIONS

    chatops_namespace :fastly
    chatops_help "Commands for working with Fastly"
    chatops_error_response "More information is available [in Sentry](#{SENTRY_URL})"

    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:list]

    chatop(
      :purge,
      /purge (?<url>https:\/\/\S+)/i,
      "purge <url> - Instantly purge the cache for an individual URL.",
    ) do
      params = jsonrpc_params.permit(:url, :message_id)
      fastly.purge!(url: params[:url])
      chatop_send "Successfully purged #{params[:url]}"
    rescue Fastly::CDNPurgeError, Fastly::ValidationError => error
      Failbot.report error
      chatop_send "Something went wrong: #{error.message}"
    end

    chatop(
      :"purge-all",
      /purge-all (?<service_name>[a-zA-Z]+)(?: magic_word=(?<magic_word>[a-zA-Z]+))?/,
      "purge-all <service-name> - Instantly purge the cache for all items in a specific service.",
    ) do
      params = jsonrpc_params.permit(:service_name, :magic_word, :message_id)

      unless ALLOWED_PURGE_ALL_SERVICES.include?(params[:service_name])
        return chatop_send <<-MSG
          Sorry, `#{params[:service_name]}` is not a valid service to purge-all for.
          Service must be one of: #{ALLOWED_PURGE_ALL_SERVICES.join(", ")}.
        MSG
      end

      unless magic_word?(params[:magic_word])
        return chatop_send <<-MSG
          :warning: This will immediately purge the cache for ALL items for this service.

          To make sure we don't do this accidentally, this command requires a magic word.
          Today's magic word is `#{current_magic_word}`.

          To purge eveverything, rerun this command while using the magic word:

          `.fastly purge-all #{params[:service_name]} magic_word=#{current_magic_word}`
        MSG
      end

      service_id = begin
        fastly.service_id_for!(params[:service_name])
      rescue Fastly::FetchServiceError => error
        Failbot.report error
        return chatop_send "Failed to fetch #{params[:service_name]}: #{error.message}"
      end

      fastly.purge_all!(service_id: service_id)
      chatop_send "Successfully purged everything for #{params[:service_name]}"
    rescue Fastly::CDNPurgeError => error
      Failbot.report error
      chatop_send "Something went wrong: #{error.message}"
    end

    private

    def current_magic_word
      MAGIC_WORDS[Time.now.wday]
    end

    def magic_word?(word)
      word == current_magic_word
    end

    memoize def fastly
      Fastly.new
    end

    def require_fido_2fa_with_magic_word
      return unless jsonrpc_params[:magic_word].present?
      require_fido_2fa
    end

    def verify_authenticity_token?
      false # robots do this
    end
  end
end
