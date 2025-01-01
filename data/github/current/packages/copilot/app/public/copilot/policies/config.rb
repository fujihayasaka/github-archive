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
      display_name: "#{Copilot::COPILOT_A_CHAT} in Copilot setting"
    },
    a_f: {
      business_controller_param: "copilot_a_f",
      org_controller_param: "copilot_a_f",
      user_controller_param: "a_f",
      display_name: "#{Copilot::COPILOT_A_F} in Copilot setting"
    },
    afos: {
      business_controller_param: "copilot_afos",
      org_controller_param: "copilot_afos",
      user_controller_param: "afos",
      display_name: "#{Copilot::COPILOT_AFOS} in Copilot setting"
    },
    aofo: {
      business_controller_param: "copilot_aofo",
      org_controller_param: "copilot_aofo",
      user_controller_param: "aofo",
      display_name: "#{Copilot::COPILOT_AOFO} in Copilot setting"
    },
    al: {
      business_controller_param: "copilot_al",
      org_controller_param: "copilot_al",
      user_controller_param: "al",
      display_name: "#{Copilot::COPILOT_AL} in Copilot setting"
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
    agent_mode: {
      business_controller_param: "copilot_agent_mode",
      org_controller_param: "copilot_agent_mode",
      user_controller_param: "agent_mode",
      display_name: "Agent mode setting"
    },
    g_chat: {
      business_controller_param: "copilot_g_chat",
      org_controller_param: "copilot_g_chat",
      user_controller_param: "g_chat",
      display_name: "#{Copilot::COPILOT_G_CHAT} in Copilot setting"
    },
    g_tf: {
      business_controller_param: "copilot_g_tf",
      org_controller_param: "copilot_g_tf",
      user_controller_param: "g_tf",
      display_name: "#{Copilot::COPILOT_G_TF} in Copilot setting"
    },
    grok_code: {
      business_controller_param: "copilot_grok_code",
      org_controller_param: "copilot_grok_code",
      user_controller_param: "grok_code",
      display_name: "#{Copilot::COPILOT_GROK_CODE} in Copilot setting"
    },
    gtff: {
      business_controller_param: "copilot_gtff",
      org_controller_param: "copilot_gtff",
      user_controller_param: "gtff",
      display_name: "#{Copilot::COPILOT_GTFF} in Copilot setting"
    },
    github_enterprise_feature_group: {}, # copilot_for_dotcom
    ide_chat: {}, # looks like not called anywhere?
    insights: {
      business_controller_param: "copilot_insights",
      org_controller_param: "copilot_insights",
      user_controller_param: "copilot_insights",
      display_name: Copilot::COPILOT_INSIGHTS
    },
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
      display_name: "#{Copilot::COPILOT_O1} in Copilot setting"
    },
    o3: {
      business_controller_param: "copilot_o3",
      org_controller_param: "copilot_o3",
      user_controller_param: "o3",
      display_name: "#{Copilot::COPILOT_O3} in Copilot setting"
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
      display_name: "#{Copilot::COPILOT_O_FF} in Copilot setting"
    },
    o_fm: {
      business_controller_param: "copilot_o_fm",
      org_controller_param: "copilot_o_fm",
      user_controller_param: "o_fm",
      display_name: "#{Copilot::COPILOT_O_FM} in Copilot setting"
    },
    ofct: {
      business_controller_param: "copilot_ofct",
      org_controller_param: "copilot_ofct",
      user_controller_param: "ofct",
      display_name: "#{Copilot::COPILOT_OFCT} in Copilot setting"
    },
    o_t: {
      business_controller_param: "copilot_o_t",
      org_controller_param: "copilot_o_t",
      user_controller_param: "o_t",
      display_name: "#{Copilot::COPILOT_O_T} in Copilot setting"
    },
    obmb: {
      business_controller_param: "copilot_obmb",
      org_controller_param: "copilot_obmb",
      user_controller_param: "obmb",
      display_name: "#{Copilot::COPILOT_OBMB} in Copilot setting"
    },
    obmw: {
      business_controller_param: "copilot_obmw",
      org_controller_param: "copilot_obmw",
      user_controller_param: "obmw",
      display_name: "#{Copilot::COPILOT_OBMW} in Copilot setting"
    },
    ofo: {
      business_controller_param: "copilot_ofo",
      org_controller_param: "copilot_ofo",
      user_controller_param: "ofo",
      display_name: "#{Copilot::COPILOT_OFO} in Copilot setting"
    },
    pending_plan_downgrade_date: {}, # used when downgrading or when enabling or disabling
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
    swe_agent: {
      business_controller_param: "copilot_swe_agent",
      org_controller_param: "copilot_swe_agent",
      user_controller_param: "swe_agent",
      display_name: "#{Copilot::COPILOT_SWE_AGENT} access setting"
    },
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
    mcp: {
      business_controller_param: "copilot_mcp",
      org_controller_param: "copilot_mcp",
      user_controller_param: "mcp",
      display_name: "#{Copilot::COPILOT_MCP_SERVERS} access setting"
    },
    spark: {
      business_controller_param: "copilot_spark",
      org_controller_param: "copilot_spark",
      user_controller_param: "spark",
      display_name: "#{Copilot::SPARK_NAME} access setting"
    },
    workspace_for_emu: {
      business_controller_param: "copilot_workspace_for_emu",
      display_name: "Copilot Workspace setting"
    }, # not currently used for orgs
    ea_user_fallback_policy: {
      business_controller_param: "copilot_ea_user_fallback_policy",
      display_name: "#{Copilot::COPILOT_EA_USER_FALLBACK_POLICY} setting"
    }, # business only setting
    code_review: {
      business_controller_param: "copilot_code_review",
      org_controller_param: "copilot_code_review",
      user_controller_param: "code_review",
      display_name: "#{Copilot::COPILOT_CODE_REVIEW} access setting"
    },
    code_review_beta_features: {
      business_controller_param: "copilot_code_review_beta_features",
      org_controller_param: "copilot_code_review_beta_features",
      user_controller_param: "code_review_beta_features",
      display_name: "#{Copilot::COPILOT_CODE_REVIEW_PREVIEW_FEATURES} access setting"
    },
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
