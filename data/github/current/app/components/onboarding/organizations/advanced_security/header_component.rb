# typed: strict
# frozen_string_literal: true

class Onboarding::Organizations::AdvancedSecurity::HeaderComponent < ApplicationComponent
  sig { returns(T.nilable(Business)) }
  attr_reader :business

  sig { returns(Organization) }
  attr_reader :organization

  sig { returns(User) }
  attr_reader :user

  sig { returns(T::Boolean) }
  attr_reader :trial_active

  sig { params(organization: Organization, business: T.nilable(Business), user: User, trial_active: T::Boolean).void }
  def initialize(organization:, business:, user:, trial_active:)
    @organization = organization
    @business = business
    @user = user
    @trial_active = trial_active
  end

  sig { returns(T::Boolean) }
  def render?
    business.present?
  end

  sig { returns(T.nilable(Integer)) }
  memoize def trial_days_left
    biz = T.must(business)

    # Check SKU trial first if FF enabled
    if FeatureFlag.vexi.enabled?(:unified_self_serve_ghas_trials, biz, default: false)
      days_left = EnterpriseCloudOnboard::AdvancedSecurityTrial.advanced_security_trial_days_left(billable_entity: biz)
      return days_left unless days_left.nil?
    end

    # Fall back to subscription_item
    biz.advanced_security_subscription_item&.days_left_on_free_trial
  end

  sig { returns(T::Boolean) }
  def trial_active?
    trial_active
  end

  sig { returns(T::Boolean) }
  memoize def can_manage_business?
    T.must(business).adminable_by?(user)
  end
end
