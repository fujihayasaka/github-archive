# typed: false
# frozen_string_literal: true

module Configurable
  module MicrosoftSupportPlan
    KEY = "microsoft_support_plan"

    # Note: keep these in sync with the support_sku field in Zendesk https://github.com/github/zendesk/issues/1726
    UNIFIED_ADVANCED = "premium_unified_advanced"
    UNIFIED_PERFORMANCE = "premium_unified_performance"
    PREMIER            = "premium_premier"
    PREMIUM_UNIFIED    = "premium_unified"
    GHED = "premium_plus_engineering_direct"
    PREMIUM_PREMIER_ASFP = "premium_premier_asfp"
    PREMIUM_PREMIER_PSFP = "premium_premier_psfp"

    # This plan is used to remove the microsoft support plan
    STANDARD = "standard"

    VALID_VALUES = [UNIFIED_ADVANCED, UNIFIED_PERFORMANCE, PREMIER, PREMIUM_UNIFIED, GHED, PREMIUM_PREMIER_ASFP, PREMIUM_PREMIER_PSFP].freeze

    PREMIUM_UNIFIED_MSFT_SERVICE_IDS = T.let([
      1133, 1134, 1221, 1267, 1271, 1272, 1273, 1274, 1275, 1276, 1283, 1432, 1539, 1579
    ].freeze, T::Array[Integer])

    PREMIUM_PREMIER_MSFT_SERVICE_IDS = T.let([
      21, 208, 315, 327, 329, 355, 368, 372, 373, 517, 522, 602, 603, 688, 700, 701, 803, 842, 1001, 1020, 1142, 1154, 1201, 1279
    ].freeze, T::Array[Integer])

    PREMIUM_PREMIER_PSFP_SERVICE_IDS = T.let([828, 832, 836, 1044, 1047, 1048, 1053, 1054].freeze, T::Array[Integer])
    PREMIUM_PREMIER_ASFP_SERVICE_IDS = T.let([1158, 1204, 1205].freeze, T::Array[Integer])

    class InvalidMicrosoftSupportPlan < StandardError; end

    sig { params(plan: T.nilable(String), dry_run: T::Boolean).returns(T::Boolean) }
    def update_microsoft_support_plan(plan, dry_run: false)
      if is_valid_microsoft_support_plan?(plan) && GitHub.flipper[:microsoft_support_plan].enabled?(self)
        self.microsoft_support_plan = plan unless dry_run

        true
      elsif plan == STANDARD
        self.microsoft_support_plan = nil unless dry_run
        true
      else # plan not found
        false
      end
    end

    # Public: Set microsoft support plan for Business/Enterprise
    #
    # Allow microsoft_support_plan to be set like other active record attributes.
    # Microsoft Support Plan will only be able to be set by staff so try to get
    # current_user else default to backup_actor.
    # since there is no default plan, default is nil or "", which will delete the record
    def microsoft_support_plan=(plan)
      raise InvalidMicrosoftSupportPlan.new(plan) unless plan.blank? || plan.in?(VALID_VALUES)

      return plan if plan == microsoft_support_plan

      backup_actor = GitHub.enterprise? ? User.ghost : User.staff_user
      actor = User.find_by(id: GitHub.context[:actor_id]) || backup_actor

      if plan.blank?
        config.delete(KEY, actor)
      else
        entry = configuration_entries.find_by(name: KEY) || configuration_entries.new(name: KEY)

        already_premium = !entry.value.to_s.blank? || support_plan.starts_with?("premium")

        entry.final   = false
        entry.value   = plan
        entry.updater = actor

        if persisted?
          entry.save!
          config.reset
          BusinessMailer.premium_support_notice(self).deliver_later if !already_premium && owners.present?
        end
      end

      plan
    end

    def microsoft_support_plan
      return unless persisted?

      config.get(KEY)
    end

    def is_valid_microsoft_support_plan?(plan)
      VALID_VALUES.include?(plan)
    end
  end
end
