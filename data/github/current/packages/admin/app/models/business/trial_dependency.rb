# typed: true
# frozen_string_literal: true

module Business::TrialDependency
  include BusinessesHelper
  include GitHub::Memoizer

  extend T::Helpers

  requires_ancestor { Business }

  sig { returns(T::Boolean) }
  def digital_front_door?
    return false if GitHub.single_business_environment?
    return false unless self.feature_enabled?(:digital_front_door_mvp)
    return false unless self.feature_enabled?(:copilot_metered_enterprise)
    return false unless self.trial?
    return false unless self.metered_ghe?
    return false unless self.has_ongoing_copilot_business_trial?
    return false unless self.has_active_advanced_security_subscription?
    true
  end
end
