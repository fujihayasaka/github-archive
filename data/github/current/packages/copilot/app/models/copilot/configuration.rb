# typed: strict
# frozen_string_literal: true

module Copilot
  class Configuration < ApplicationRecord::Copilot
    include ::Instrumentation::Model
    include GitHub::BatchedScope

    self.table_name = "copilot_configurations"
    self.strict_loading_by_default = true

    self.ignored_columns += [:a_ft, :copilot_swe_agent, :mcp_enabled, :pr_diff_chats, :beta_features_code_review, :emergency_model_2, :emergency_model_3, :training_telemetry]

    alias_attribute :automatic_code_review, :user_automatic_code_review

    belongs_to :configurable, polymorphic: true

    # max seats is a setting that is only available to Enterprise Teams (new functionality)
    # evidently these can have lots and lots of users and we don't want to charge if the admin
    # chooses a big group accidentally.
    validates :max_seats, if: :business?, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :max_seats, if: :organization?, numericality: { only_integer: true, equal_to: 0 }
    validates :max_seats, if: :user?, numericality: { only_integer: true, equal_to: 0 }

    scope :pending_downgrades, -> (configurable_type) {
      where(configurable_type: configurable_type)
        .where("pending_plan_downgrade_date <= ?", Date.current)
        .pluck(:configurable_id)
    }

    # Public code suggestions denote whether the configurable wants suggestions
    # from public code. Allowing this disables snippy, blocking enables snippy.
    enum :public_code_suggestions, {
      unconfigured: 0,
      allowed: 1,
      blocked: 2,
      no_policy: 3,
    }, prefix: true

    validates :public_code_suggestions, if: :business?, inclusion: {
      in: %w[allowed blocked no_policy],
    }
    validates :public_code_suggestions, if: :organization?, inclusion: {
      in: %w[unconfigured allowed blocked],
    }
    validates :public_code_suggestions, if: :user?, inclusion: {
      in: %w[unconfigured allowed blocked],
    }

    enum :chat_enabled, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :chat_enabled, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :chat_enabled, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :chat_enabled, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :dotcom_chat, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :dotcom_chat, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :dotcom_chat, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :dotcom_chat, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }

    enum :beta_features_github_chat, {
      disabled: 0,
      enabled: 1,
      no_policy: 2,
    }, prefix: true

    validates :beta_features_github_chat, if: :business?, inclusion: {
      in: %w[disabled enabled no_policy]
    }
    validates :beta_features_github_chat, if: :organization?, inclusion: {
      in: %w[disabled enabled]
    }
    validates :beta_features_github_chat, if: :user?, inclusion: {
      in: %w[disabled enabled]
    }

    enum :bing_github_chat, {
      disabled: 0,
      enabled: 1,
      no_policy: 2,
    }, prefix: true

    validates :bing_github_chat, if: :business?, inclusion: {
      in: %w[disabled enabled no_policy]
    }
    validates :bing_github_chat, if: :organization?, inclusion: {
      in: %w[disabled enabled]
    }
    validates :bing_github_chat, if: :user?, inclusion: {
      in: %w[disabled enabled]
    }

    enum :model_native_search, {
      unconfigured: 0,
      no_policy: 1,
      disabled: 2,
      enabled: 3,
    }, prefix: true

    validates :model_native_search, if: :business?, inclusion: {
      in: %w[unconfigured disabled enabled no_policy]
    }
    validates :model_native_search, if: :organization?, inclusion: {
      in: %w[unconfigured disabled enabled]
    }
    validates :model_native_search, if: :user?, inclusion: {
      in: %w[unconfigured disabled enabled]
    }

    enum :user_feedback_opt_in, {
      disabled: 0,
      enabled: 1,
      no_policy: 2,
    }, prefix: true

    validates :user_feedback_opt_in, if: :business?, inclusion: {
      in: %w[disabled enabled no_policy]
    }
    validates :user_feedback_opt_in, if: :organization?, inclusion: {
      in: %w[disabled enabled]
    }
    validates :user_feedback_opt_in, if: :user?, inclusion: {
      in: %w[disabled enabled]
    }

    enum :mobile_chat, {
      disabled: 0,
      enabled: 1,
      no_policy: 2,
    }, prefix: true

    validates :mobile_chat, if: :business?, inclusion: {
      in: %w[enabled disabled no_policy]
    }
    validates :mobile_chat, if: :organization?, inclusion: {
      in: %w[disabled enabled]
    }
    validates :mobile_chat, if: :user?, inclusion: {
      in: %w[disabled enabled]
    }

    enum :seat_management, {
      unconfigured: 0,
      disabled: 1,
      enabled_for_all: 2,
      enabled_for_selected: 3,
    }, prefix: true

    validates :seat_management, if: :organization?, inclusion: {
      in: %w[unconfigured disabled enabled_for_all enabled_for_selected]
    }

    # User telemetry controls if the clients should send telemetry (code
    # context, suggestions, and acceptance/rejection of suggestions) to the
    # telemetry service to help us improve Copilot.
    enum :user_telemetry, {
      enabled: 0,
      disabled: 1,
    }, prefix: true

    validates :user_telemetry, if: :business?, inclusion: {
      in: %w[disabled],
    }
    validates :user_telemetry, if: :organization?, inclusion: {
      in: %w[disabled],
    }
    validates :user_telemetry, if: :user?, inclusion: {
      in: %w[enabled disabled],
    }

    # Copilot enabled is a setting for Organizations and Businesses.
    enum :copilot_enabled, {
      disabled: 0,
      enabled: 1,
      all_organizations: 2,
      selected_organizations: 3,
      unconfigured: 4,
      organizations_disabled: 5,
    }, prefix: false

    validates :copilot_enabled, if: :business?, inclusion: {
      in: %w[disabled enabled all_organizations selected_organizations unconfigured organizations_disabled],
    }
    validates :copilot_enabled, if: :organization?, inclusion: {
      in: %w[disabled enabled],
    }
    validates :copilot_enabled, if: :user?, inclusion: {
      in: %w[disabled],
    }
    validates :copilot_enabled, if: :standalone_business?, inclusion: {
      in: %w[disabled enabled unconfigured],
    }

    enum :custom_models, {
      unconfigured: 0,
      no_policy: 1,
      disabled: 2,
      enabled: 3,
    }, prefix: true

    validates :custom_models, if: :business?, inclusion: {
      in: %w[no_policy disabled enabled unconfigured],
    }

    validates :custom_models, if: :organization?, inclusion: {
      in: %w[no_policy disabled enabled unconfigured],
    }

    validates :custom_models, if: :user?, inclusion: {
      in: %w[no_policy disabled enabled unconfigured],
    }

    enum :cli, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :cli, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :cli, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :cli, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }

    enum :desktop, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :desktop, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :desktop, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :desktop, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }

    enum :github_enterprise_feature_group, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :github_enterprise_feature_group, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :github_enterprise_feature_group, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :github_enterprise_feature_group, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }

    enum :usage_telemetry_api, {
      disabled: 0, # default for biz and org
      enabled: 1, # this can only be unlocked for orgs if the biz unlocks it
      no_policy: 2
    }, prefix: true

    validates :usage_telemetry_api, if: :business?, inclusion: {
      in: %w[disabled enabled no_policy]
    }
    validates :usage_telemetry_api, if: :organization?, inclusion: {
      in: %w[disabled enabled]
    }
    # not available for users
    validates :usage_telemetry_api, if: :user?, inclusion: {
      in: %w[disabled]
    }

    validates :usage_telemetry_api, if: :standalone_business?, inclusion: {
      in: %w[disabled enabled]
    }

    enum :pr_summarizations, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    enum :private_docs, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    # Tracks whether the entity is on a Copilot Business or Copilot Enterprise plan. If unconfigured,
    # the plan is determined by the owning entity, in this order: user -> org -> enterprise. All enterprises
    # should have a configured plan.
    enum :copilot_plan, {
      unconfigured: 0,
      business: 1,
      enterprise: 2,
    }, prefix: true

    validates :copilot_plan, if: :user?, inclusion: {
      in: %w[unconfigured]
    }

    validates :copilot_plan, if: :organization?, inclusion: {
      in: %w[unconfigured business enterprise]
    }

    # TODO: once existing enterprises are backfilled, add a validation to prevent `copilot_plan: :unconfigured` for businesses

    enum :copilot_extensions, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    enum :private_telemetry, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    enum :editor_preview_features, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    enum :agent_mode, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    enum :a_chat, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    enum :automatic_code_review, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    alias_attribute :agent_mode_auto_approve, :emergency_model_1
    enum :agent_mode_auto_approve, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    enum :coding_agent_enterprise_management, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
    }, prefix: true

    validates :editor_preview_features, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :editor_preview_features, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :editor_preview_features, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    validates :agent_mode, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :agent_mode, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :agent_mode, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    validates :agent_mode_auto_approve, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :agent_mode_auto_approve, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :agent_mode_auto_approve, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    validates :coding_agent_enterprise_management, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :automatic_code_review, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :automatic_code_review, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :automatic_code_review, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    validates :a_chat, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :a_chat, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :a_chat, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :a_f, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :a_f, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :a_f, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :a_f, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :afos, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :afos, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :afos, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :afos, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :al, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :al, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :al, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :al, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :g_chat, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :g_chat, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :g_chat, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :g_chat, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :g_tf, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :g_tf, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :g_tf, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :g_tf, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :gtff, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :gtff, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :gtff, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :gtff, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :obmb, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :obmb, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :obmb, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :obmb, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :obmw, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :obmw, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :obmw, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :obmw, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :aofo, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :aofo, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :aofo, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :aofo, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :o_fm, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :o_fm, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :o_fm, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :o_fm, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :ofct, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :ofct, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :ofct, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :ofct, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :o_t, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :o_t, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :o_t, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :o_t, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :o1, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :o1, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :o1, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :o1, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :o3, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :o3, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :o3, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :o3, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :o_ff, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :o_ff, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :o_ff, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :o_ff, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }



    enum :ofo, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :ofo, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :ofo, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :ofo, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :grok_code, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :grok_code, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :grok_code, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :grok_code, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :m_ironman, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :m_ironman, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :m_ironman, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :m_ironman, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :m_spiderman, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :m_spiderman, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :m_spiderman, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :m_spiderman, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :m_thor, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :m_thor, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :m_thor, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :m_thor, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :workspace_for_emu, {
      disabled: 0,
      enabled: 1,
    }, prefix: true

    validates :workspace_for_emu, if: :business?, inclusion: {
      in: %w[disabled enabled]
    }

    enum :mcp, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3
    }, prefix: true

    validates :mcp, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }

    validates :mcp, if: :organization?, inclusion: {
      in: %w[unconfigured disabled enabled],
    }
    validates :mcp, if: :user?, inclusion: {
      in: %w[unconfigured disabled enabled],
    }

    enum :overages, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3
    }, prefix: true

    validates :overages, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :overages, if: :standalone_business?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :overages, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :overages, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }

    enum :swe_agent, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :swe_agent, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy],
    }
    validates :swe_agent, if: :organization?, inclusion: {
      in: %w[unconfigured disabled enabled], # in reality, this is only enabled/disabled and the db value doesn't matter
    }
    validates :swe_agent, if: :user?, inclusion: {
      in: %w[unconfigured disabled enabled], # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :spark, {
      disabled: 0,
      enabled: 1,
      no_policy: 2,
    }, prefix: true

    validates :spark, if: :business?, inclusion: {
      in: %w[disabled enabled no_policy],
    }
    validates :spark, if: :organization?, inclusion: {
      in: %w[disabled enabled],
    }
    validates :spark, if: :user?, inclusion: {
      in: %w[disabled enabled],
    }

    alias_attribute :daisy, :acb # Column name is acb due to miscommunication during initial launch
    enum :daisy, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :daisy, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :daisy, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :daisy, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :loops, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :loops, if: :business?, inclusion: {
      in: %w[unconfigured disabled enabled no_policy],
    }
    validates :loops, if: :organization?, inclusion: {
      in: %w[unconfigured disabled enabled],
    }
    validates :loops, if: :user?, inclusion: {
      in: %w[unconfigured disabled enabled],
    }

    enum :bento, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :bento, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :bento, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :bento, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :sunflower, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :sunflower, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :sunflower, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :sunflower, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :tulip, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :tulip, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :tulip, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :tulip, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :peony, {
      unconfigured: 0, # default
      disabled: 1,
      enabled: 2,
    }, prefix: true

    validates :peony, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :peony, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :peony, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }

    enum :lotus, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :lotus, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :lotus, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :lotus, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :arcticfox, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :arcticfox, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :arcticfox, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :arcticfox, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :watermelon, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :watermelon, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :watermelon, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :watermelon, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :antman, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :antman, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :antman, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :antman, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :hulk, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :hulk, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :hulk, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :hulk, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :captainamerica, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :captainamerica, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :captainamerica, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :captainamerica, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :wintersoldier, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :wintersoldier, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :wintersoldier, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :wintersoldier, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :blackpanther, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :blackpanther, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :blackpanther, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :blackpanther, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :cucumber, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :cucumber, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :cucumber, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :cucumber, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :blueberry, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :blueberry, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :blueberry, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :blueberry, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :cherry, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :cherry, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :cherry, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled]
    }
    validates :cherry, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    # Controls whether we force Spark repo creation in an org -- either user or in an org.
    enum :spark_force_org, {
      disabled: 0,
      enabled: 1,
      no_policy: 2,
    }, prefix: true

    validates :spark_force_org, if: :business?, inclusion: {
      in: %w[disabled enabled no_policy],
    }
    validates :spark_force_org, if: :organization?, inclusion: {
      in: %w[disabled enabled],
    }
    validates :spark_force_org, if: :user?, inclusion: {
      in: %w[disabled enabled],
    }

    # This is more of a meta-policy that allows business admins to set a fallback policy for
    # enterprise-assigned users when the business selects "No policy" for any policy.
    # This is only used for Copilot for Business assigned directly by the business to users.
    # As this is a business-only setting, it is not available or validatable for organizations or users.
    # The default is disabled.
    enum :ea_user_fallback_policy, {
      disabled: 1,
      enabled: 2,
    }, prefix: true

    validates :ea_user_fallback_policy, if: :business?, inclusion: {
      in: %w[enabled disabled],
    }

    enum :insights, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :insights, if: :business?, inclusion: { in: %w[unconfigured disabled enabled no_policy] }
    validates :insights, if: :organization?, inclusion: { in: %w[unconfigured disabled enabled] }
    validates :insights, if: :user?, inclusion: { in: %w[unconfigured] } # We don't have this policy at the user level so it shouldn't change

    enum :code_review, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :code_review, if: :business?, inclusion: { in: %w[unconfigured disabled enabled no_policy] }
    validates :code_review, if: :organization?, inclusion: { in: %w[unconfigured disabled enabled] }
    validates :code_review, if: :user?, inclusion: { in: %w[unconfigured disabled enabled] }

    enum :code_review_beta_features, {
      disabled: 0,
      enabled: 1,
      no_policy: 2,
    }, prefix: true

    validates :code_review_beta_features, if: :business?, inclusion: { in: %w[disabled enabled no_policy] }
    validates :code_review_beta_features, if: :organization?, inclusion: { in: %w[disabled enabled] }
    validates :code_review_beta_features, if: :user?, inclusion: { in: %w[disabled enabled] }

    enum :generated_commit_message, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :generated_commit_message, if: :business?, inclusion: { in: %w[unconfigured disabled enabled no_policy] }
    validates :generated_commit_message, if: :organization?, inclusion: { in: %w[unconfigured disabled enabled] }
    validates :generated_commit_message, if: :user?, inclusion: { in: %w[unconfigured disabled enabled] }

    enum :spaces, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :spaces, if: :business?, inclusion: { in: %w[unconfigured disabled enabled no_policy] }
    validates :spaces, if: :organization?, inclusion: { in: %w[unconfigured disabled enabled] }
    validates :spaces, if: :user?, inclusion: { in: %w[unconfigured disabled enabled] } # Not available at user level but still shown on the user setting form

    enum :cca_direct_org_billing, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :cca_direct_org_billing, if: :business?, inclusion: { in: %w[unconfigured disabled enabled no_policy] }
    validates :cca_direct_org_billing, if: :organization?, inclusion: { in: %w[unconfigured disabled enabled] } # This policy is inherited/propagated from business (or org-configured when business has no_policy)
    validates :cca_direct_org_billing, if: :user?, inclusion: { in: %w[unconfigured] } # We don't have this policy at the user level so it shouldn't change

    enum :cli_direct_org_billing, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :cli_direct_org_billing, if: :business?, inclusion: { in: %w[unconfigured disabled enabled no_policy] }
    validates :cli_direct_org_billing, if: :organization?, inclusion: { in: %w[unconfigured disabled enabled] } # This policy is inherited/propagated from business (or org-configured when business has no_policy)
    validates :cli_direct_org_billing, if: :user?, inclusion: { in: %w[unconfigured] } # We don't have this policy at the user level so it shouldn't change

    enum :ccr_direct_org_billing, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :ccr_direct_org_billing, if: :business?, inclusion: { in: %w[unconfigured disabled enabled no_policy] }
    validates :ccr_direct_org_billing, if: :organization?, inclusion: { in: %w[unconfigured disabled enabled] } # This policy is inherited/propagated from business (or org-configured when business has no_policy)
    validates :ccr_direct_org_billing, if: :user?, inclusion: { in: %w[unconfigured] } # We don't have this policy at the user level so it shouldn't change

    enum :spaces_individual_access, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :spaces_individual_access, if: :business?, inclusion: { in: %w[unconfigured disabled enabled no_policy] }
    validates :spaces_individual_access, if: :organization?, inclusion: { in: %w[unconfigured disabled enabled] }
    validates :spaces_individual_access, if: :user?, inclusion: { in: %w[unconfigured disabled enabled] } # Not available at user level but still shown on the user setting form

    enum :spaces_individual_sharing, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :spaces_individual_sharing, if: :business?, inclusion: { in: %w[unconfigured disabled enabled no_policy] }
    validates :spaces_individual_sharing, if: :organization?, inclusion: { in: %w[unconfigured disabled enabled] }
    validates :spaces_individual_sharing, if: :user?, inclusion: { in: %w[unconfigured disabled enabled] } # Not available at user level but still shown on the user setting form

    enum :restrict_to_azure, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :restrict_to_azure, if: :business?, inclusion: { in: %w[unconfigured disabled enabled no_policy] }
    validates :restrict_to_azure, if: :organization?, inclusion: { in: %w[unconfigured disabled enabled] }
    validates :restrict_to_azure, if: :user?, inclusion: { in: %w[unconfigured] } # Not available at user level for CFI

    enum :memory, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :memory, if: :business?, inclusion: { in: %w[unconfigured disabled enabled no_policy] } #  unconfigured = no_policy at business level so orgs can opt in without enterprise configuration.
    validates :memory, if: :organization?, inclusion: { in: %w[unconfigured disabled enabled] } # no_policy not available at org level as users in org may not configure it. unconfigured = disabled.
    validates :memory, if: :user?, inclusion: { in: %w[unconfigured disabled enabled] } # Visible to user in orgs but not configurable. User not an org can configure.

    enum :restrict_to_fedramp, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :restrict_to_fedramp, if: :business?, inclusion: { in: %w[unconfigured disabled enabled no_policy] }
    validates :restrict_to_fedramp, if: :organization?, inclusion: { in: %w[unconfigured disabled enabled] }
    validates :restrict_to_fedramp, if: :user?, inclusion: { in: %w[unconfigured] } # Not available at user level for CFI

    enum :restrict_to_data_residency, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :restrict_to_data_residency, if: :business?, inclusion: { in: %w[unconfigured disabled enabled no_policy] }
    validates :restrict_to_data_residency, if: :organization?, inclusion: { in: %w[unconfigured disabled enabled] }
    validates :restrict_to_data_residency, if: :user?, inclusion: { in: %w[unconfigured] } # Not available at user level for CFI

    sig { returns(T::Boolean) }
    def business?
      configurable_type == "Business"
    end

    sig { returns(T::Boolean) }
    def standalone_business?
      return false unless business?

      biz = ::Business.find_by(id: configurable_id)
      return false if biz.nil?

      biz.copilot_licensing_enabled?
    end

    sig { returns(T::Boolean) }
    def organization?
      configurable_type == "Organization"
    end

    sig { returns(T::Boolean) }
    def user?
      configurable_type == "User"
    end

    sig { returns(T::Boolean) }
    def public_code_suggestions_configured?
      !public_code_suggestions_unconfigured?
    end

    sig { returns(T::Boolean) }
    def chat_enabled_configured?
      !chat_enabled_unconfigured?
    end

    sig { returns(T::Boolean) }
    def dotcom_chat_configured?
      !dotcom_chat_unconfigured?
    end

    sig { returns(T::Boolean) }
    def editor_preview_features_configured?
      !editor_preview_features_unconfigured?
    end

    sig { returns(T::Boolean) }
    def agent_mode_configured?
      !agent_mode_unconfigured?
    end

    sig { returns(T::Boolean) }
    def agent_mode_auto_approve_configured?
      !agent_mode_auto_approve_unconfigured?
    end

    sig { returns(T::Boolean) }
    def automatic_code_review_configured?
      !automatic_code_review_unconfigured?
    end

    sig { returns(T::Boolean) }
    def a_f_configured?
      !a_f_unconfigured?
    end

    sig { returns(T::Boolean) }
    def g_chat_configured?
      !g_chat_unconfigured?
    end

    sig { returns(T::Boolean) }
    def o1_configured?
      !o1_unconfigured?
    end

    sig { returns(T::Boolean) }
    def o3_configured?
      !o3_unconfigured?
    end

    sig { returns(T::Boolean) }
    def o_ff_configured?
      !o_ff_unconfigured?
    end

    sig { returns(T::Boolean) }
    def cli_configured?
      !cli_unconfigured?
    end

    sig { returns(T::Boolean) }
    def desktop_configured?
      !desktop_unconfigured?
    end

    sig { returns(T::Boolean) }
    def custom_models_configured?
      !custom_models_unconfigured?
    end

    sig { returns(T::Boolean) }
    def overages_configured?
      !overages_unconfigured?
    end

    sig { returns(T::Boolean) }
    def spaces_configured?
      !spaces_unconfigured?
    end

    sig { returns(T.nilable(T::Boolean)) }
    def snippy_setting
      return unless public_code_suggestions_configured?
      !public_code_suggestions_allowed?
    end

    sig { returns(String) }
    def copilot_for_dotcom_setting
      github_enterprise_feature_group
    end
    alias copilot_for_dotcom copilot_for_dotcom_setting

    sig { returns(T::Boolean) }
    def copilot_for_dotcom_configured?
      !github_enterprise_feature_group_unconfigured?
    end

    sig { returns(T::Boolean) }
    def copilot_for_dotcom_unconfigured?
      github_enterprise_feature_group_unconfigured?
    end

    sig { void }
    def copilot_for_dotcom_unconfigured!
      github_enterprise_feature_group_unconfigured!
      dotcom_chat_unconfigured!
      pr_summarizations_unconfigured!
    end

    sig { returns(T::Boolean) }
    def copilot_for_dotcom_enabled?
      github_enterprise_feature_group_enabled?
    end

    sig { void }
    def copilot_for_dotcom_enabled!
      github_enterprise_feature_group_enabled!
      dotcom_chat_enabled!
      pr_summarizations_enabled!
    end

    sig { returns(T::Boolean) }
    def copilot_for_dotcom_disabled?
      github_enterprise_feature_group_disabled?
    end

    sig { returns(T::Boolean) }
    def pr_summarizations_configured?
      !github_enterprise_feature_group_unconfigured?
    end

    sig { returns(T::Boolean) }
    def private_docs_configured?
      !private_docs_unconfigured?
    end

    sig { void }
    def copilot_for_dotcom_disabled!
      github_enterprise_feature_group_disabled!
      dotcom_chat_disabled!
      beta_features_github_chat_disabled!
      pr_summarizations_disabled!
    end

    sig { returns(T::Boolean) }
    def copilot_for_dotcom_no_policy?
      github_enterprise_feature_group_no_policy?
    end

    sig { void }
    def copilot_for_dotcom_no_policy!
      # Only businesses have concept of "no_policy"
      return unless business?
      github_enterprise_feature_group_no_policy!
      dotcom_chat_no_policy!
      beta_features_github_chat_no_policy!
      pr_summarizations_no_policy!
    end

    sig { returns(T::Boolean) }
    def copilot_extensions_configured?
      !copilot_extensions_unconfigured?
    end

    sig { returns(T::Boolean) }
    def private_telemetry_configured?
      !private_telemetry_unconfigured?
    end

    sig { params(model_key: String).returns(String) }
    def model_policy(model_key)
      policy = (model_policies || {})[model_key]
      return policy if %w[unconfigured enabled disabled no_policy].include?(policy)

      "unconfigured"
    end

    sig { params(model_key: String, policy: String).void }
    def set_model_policy(model_key, policy)
      return unless ModelsRegistryCache.find_by(model_key: model_key).present?
      return unless %w[enabled disabled no_policy].include?(policy)

      update_model_policies = (model_policies.dup || {})
      update_model_policies[model_key] = policy
      update!(model_policies: update_model_policies)
    end
  end
end
