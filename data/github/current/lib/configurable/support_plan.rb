# typed: false
# frozen_string_literal: true

module Configurable
  module SupportPlan
    KEY = "support_plan".freeze

    # Note: keep these in sync with the support_sku field in Zendesk https://github.com/github/zendesk/issues/1726
    STANDARD           = "standard".freeze # Assumed default if configuration unset
    PREMIUM            = "premium".freeze
    PREMIUM_PLUS       = "premium_plus".freeze
    ENGINEERING_DIRECT = "premium_plus_engineering_direct".freeze
    ENGINEERING_DIR_P  = "premium_plus_engineering_direct_premier".freeze
    ENGINEERING_DIR_UA = "premium_plus_engineering_direct_unified_a".freeze
    ENGINEERING_DIR_UP = "premium_plus_engineering_direct_unified_p".freeze
    EDUCATION          = "education".freeze

    VALID_VALUES = [STANDARD, PREMIUM, PREMIUM_PLUS, ENGINEERING_DIRECT,
      ENGINEERING_DIR_P, ENGINEERING_DIR_UA, ENGINEERING_DIR_UP, EDUCATION].freeze

    class InvalidSupportPlan < StandardError; end
    include FeatureFlagHelper
    # Public: Set support plan for Business/Enterprise
    #
    # Allow support_plan to be set like other active record attributes.
    # Support Plan will only be able to be set by staff so try to get
    # current_user else default to backup_actor.
    def support_plan=(plan)
      raise InvalidSupportPlan.new(plan) unless plan.in?(VALID_VALUES)

      return plan if plan == support_plan

      backup_actor = GitHub.enterprise? ? User.ghost : User.staff_user
      actor = User.find_by(id: GitHub.context[:actor_id]) || backup_actor

      if plan == STANDARD
        config.delete(KEY, actor)
      else
        entry = configuration_entries.find_by(name: KEY) || configuration_entries.new(name: KEY)

        send_premium_mailer = plan.starts_with?("premium") && !entry.value.to_s.starts_with?("premium") && owners.present?

        entry.final   = false
        entry.value   = plan
        entry.updater = actor

        if persisted?
          entry.save!
          config.reset
          BusinessMailer.premium_support_notice(self).deliver_later if send_premium_mailer
        end
      end

      plan
    end

    def support_plan
      return STANDARD unless persisted?

      config.get(KEY) || STANDARD
    end

    def is_valid_support_plan(plan)
      VALID_VALUES.include?(plan)
    end

    def calculated_support_plan
      support_plan_source.microsoft? ? microsoft_support_plan : support_plan
    end

    def humanize_support_plan
      calculated_support_plan.titleize
    end

    def support_plan_source
      if support_plan.starts_with?("premium")
        "github".inquiry
      elsif microsoft_support_plan
        "microsoft".inquiry
      else
        "github".inquiry
      end
    end

    def has_premium_plus_support_plan?
      calculated_support_plan.starts_with?(PREMIUM_PLUS)
    end

    def has_premium_support_plan?
      !has_premium_plus_support_plan? && calculated_support_plan.starts_with?(PREMIUM)
    end
  end
end
