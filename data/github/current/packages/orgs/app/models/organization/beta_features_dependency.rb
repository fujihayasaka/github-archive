# typed: true
# frozen_string_literal: true

module Organization::BetaFeaturesDependency
  extend T::Helpers

  requires_ancestor { Organization }

  BETA_FEATURES = []
  ELIGIBLE_PLANS = [GitHub::Plan::BUSINESS_PLUS, GitHub::Plan::BUSINESS]

  class MissingBigFeatureError < StandardError; end

  def set_beta_features_for_plan
    return unless GitHub.organization_beta_enrollment_enabled?

    if plan_gets_beta_features?
      enable_beta_features
    end
  end

  def has_active_enterprise_cloud_trial?
    Billing::EnterpriseCloudTrial.new(self).active?
  end

  private

  def plan_gets_beta_features?
    return true if has_active_enterprise_cloud_trial?

    ELIGIBLE_PLANS.include?(self.plan.name)
  end

  def enable_beta_features
    big_features = ::Flipper::Config.big_features

    BETA_FEATURES.each do |feature|
      T.bind(self, Organization)

      raise MissingBigFeatureError, "#{feature} is not defined as a big feature in Flipper config" unless big_features.include?(feature.to_s)

      FeatureFlag.vexi_management.add_feature_flag_actors(feature, [self]) # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
    end
  end
end
