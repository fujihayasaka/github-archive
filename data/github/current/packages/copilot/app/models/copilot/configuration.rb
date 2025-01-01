# typed: strict
# frozen_string_literal: true

module Copilot
  class Configuration < ApplicationRecord::Copilot
    include ::Instrumentation::Model

    self.table_name = "copilot_configurations"
    self.strict_loading_by_default = true

    self.ignored_columns += [:a_ft]

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
    }, prefix: false

    validates :copilot_enabled, if: :business?, inclusion: {
      in: %w[disabled enabled all_organizations selected_organizations unconfigured],
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

    enum :a_chat, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
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

    enum :o_f, {
      unconfigured: 0,
      disabled: 1,
      enabled: 2,
      no_policy: 3,
    }, prefix: true

    validates :o_f, if: :business?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :o_f, if: :organization?, inclusion: {
      in: %w[unconfigured enabled disabled no_policy]
    }
    validates :o_f, if: :user?, inclusion: {
      in: %w[unconfigured enabled disabled] # in reality, this is only enabled/disabled and the db value doesn't matter
    }

    enum :workspace_for_emu, {
      disabled: 0,
      enabled: 1,
    }, prefix: true

    validates :workspace_for_emu, if: :business?, inclusion: {
      in: %w[disabled enabled]
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
      configurable.organization?
    end

    sig { returns(T::Boolean) }
    def user?
      configurable.user?
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
    def a_chat_configured?
      !a_chat_unconfigured?
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
    def o_f_configured?
      !o_f_unconfigured?
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

    sig { returns(T.nilable(T::Boolean)) }
    def snippy_setting
      return unless public_code_suggestions_configured?
      !public_code_suggestions_allowed?
    end

    sig { returns(String) }
    def copilot_for_dotcom_setting
      github_enterprise_feature_group
    end

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
  end
end
