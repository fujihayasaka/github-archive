# typed: true
# frozen_string_literal: true


class GitHubModels::Users::BillingUsageComponent < ApplicationComponent
  sig do
    params(
      user: User,
      can_enable_models_billing: T::Boolean,
      has_payment_method: T::Boolean,
      billing_enabled: T::Boolean,
      models_billing_disabled_by_non_payment_method_reason: T::Boolean,
      in_stafftools: T::Boolean,
      legacy: T::Boolean
    ).void
  end
  def initialize(user:, can_enable_models_billing: false, has_payment_method: false, billing_enabled: false, models_billing_disabled_by_non_payment_method_reason: false, in_stafftools: false, legacy: false)
    @user = user
    @can_enable_models_billing = can_enable_models_billing
    @has_payment_method = has_payment_method
    @billing_enabled = billing_enabled
    @models_billing_disabled_by_non_payment_method_reason = models_billing_disabled_by_non_payment_method_reason
    @in_stafftools = in_stafftools
    @legacy = legacy
  end

  private

  sig { returns T.nilable(User) }
  attr_reader :user

  sig { returns T::Boolean }
  attr_reader :can_enable_models_billing, :billing_enabled, :has_payment_method, :models_billing_disabled_by_non_payment_method_reason

  sig { returns T::Boolean }
  def in_stafftools?
    @in_stafftools
  end

  sig { returns(String) }
  def billing_enablement_path
    if in_stafftools?
      stafftools_user_models_billing_path(user)
    else
      models_user_billing_enablement_path(user)
    end
  end

  sig { returns(String) }
  def delete_billing_enablement_path
    if in_stafftools?
      stafftools_user_models_billing_path(user)
    else
      delete_models_user_billing_enablement_path(user)
    end
  end

  sig { returns(String) }
  def show_billing_text
    billing_enabled ? "Enabled" : "Disabled"
  end

  sig { returns(String) }
  def billing_details_path
    usage_chart_settings_billing_path(user, query: "product:models")
  end

  sig { returns T.nilable(T::Boolean) }
  def render?
    GitHub.models_enabled?
  end

  sig { returns(T::Boolean) }
  def legacy
    @legacy
  end
end
