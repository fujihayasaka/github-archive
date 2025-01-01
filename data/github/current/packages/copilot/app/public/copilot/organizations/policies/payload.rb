# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module Policies
      class Payload
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
          can_edit_desktop = @organization.feature_enabled?(:copilot_desktop)
          can_edit_editor_preview_features = true
          can_edit_a_chat = true
          can_edit_a_f = @organization.feature_enabled?(:copilot_a_f)
          can_edit_g_chat = true
          can_edit_o1 = true
          can_edit_o3 = true
          can_edit_o_ff = @organization.copilot_plan_enterprise? ? @organization.feature_enabled?(:copilot_o_ff_enterprise) : @organization.feature_enabled?(:copilot_o_ff_business)
          can_edit_o_f = @organization.feature_enabled?(:copilot_o_f)
          can_edit_copilot_for_dotcom = true
          can_edit_dotcom_bing_access = true
          can_edit_user_feedback_opt_in = true
          can_see_copilot_chat_for_dotcom = true
          can_see_copilot_desktop = @organization.feature_enabled?(:copilot_desktop)
          can_see_dotcom_bing_access = !GitHub.multi_tenant_enterprise?
          can_edit_copilot_extensions = true
          can_edit_private_telemetry = true
          can_edit_beta_features_opt_in = true
          can_edit_usage_metrics_policy = false
          can_edit_overages = true
          enterprise_name = T.let(nil, T.nilable(String))
          enterprise_slug = T.let(nil, T.nilable(String))

          can_see_editor_preview_features = @organization.feature_enabled?(:copilot_next_edit_suggestions)
          can_see_a_chat = !GitHub.multi_tenant_enterprise?
          can_see_a_f = !GitHub.multi_tenant_enterprise? && @organization.feature_enabled?(:copilot_a_f)
          can_see_g_chat = !GitHub.multi_tenant_enterprise?
          can_see_o1 = !GitHub.multi_tenant_enterprise?
          can_see_o3 = !GitHub.multi_tenant_enterprise?
          can_see_o_ff = !GitHub.multi_tenant_enterprise? && @organization.copilot_plan_enterprise? ? @organization.feature_enabled?(:copilot_o_ff_enterprise) : @organization.feature_enabled?(:copilot_o_ff_business)
          can_see_o_f = !GitHub.multi_tenant_enterprise? && @organization.feature_enabled?(:copilot_o_f)
          can_see_overages = !GitHub.multi_tenant_enterprise?

          if copilot_business
            # if the business has an explicit policy, this user cannot edit it. So lets check for it.
            can_edit_snippy = copilot_business.no_public_code_suggestions_policy?
            can_edit_editor_chat = copilot_business.no_chat_policy?
            can_edit_mobile_chat = copilot_business.no_mobile_chat_policy?
            can_edit_copilot_for_dotcom = copilot_business.copilot_for_dotcom_no_policy?
            can_edit_dotcom_bing_access = copilot_business.bing_github_chat_no_policy?
            can_edit_user_feedback_opt_in = copilot_business.user_feedback_opt_in_no_policy?
            can_edit_cli = copilot_business.cli_no_policy?
            can_edit_desktop = copilot_business.feature_enabled?(:copilot_desktop) && (copilot_business.desktop_no_policy? || copilot_business.desktop_unconfigured?)
            can_edit_editor_preview_features = copilot_business.editor_preview_features_no_policy? || copilot_business.editor_preview_features_unconfigured?
            can_edit_a_chat = copilot_business.a_chat_no_policy? || copilot_business.a_chat_unconfigured?
            can_edit_a_f = copilot_business.a_f_no_policy? || copilot_business.a_f_unconfigured?
            can_edit_g_chat = copilot_business.g_chat_no_policy? || copilot_business.g_chat_unconfigured?
            can_edit_o1 = copilot_business.o1_no_policy? || copilot_business.o1_unconfigured?
            can_edit_o3 = copilot_business.o3_no_policy? || copilot_business.o3_unconfigured?
            can_edit_o_ff = @organization.copilot_plan_enterprise? ? @organization.feature_enabled?(:copilot_o_ff_enterprise) : @organization.feature_enabled?(:copilot_o_ff_business) && (copilot_business.o_ff_no_policy? || copilot_business.o_ff_unconfigured?)
            can_edit_o_f = copilot_business.o_f_no_policy? || copilot_business.o_f_unconfigured?
            can_edit_copilot_extensions = copilot_business.copilot_extensions_no_policy?
            can_edit_private_telemetry = copilot_business.private_telemetry_no_policy?
            can_edit_usage_metrics_policy = copilot_business.telemetry_aggregation_no_policy?
            can_edit_beta_features_opt_in = copilot_business.beta_features_github_chat_no_policy?
            can_edit_overages = copilot_business.overages_no_policy? || copilot_business.overages_unconfigured?
            enterprise_name = copilot_business.business_object.name
            enterprise_slug = copilot_business.business_object.slug
            can_see_editor_preview_features = copilot_business.feature_enabled?(:copilot_next_edit_suggestions)
            can_see_a_chat = true
            can_see_a_f = copilot_business.feature_enabled?(:copilot_a_f)
            can_see_g_chat = true
            can_see_o3 = true
            can_see_o_ff = @organization.copilot_plan_enterprise? ? @organization.feature_enabled?(:copilot_o_ff_enterprise) : @organization.feature_enabled?(:copilot_o_ff_business)
            can_see_o_f = copilot_business.feature_enabled?(:copilot_o_f)
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
            editor_preview_features: {
              manages: "copilot_editor_preview_features",
              configurable: can_edit_editor_preview_features,
              visible: can_see_editor_preview_features,
              options: make_menu_options([
                # note the unconfigured item is added client-side
                Copilot::Policies::MenuItems::EditorPreviewFeatures::Enabled,
                Copilot::Policies::MenuItems::EditorPreviewFeatures::Disabled,
                Copilot::Policies::MenuItems::EditorPreviewFeatures::NoPolicy,
              ])
            },
            a_chat: {
              manages: "copilot_a_chat",
              configurable: can_edit_a_chat,
              visible: can_see_a_chat,
              options: make_menu_options([
                # note the unconfigured item is added client-side
                Copilot::Policies::MenuItems::AChat::Enabled,
                Copilot::Policies::MenuItems::AChat::Disabled,
                Copilot::Policies::MenuItems::AChat::NoPolicy,
              ])
            },
            a_f: {
              manages: "copilot_a_f",
              configurable: can_edit_a_f,
              visible: can_see_a_f,
              options: make_menu_options([
                # note the unconfigured item is added client-side
                Copilot::Policies::MenuItems::AF::Enabled,
                Copilot::Policies::MenuItems::AF::Disabled,
                Copilot::Policies::MenuItems::AF::NoPolicy,
              ])
            },
            g_chat: {
              manages: "copilot_g_chat",
              configurable: can_edit_g_chat,
              visible: can_see_g_chat,
              options: make_menu_options([
                # note the unconfigured item is added client-side
                Copilot::Policies::MenuItems::GChat::Enabled,
                Copilot::Policies::MenuItems::GChat::Disabled,
                Copilot::Policies::MenuItems::GChat::NoPolicy,
              ])
            },
            o1: {
              manages: "copilot_o1",
              configurable: can_edit_o1,
              visible: can_see_o1,
              options: make_menu_options([
                # note the unconfigured item is added client-side
                Copilot::Policies::MenuItems::O1::Enabled,
                Copilot::Policies::MenuItems::O1::Disabled,
                Copilot::Policies::MenuItems::O1::NoPolicy,
              ])
            },
            o3: {
              manages: "copilot_o3",
              configurable: can_edit_o3,
              visible: can_see_o3,
              options: make_menu_options([
                # note the unconfigured item is added client-side
                Copilot::Policies::MenuItems::O3::Enabled,
                Copilot::Policies::MenuItems::O3::Disabled,
                Copilot::Policies::MenuItems::O3::NoPolicy,
              ])
            },
            o_ff: {
              manages: "copilot_o_ff",
              configurable: can_edit_o_ff,
              visible: can_see_o_ff,
              options: make_menu_options([
                # note the unconfigured item is added client-side
                Copilot::Policies::MenuItems::OFf::Enabled,
                Copilot::Policies::MenuItems::OFf::Disabled,
                Copilot::Policies::MenuItems::OFf::NoPolicy,
              ])
            },
            o_f: {
              manages: "copilot_o_f",
              configurable: can_edit_o_f,
              visible: can_see_o_f,
              options: make_menu_options([
                # note the unconfigured item is added client-side
                Copilot::Policies::MenuItems::OF::Enabled,
                Copilot::Policies::MenuItems::OF::Disabled,
                Copilot::Policies::MenuItems::OF::NoPolicy,
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
            desktop: {
              manages: "desktop",
              configurable: can_edit_desktop,
              visible: can_see_copilot_desktop,
              options: make_menu_options([
                Copilot::Policies::MenuItems::Desktop::Enabled,
                Copilot::Policies::MenuItems::Desktop::Disabled,
              ])
            },
            copilot_for_dotcom: {
              manages: "copilot_for_dotcom",
              configurable: can_edit_copilot_for_dotcom,
              visible: can_see_copilot_chat_for_dotcom,
              options: make_menu_options([
                Copilot::Policies::MenuItems::CopilotForDotcom::Enabled,
                Copilot::Policies::MenuItems::CopilotForDotcom::Disabled,
              ])
            },
            bing_github_chat: {
              manages: "bing_github_chat",
              configurable: can_edit_dotcom_bing_access,
              visible: can_see_dotcom_bing_access,
              options: make_menu_options([
                Copilot::Policies::MenuItems::BingGitHubChat::Enabled,
                Copilot::Policies::MenuItems::BingGitHubChat::Disabled,
              ])
            },
            copilot_user_feedback_opt_in: {
              manages: "copilot_user_feedback_opt_in",
              configurable: can_edit_user_feedback_opt_in,
              visible: can_see_copilot_chat_for_dotcom,
              enabled: @organization.user_feedback_opt_in_enabled?,
            },
            copilot_beta_features_opt_in: {
              manages: "copilot_beta_features_opt_in",
              configurable: can_edit_beta_features_opt_in,
              visible: true,
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
              visible: true,
              options: make_menu_options([
                Copilot::Policies::MenuItems::UsageTelemetryAggregation::Enabled,
                Copilot::Policies::MenuItems::UsageTelemetryAggregation::Disabled,
              ])
            },
            overages: {
              manages: "copilot_overages",
              configurable: can_edit_overages,
              visible: can_see_overages,
              options: make_menu_options([
                # note the unconfigured item is added client-side
                Copilot::Policies::MenuItems::Overages::Enabled,
                Copilot::Policies::MenuItems::Overages::Disabled,
                Copilot::Policies::MenuItems::Overages::NoPolicy,
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
