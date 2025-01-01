# typed: true
# frozen_string_literal: true

module HostedRunnersHelper

  sig { params(entity: T.any(Business, Organization)).returns(T::Boolean) }
  def self.is_custom_images_permitted?(entity)
    return false if GitHub.enterprise?
    return true unless is_custom_images_policy_feature_enabled?(entity: entity)
    return true if entity.is_a?(Business)

    if entity.delegate_billing_to_business? && entity.business.present?
      business = T.must(entity.business)
      return false unless is_custom_images_policy_feature_enabled?(entity: business)

      # The org is in an enterprise, check that the business enables it for all orgs...
      return true if business.custom_images_enabled_for_all?
      # Or just selected orgs and this org is one of them
      return business.custom_images_enabled_for_selected? && entity.custom_images_allowed_by_owner?
    end

    # Otherwise, no enterprise, just the plan dictates it
    plan_allows_custom_images?(entity)
  end

  sig { params(entity: Organization).returns(T::Boolean) }
  def self.plan_allows_custom_images?(entity)
    return false if GitHub.enterprise?
    # Team and Enterprise plan orgs are allowed
    entity.plan.business? || entity.plan.business_plus?
  end

  sig { params(entity: T.any(Business, Organization)).returns(T::Boolean) }
  def self.is_custom_images_policy_feature_enabled?(entity:)
    FeatureFlag.vexi.enabled_or_raise?(:actions_enforce_custom_image_policy) || # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    entity.feature_flag_enabled?(:actions_enforce_custom_image_policy, default: false)
  end
end
