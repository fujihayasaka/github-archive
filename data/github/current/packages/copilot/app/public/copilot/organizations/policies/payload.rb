# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Policies
      class Payload
        extend T::Sig
        include GitHub::Memoizer
        include DocsUrlHelper

        sig { params(organization: ::Copilot::Organization, user: ::User).void }
        def initialize(organization:, user:)
          @organization = organization
          @user = user
        end

        sig { returns(Copilot::Types::PoliciesIndexPayload) }
        def call
          copilot_business = @organization.copilot_business

          can_edit_snippy = true
          can_edit_editor_chat = true
          can_edit_mobile_chat = true
          can_edit_cli = true
          can_edit_copilot_for_dotcom = true
          can_edit_dotcom_bing_access = true
          can_edit_user_feedback_opt_in = true
          can_see_copilot_enterprise = false
          can_edit_copilot_extensions = true
          can_edit_private_telemetry = true
          can_edit_beta_features_opt_in = true
          can_edit_usage_metrics_policy = false
          enterprise_name = T.let(nil, T.nilable(String))
          enterprise_slug = T.let(nil, T.nilable(String))

          if copilot_business
            # if the business has an explicit policy, this user cannot edit it. So lets check for it.
            can_edit_snippy = copilot_business.no_public_code_suggestions_policy?
            can_edit_editor_chat = copilot_business.no_chat_policy?
            can_edit_mobile_chat = copilot_business.no_mobile_chat_policy?
            can_edit_copilot_for_dotcom = copilot_business.copilot_for_dotcom_no_policy?
            can_edit_dotcom_bing_access = copilot_business.bing_github_chat_no_policy?
            can_edit_user_feedback_opt_in = copilot_business.user_feedback_opt_in_no_policy?
            can_edit_cli = copilot_business.cli_no_policy?
            can_see_copilot_enterprise = copilot_business.has_copilot_enterprise_access? || @organization.copilot_plan_enterprise? || (@organization.business_trial&.copilot_plan_enterprise? && @organization.business_trial&.has_trial?)
            can_edit_copilot_extensions = copilot_business.copilot_extensions_no_policy?
            can_edit_private_telemetry = copilot_business.private_telemetry_no_policy?
            can_edit_usage_metrics_policy = copilot_business.telemetry_aggregation_no_policy?
            can_edit_beta_features_opt_in = copilot_business.beta_features_github_chat_no_policy?
            enterprise_name = copilot_business.business_object.name
            enterprise_slug = copilot_business.business_object.slug
          else
            can_edit_usage_metrics_policy = true
          end

          {
            org_name: @organization.__getobj__.display_login,
            copilot_plan: @organization.copilot_plan,
            enterprise_name: enterprise_name,
            enterprise_slug: enterprise_slug,
            editor_chat: {
              manages: "copilot_editor_chat_enabled",
              configurable: can_edit_editor_chat,
              visible: nil,
              options: make_menu_options([
                # note the unconfigured item is added client-side
                Copilot::Policies::MenuItems::EditorChat::Enabled,
                Copilot::Policies::MenuItems::EditorChat::Disabled,
                Copilot::Policies::MenuItems::EditorChat::NoPolicy,
              ])
            },
            mobile_chat: {
              manages: "copilot_mobile_chat",
              configurable: can_edit_mobile_chat,
              visible: nil,
              options: make_menu_options([
                # note the unconfigured item is added client-side
                Copilot::Policies::MenuItems::MobileChat::Enabled,
                Copilot::Policies::MenuItems::MobileChat::Disabled,
                Copilot::Policies::MenuItems::MobileChat::NoPolicy,
              ])
            },
            snippy: {
              manages: "copilot_public_code_suggestions",
              configurable: can_edit_snippy,
              visible: nil,
              options: make_menu_options([
                # note the unconfigured item is added client-side
                Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed,
                Copilot::Policies::MenuItems::PublicCodeSuggestions::Blocked,
                Copilot::Policies::MenuItems::PublicCodeSuggestions::NoPolicy,
              ])
            },
            cli: {
              manages: "cli",
              configurable: can_edit_cli,
              visible: nil,
              options: make_menu_options([
                Copilot::Policies::MenuItems::Cli::Enabled,
                Copilot::Policies::MenuItems::Cli::Disabled,
              ])
            },
            copilot_for_dotcom: {
              manages: "copilot_for_dotcom",
              configurable: can_edit_copilot_for_dotcom,
              visible: can_see_copilot_enterprise,
              options: make_menu_options([
                Copilot::Policies::MenuItems::CopilotForDotcom::Enabled,
                Copilot::Policies::MenuItems::CopilotForDotcom::Disabled,
              ])
            },
            bing_github_chat: {
              manages: "bing_github_chat",
              configurable: can_edit_dotcom_bing_access,
              visible: can_see_copilot_enterprise,
              options: make_menu_options([
                Copilot::Policies::MenuItems::BingGitHubChat::Enabled,
                Copilot::Policies::MenuItems::BingGitHubChat::Disabled,
              ])
            },
            copilot_user_feedback_opt_in: {
              manages: "copilot_user_feedback_opt_in",
              configurable: can_edit_user_feedback_opt_in,
              visible: can_see_copilot_enterprise,
              enabled: @organization.user_feedback_opt_in_enabled?,
            },
            copilot_beta_features_opt_in: {
              manages: "copilot_beta_features_opt_in",
              configurable: can_edit_beta_features_opt_in,
              visible: can_see_copilot_enterprise,
              enabled: @organization.beta_features_github_chat_enabled?,
            },
            copilot_extensions: {
              manages: "copilot_extensions",
              configurable: can_edit_copilot_extensions,
              visible: nil,
              options: make_menu_options([
                Copilot::Policies::MenuItems::CopilotExtensions::Enabled,
                Copilot::Policies::MenuItems::CopilotExtensions::Disabled,
              ])
            },
            private_telemetry: {
              manages: "private_telemetry",
              configurable: can_edit_private_telemetry,
              visible: nil,
              options: make_menu_options([
                Copilot::Policies::MenuItems::PrivateTelemetry::Allowed,
                Copilot::Policies::MenuItems::PrivateTelemetry::Blocked,
              ])
            },
            copilot_usage_metrics_policy: {
              manages: "copilot_usage_metrics_policy",
              configurable: can_edit_usage_metrics_policy,
              visible: @organization.feature_enabled?(:copilot_usage_metrics_policy),
              options: make_menu_options([
                Copilot::Policies::MenuItems::UsageTelemetryAggregation::Enabled,
                Copilot::Policies::MenuItems::UsageTelemetryAggregation::Disabled,
              ])
            },
            docsUrls: {
              generalPrivacyStatement: DocsUrlConfig.url_for("site-policy/github-general-privacy-statement"),
            }
          }
        end

        private

        sig do params(items: T::Array[T.class_of(Copilot::Policies::MenuItems::Base)])
          .returns(T::Array[Copilot::Types::MenuItemHashType])
        end
        def make_menu_options(items)
          items.map do |menu_item|
            menu_item.new(copilot_configurable: @organization).to_h
          end.compact
        end
      end
    end
  end
end
