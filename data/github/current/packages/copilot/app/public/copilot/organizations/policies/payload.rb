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
          can_edit_a_f = true
          can_edit_afos = @organization.feature_enabled?(:copilot_afos)
          can_edit_al = false
          can_edit_g_chat = true
          can_edit_g_tf = @organization.feature_enabled?(:copilot_g_tf)
          can_edit_gtff = @organization.feature_enabled?(:copilot_gtff)
          can_edit_o1 = true
          can_edit_o3 = true
          can_edit_o_ff = @organization.copilot_plan_enterprise? ? @organization.feature_enabled?(:copilot_o_ff_enterprise) : @organization.feature_enabled?(:copilot_o_ff_business)
          can_edit_o_fm = @organization.feature_enabled?(:copilot_o_fm)
          can_edit_o_f = @organization.feature_enabled?(:copilot_o_f)
          can_edit_o_t = @organization.feature_enabled?(:copilot_o_t)
          can_edit_ofo = @organization.feature_enabled?(:copilot_api_force_legacy_base_chat_model)
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
          can_edit_swe_agent = true
          can_edit_mcp = true
          enterprise_name = T.let(nil, T.nilable(String))
          enterprise_slug = T.let(nil, T.nilable(String))

          can_see_editor_preview_features = @organization.feature_enabled?(:copilot_next_edit_suggestions)
          can_see_a_chat = true
          can_see_a_f = true
          can_see_afos = @organization.feature_enabled?(:copilot_afos)
          can_see_al = @organization.copilot_plan_enterprise? && @organization.feature_enabled?(:copilot_al)
          can_see_g_chat = true
          can_see_g_tf = @organization.feature_enabled?(:copilot_g_tf)
          can_see_gtff = @organization.feature_enabled?(:copilot_gtff)
          can_see_o1 = true
          can_see_o3 = true
          can_see_o_ff = @organization.copilot_plan_enterprise? ? @organization.feature_enabled?(:copilot_o_ff_enterprise) : @organization.feature_enabled?(:copilot_o_ff_business)
          can_see_o_fm = @organization.feature_enabled?(:copilot_o_fm)
          can_see_o_f = @organization.feature_enabled?(:copilot_o_f)
          can_see_o_t = @organization.copilot_plan_enterprise? && @organization.feature_enabled?(:copilot_o_t)
          can_see_ofo = @organization.feature_enabled?(:copilot_api_force_legacy_base_chat_model)
          can_see_overages = !GitHub.multi_tenant_enterprise?
          can_see_swe_agent = false # Only show if enabled for enterprise (below)
          can_see_mcp = false # Only show if enabled for enterprise (below)

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
            can_edit_afos = @organization.feature_enabled?(:copilot_afos) && (copilot_business.afos_no_policy? || copilot_business.afos_unconfigured?)
            can_edit_al = @organization.feature_enabled?(:copilot_al) && (copilot_business.al_no_policy? || copilot_business.al_unconfigured?)
            can_edit_g_chat = copilot_business.g_chat_no_policy? || copilot_business.g_chat_unconfigured?
            can_edit_g_tf = @organization.feature_enabled?(:copilot_g_tf) && (copilot_business.g_tf_no_policy? || copilot_business.g_tf_unconfigured?)
            can_edit_gtff = @organization.feature_enabled?(:copilot_gtff) && (copilot_business.gtff_no_policy? || copilot_business.gtff_unconfigured?)
            can_edit_o1 = copilot_business.o1_no_policy? || copilot_business.o1_unconfigured?
            can_edit_o3 = copilot_business.o3_no_policy? || copilot_business.o3_unconfigured?
            can_edit_o_ff = @organization.copilot_plan_enterprise? ? @organization.feature_enabled?(:copilot_o_ff_enterprise) : @organization.feature_enabled?(:copilot_o_ff_business) && (copilot_business.o_ff_no_policy? || copilot_business.o_ff_unconfigured?)
            can_edit_o_fm = @organization.feature_enabled?(:copilot_o_fm) && (copilot_business.o_fm_no_policy? || copilot_business.o_fm_unconfigured?)
            can_edit_o_f = copilot_business.o_f_no_policy? || copilot_business.o_f_unconfigured?
            can_edit_o_t = @organization.feature_enabled?(:copilot_o_t) && (copilot_business.o_t_no_policy? || copilot_business.o_t_unconfigured?)
            can_edit_ofo = @organization.feature_enabled?(:copilot_api_force_legacy_base_chat_model) && (copilot_business.ofo_no_policy? || copilot_business.ofo_unconfigured?)
            can_edit_copilot_extensions = copilot_business.copilot_extensions_no_policy?
            can_edit_private_telemetry = copilot_business.private_telemetry_no_policy?
            can_edit_usage_metrics_policy = copilot_business.telemetry_aggregation_no_policy?
            can_edit_beta_features_opt_in = copilot_business.beta_features_github_chat_no_policy?
            can_edit_overages = copilot_business.overages_no_policy? || copilot_business.overages_unconfigured?
            can_edit_swe_agent = copilot_business.swe_agent_no_policy?
            can_edit_mcp = copilot_business.mcp_no_policy?
            enterprise_name = copilot_business.business_object.name
            enterprise_slug = copilot_business.business_object.slug
            can_see_editor_preview_features = copilot_business.feature_enabled?(:copilot_next_edit_suggestions)
            can_see_o_ff = @organization.copilot_plan_enterprise? ? @organization.feature_enabled?(:copilot_o_ff_enterprise) : @organization.feature_enabled?(:copilot_o_ff_business)
            can_see_o_f = copilot_business.feature_enabled?(:copilot_o_f)
            can_see_swe_agent = !GitHub.multi_tenant_enterprise? && @organization.copilot_plan_enterprise?
            can_see_mcp = !GitHub.multi_tenant_enterprise? && @organization.copilot_plan_enterprise?
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
            automatic_code_review: {
              manages: "automatic_code_review",
              configurable: false,
              visible: false,
              options: make_menu_options([])
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
            # note the unconfigured item is added client-side
            a_f: if @organization.feature_enabled?(:copilot_policy_form_refactor)
                   {
                      manages: "copilot_a_f",
                      configurable: can_edit_a_f,
                      visible: can_see_a_f,
                      helpurl: Copilot::COPILOT_A_CHAT_DOCS,
                      helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_A_F}.",
                      description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_A_F} model.",
                      displayname: "#{Copilot::COPILOT_A_F} in Copilot",
                      options: [
                        Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: @organization.a_f_enabled?),
                        Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: @organization.a_f_disabled?),
                        Copilot::Policies::MenuItems::GeneralPolicies::NoPolicy.new(copilot_configurable: @organization, checked: @organization.a_f_no_policy?),
                      ].map(&:to_h).compact,
                      preview: !@organization.feature_enabled?(:af_ga),
                    }
                 else
                   {
                      manages: "copilot_a_f",
                      configurable: can_edit_a_f,
                      visible: can_see_a_f,
                      options: make_menu_options([
                        # note the unconfigured item is added client-side
                        Copilot::Policies::MenuItems::AF::Enabled,
                        Copilot::Policies::MenuItems::AF::Disabled,
                        Copilot::Policies::MenuItems::AF::NoPolicy,
                      ])
                    }
                 end,
            a_chat_ga: @organization.feature_enabled?(:a_chat_ga),
            a_f_ga: @organization.feature_enabled?(:af_ga),
            afos:  {
              manages: "copilot_afos",
              configurable: can_edit_afos,
              visible: can_see_afos,
              helpurl: Copilot::COPILOT_AFOS_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_AFOS}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_AFOS} model.",
              displayname: "#{Copilot::COPILOT_AFOS} in Copilot",
              options: [
                Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: @organization.afos_enabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: @organization.afos_disabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::NoPolicy.new(copilot_configurable: @organization, checked: @organization.afos_no_policy?),
              ].map(&:to_h).compact,
              preview: true,
            },
            al:  {
              manages: "copilot_al",
              configurable: can_edit_al,
              visible: can_see_al,
              helpurl: Copilot::COPILOT_AL_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_AL}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_AL} model.",
              displayname: "#{Copilot::COPILOT_AL} in Copilot",
              options: [
                Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: @organization.al_enabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: @organization.al_disabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::NoPolicy.new(copilot_configurable: @organization, checked: @organization.al_no_policy?),
              ].map(&:to_h).compact,
              preview: true,
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
            g_chat_ga: @organization.feature_enabled?(:g_chat_ga),
            g_tf:  {
              manages: "copilot_g_tf",
              configurable: can_edit_g_tf,
              visible: can_see_g_tf,
              helpurl: Copilot::COPILOT_G_TF_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_G_TF}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_G_TF} model.",
              displayname: "#{Copilot::COPILOT_G_TF} in Copilot",
              options: [
                Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: @organization.g_tf_enabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: @organization.g_tf_disabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::NoPolicy.new(copilot_configurable: @organization, checked: @organization.g_tf_no_policy?),
              ].map(&:to_h).compact,
              preview: true,
            },
            gtff:  {
              manages: "copilot_gtff",
              configurable: can_edit_gtff,
              visible: can_see_gtff,
              helpurl: Copilot::COPILOT_GTFF_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_GTFF}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_GTFF} model.",
              displayname: "#{Copilot::COPILOT_GTFF} in Copilot",
              options: [
                Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: @organization.gtff_enabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: @organization.gtff_disabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::NoPolicy.new(copilot_configurable: @organization, checked: @organization.gtff_no_policy?),
              ].map(&:to_h).compact,
              preview: true,
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
            o3_mini_ga: @organization.feature_enabled?(:o3_mini_ga),
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
            o_fm:  {
              manages: "copilot_o_fm",
              configurable: can_edit_o_fm,
              visible: can_see_o_fm,
              helpurl: Copilot::COPILOT_O_FM_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_O_FM}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_O_FM} model.",
              displayname: "#{Copilot::COPILOT_O_FM} in Copilot",
              options: [
                Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: @organization.o_fm_enabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: @organization.o_fm_disabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::NoPolicy.new(copilot_configurable: @organization, checked: @organization.o_fm_no_policy?),
              ].map(&:to_h).compact,
              preview: true,
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
            o_t:  {
              manages: "copilot_o_t",
              configurable: can_edit_o_t,
              visible: can_see_o_t,
              helpurl: Copilot::COPILOT_O_T_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_O_T}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_O_T} model.",
              displayname: "#{Copilot::COPILOT_O_T} in Copilot",
              options: [
                Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: @organization.o_t_enabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: @organization.o_t_disabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::NoPolicy.new(copilot_configurable: @organization, checked: @organization.o_t_no_policy?),
              ].map(&:to_h).compact,
              preview: true,
            },
            ofo:  {
              manages: "copilot_ofo",
              configurable: can_edit_ofo,
              visible: can_see_ofo,
              helpurl: Copilot::COPILOT_OFO_DOCS,
              helptext: "Learn more about how GitHub Copilot serves #{Copilot::COPILOT_OFO}.",
              description: "If enabled, members of this organization will have access to the latest #{Copilot::COPILOT_OFO} model.",
              displayname: "#{Copilot::COPILOT_OFO} in Copilot",
              options: [
                Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: @organization.ofo_enabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: @organization.ofo_disabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::NoPolicy.new(copilot_configurable: @organization, checked: @organization.ofo_no_policy?),
              ].map(&:to_h).compact,
              preview: true,
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
            mcp:  {
              manages: "copilot_mcp",
              configurable: can_edit_mcp,
              visible: can_see_mcp,
              helpurl: "https://gh.io/copilotmcp",
              helptext: "Learn more.",
              description: "If enabled, users can configure and use third-party Model Context Protocols (MCPs) for use on GitHub.com.",
              displayname: Copilot::COPILOT_MCP_SERVERS,
              options: [
                Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: @organization.mcp_enabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: @organization.mcp_disabled?),
              ].map(&:to_h).compact,
              preview: true,
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
            swe_agent:  {
              manages: "copilot_swe_agent",
              configurable: can_edit_swe_agent,
              visible: can_see_swe_agent,
              helpurl: "https://gh.io/assigncopilot",
              helptext: "Learn more.",
              description: "If enabled, users assigned a Copilot license from this organization will have access to #{Copilot::COPILOT_SWE_AGENT} in repositories where it is enabled. This feature may use models which are not enabled on your Models settings page.",
              displayname: "#{Copilot::COPILOT_SWE_AGENT} access",
              options: [
                Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: @organization.swe_agent_enabled?),
                Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: @organization.swe_agent_disabled?),
              ].map(&:to_h).compact,
              preview: true,
            },
            # TODO: mocking Spark data until the necessary DB migrations for Spark organization policies are complete
            spark: {
              manages: "spark",
              configurable: true,
              visible: true,
              helpurl: "https://gh.io/responsible-use-of-github-spark", # TODO: what's the final Spark help URL?
              helptext: "Learn more about Spark",
              displayname: "Spark", # TODO: does this need to be dynamic?
              description: "If enabled, members of your enterprise will have access to Spark.",
              options: [
                Copilot::Policies::MenuItems::GeneralPolicies::Enabled.new(copilot_configurable: @organization, checked: true), # TODO: replace with @organization.spark_enabled? when the DB migrations are complete
                Copilot::Policies::MenuItems::GeneralPolicies::Disabled.new(copilot_configurable: @organization, checked: false), # TODO: replace with @organization.spark_disabled? when the DB migrations are complete
              ].map(&:to_h).compact,
              preview: true,
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
