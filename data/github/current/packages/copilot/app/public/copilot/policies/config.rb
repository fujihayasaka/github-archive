# typed: strict
# frozen_string_literal: true

class Copilot::Policies::Config
  extend T::Helpers

  abstract!

  POLICIES = T.let({
    a_chat: {
      business_controller_param: "copilot_a_chat",
      org_controller_param: "copilot_a_chat",
      user_controller_param: "a_chat",
      display_name: "Anthropic Claude 3.5 Sonnet in Copilot setting"
    },
    a_f: {
      business_controller_param: "copilot_a_f",
      org_controller_param: "copilot_a_f",
      user_controller_param: "a_f",
      display_name: "Anthropic Claude 3.7 Sonnet in Copilot setting"
    },
    beta_features_github_chat: {
      business_controller_param: "copilot_beta_features_opt_in",
      org_controller_param: "copilot_beta_features_opt_in",
      display_name: "Preview features for Copilot in GitHub.com setting"
    },
    bing_github_chat: {
      business_controller_param: "bing_github_chat",
      org_controller_param: "bing_github_chat",
      user_controller_param: "copilot_policy_bing",
      display_name: "Bing access for Copilot in GitHub.com setting"
    },
    chat_enabled: {
      business_controller_param: "copilot_editor_chat_enabled",
      org_controller_param: "copilot_editor_chat_enabled",
      display_name: "Copilot Chat in the IDE setting"
    },
    cli: {
      business_controller_param: "cli",
      org_controller_param: "cli",
      display_name: "Copilot in the CLI setting"
    },
    copilot_enabled: {}, # not used as a normal policy
    copilot_extensions: {
      business_controller_param: "copilot_extensions",
      org_controller_param: "copilot_extensions",
      display_name: "Copilot extensions setting"
    },
    copilot_plan: {},
    custom_models: {
      business_controller_param: "copilot_custom_models",
      display_name: "Copilot fine-tuning setting"
    },
    desktop: {
      business_controller_param: "desktop",
      org_controller_param: "desktop",
      display_name: "#{Copilot::COPILOT_DESKTOP} setting"
    },
    dotcom_chat: {
      business_controller_param: "copilot_for_dotcom",
      display_name: "Copilot in GitHub.com setting"
    }, # enabled from copilot_for_dotcom_enabled! with pr_summarizations
    editor_preview_features: {
      business_controller_param: "copilot_editor_preview_features",
      org_controller_param: "copilot_editor_preview_features",
      user_controller_param: "editor_preview_features",
      display_name: "Editor preview features setting"
    },
    g_chat: {
      business_controller_param: "copilot_g_chat",
      org_controller_param: "copilot_g_chat",
      user_controller_param: "g_chat",
      display_name: "Google Gemini 2.0 Flash in Copilot setting"
    },
    github_enterprise_feature_group: {},
    ide_chat: {}, # looks like not called anywhere?
    max_seats: {}, # only used in stafftools
    mobile_chat: {
      business_controller_param: "copilot_mobile_chat",
      org_controller_param: "copilot_mobile_chat",
      display_name: "Copilot Chat in GitHub Mobile setting"
    },
    o1: {
      business_controller_param: "copilot_o1",
      org_controller_param: "copilot_o1",
      user_controller_param: "o1",
      display_name: "OpenAI o1 models in Copilot setting"
    },
    o3: {
      business_controller_param: "copilot_o3",
      org_controller_param: "copilot_o3",
      user_controller_param: "o3",
      display_name: "OpenAI o3 models in Copilot setting"
    },
    o_f: {
      business_controller_param: "copilot_o_f",
      org_controller_param: "copilot_o_f",
      user_controller_param: "o_f",
      display_name: "TEMP COPILOT O_F"
    },
    o_ff: {
      business_controller_param: "copilot_o_ff",
      org_controller_param: "copilot_o_ff",
      user_controller_param: "o_ff",
      display_name: "OpenAI GPT-4.5 model in Copilot setting"
    },
    pending_plan_downgrade_date: {}, # used when downgrading or when enabling or disabling
    pr_diff_chats: {}, # doesn't look like it is used anywhere?
    pr_summarizations: {
      business_controller_param: "copilot_for_dotcom",
      display_name: "Copilot in GitHub.com setting"
    }, # enabled from copilot_for_dotcom_enabled! with dotcom_chat
    private_docs: {},
    private_telemetry: {
      org_controller_param: "private_telemetry",
      display_name: "Private Telemetry setting"
    }, # Currently isn't used for businesses, used by orca team but might be deprecated
    prompt_overlap: {}, # Maybe not used anywhere?
    public_code_suggestions: {
      business_controller_param: "copilot_public_code_suggestions",
      org_controller_param: "copilot_public_code_suggestions",
      user_controller_param: "public_code_suggestions",
      display_name: "Copilot public code suggestions setting"
    },
    seat_management: {},
    usage_telemetry_api: {
      business_controller_param: "copilot_telemetry_aggregation",
      display_name: "Copilot metrics API access"
    },
    user_feedback_opt_in: {
      business_controller_param: "copilot_user_feedback_opt_in",
      org_controller_param: "copilot_user_feedback_opt_in",
      display_name: "User feedback collection opt-in"
    },
    user_telemetry: {
      user_controller_param: "telemetry",
      display_name: "Telemetry configuration"
    },
    workspace_for_emu: {
      business_controller_param: "copilot_workspace_for_emu",
      display_name: "Copilot Workspace setting"
    } # not currently used for orgs
  }, T::Hash[Symbol, T::Hash[Symbol, String]])

  sig { returns(T::Hash[Symbol, T::Hash[Symbol, String]]) }
  def self.policies
    T.let(POLICIES, T::Hash[Symbol, T::Hash[Symbol, String]])
  end

  sig { params(policy: Symbol).returns(T.nilable(String)) }
  def self.display_name_for(policy)
    T.let(POLICIES[policy]&.fetch(:display_name, nil), T.nilable(String))
  end

end
