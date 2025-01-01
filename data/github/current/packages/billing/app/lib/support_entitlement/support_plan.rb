# typed: strict
# frozen_string_literal: true

module SupportEntitlement
  module SupportPlan
    premier_plan = Configurable::MicrosoftSupportPlan::PREMIER
    premium_unified_plan = Configurable::MicrosoftSupportPlan::PREMIUM_UNIFIED
    premier_psfp_plan = Configurable::MicrosoftSupportPlan::PREMIUM_PREMIER_PSFP
    premier_asfp_plan = Configurable::MicrosoftSupportPlan::PREMIUM_PREMIER_ASFP

    SUPPORTED_SUPPORT_PLANS = T.let([
      premier_plan,
      premium_unified_plan,
      premier_psfp_plan,
      premier_asfp_plan
    ], T::Array[String])

    SUPPORT_PLAN_MAPPING = T.let({}, T::Hash[Integer, String])

    SUPPORT_PLAN_PRECEDENCE = T.let({
      premier_asfp_plan => 1,
      premier_psfp_plan => 2,
      premier_plan => 3,
      premium_unified_plan => 4,
    }.freeze, T::Hash[String, Integer])

    Configurable::MicrosoftSupportPlan::PREMIUM_PREMIER_MSFT_SERVICE_IDS.each do |id|
      SUPPORT_PLAN_MAPPING[id] = premier_plan
    end

    Configurable::MicrosoftSupportPlan::PREMIUM_UNIFIED_MSFT_SERVICE_IDS.each do |id|
      SUPPORT_PLAN_MAPPING[id] = premium_unified_plan
    end

    Configurable::MicrosoftSupportPlan::PREMIUM_PREMIER_PSFP_SERVICE_IDS.each do |id|
      SUPPORT_PLAN_MAPPING[id] = premier_psfp_plan
    end

    Configurable::MicrosoftSupportPlan::PREMIUM_PREMIER_ASFP_SERVICE_IDS.each do |id|
      SUPPORT_PLAN_MAPPING[id] = premier_asfp_plan
    end
  end
end
