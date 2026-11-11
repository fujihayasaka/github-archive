# typed: strict
# frozen_string_literal: true

require "chatops-controller"
require "github_chatops_extensions"

module Chatops
  class SecurityConfigurationsController < ApplicationController
    include ::Chatops::Controller
    include ::GitHubChatopsExtensions::Checks::Includable::Room

    # CAP isn't required on ChatOps controllers:
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
    skip_around_action :limit_concurrent_requests

    ALLOWED_ROOMS = T.let(["#security-products-enablement-ops"].freeze, T::Array[String])
    before_action -> { T.bind(self, Chatops::SecurityConfigurationsController); require_in_room(ALLOWED_ROOMS) }, except: :list

    chatops_namespace :security_configurations
    chatops_help "Commands for working with GitHub Security Configurations"

    chatop :show, /show (?<id>\d+)/, "show <id> - View details about a Security Configuration" do
      id = jsonrpc_params.require(:id)

      security_configuration = begin
        SecurityConfiguration.find(id)
      rescue ActiveRecord::RecordNotFound
        chatop_send("Security Configuration with ID #{id} not found.")
        return
      end

      if security_configuration.global?
        target = "Global (0)"
      else
        if security_configuration.target.is_a?(Business)
          slug = security_configuration.target.slug
          stafftools_url = "https://admin.github.com/stafftools/enterprises/#{slug}"
        else
          slug = security_configuration.target.login
          stafftools_url = "https://admin.github.com/stafftools/users/#{slug}"
        end

        target = "[#{slug}](#{stafftools_url}) (#{security_configuration.target_id})"
      end

      feature_states = (SecurityConfiguration::ALL_FEATURES.sort - [:enable_ghas]).map do |feat|
        "*#{feat.to_s.titleize}:* #{security_configuration[feat]}"
      end

      chatop_send <<~EOS
        :spg: *Security Configuration* (#{security_configuration.id})
        *Name:* #{security_configuration.name}
        *Target:* #{target}
        *Type:* #{security_configuration.type == "UnbundledSecurityConfiguration" ? "Unbundled" : "Bundled"}
        *Enable (bundled) GHAS?* #{security_configuration.enable_ghas}
        *Code Security SKU enabled?* #{security_configuration.code_security_sku_enabled}
        *Secret Protection SKU enabled?* #{security_configuration.secret_protection_sku_enabled}
        #{feature_states.join("\n")}
      EOS
    end

    chatop :bundle, /bundle (?<id>\d+)/, "bundle <id> - Transition a Security Configuration from unbundled (SKU split) to bundled" do
      id = jsonrpc_params.require(:id)

      security_configuration = begin
        ::UnbundledSecurityConfiguration.find(id)
      rescue ActiveRecord::RecordNotFound
        chatop_send("Unbundled Security Configuration with ID #{id} not found.")
        return
      end

      log_context = {
        "code.function": "bundle",
        "gh.security_configuration.id": id,
      }

      begin
        security_configuration.bundle!
        log_action("Bundled configuration", log_context)
        chatop_send("Bundled config!")
      rescue ArgumentError, ActiveRecord::ActiveRecordError => e
        Failbot.report(e, log_context)
        chatop_send("Something went wrong: #{e.message}")
      end
    end

    chatop :unbundle, /unbundle (?<id>\d+)/, "unbundle <id> - Transition a Security Configuration from bundled to unbundled (SKU split)" do
      id = jsonrpc_params.require(:id)

      security_configuration = begin
        ::SecurityConfiguration.find(id)
      rescue ActiveRecord::RecordNotFound
        chatop_send("Security Configuration with ID #{id} not found.")
        return
      end

      log_context = {
        "code.function": "unbundle",
        "gh.security_configuration.id": id,
      }

      begin
        security_configuration.unbundle!
        log_action("Unbundled configuration", log_context)
        chatop_send("Unbundled config!")
      rescue ArgumentError, ActiveRecord::ActiveRecordError => e
        Failbot.report(e, log_context)
        chatop_send("Something went wrong: #{e.message}")
      end
    end

    private

    sig { returns(T::Boolean) }
    def verify_authenticity_token?
      false # robots do this
    end

    sig { params(message: String, context: T::Hash[T.untyped, T.untyped]).void }
    def log_action(message, context = {})
      GitHub.logger.info(message, context.merge({
        "code.namespace": "Chatops::SecurityConfigurationsController",
        "gh.actor": params[:user],
      }))
    end
  end
end
