# typed: true
# frozen_string_literal: true

class GitHubModels::Users::BillingUsageFooterComponent < ApplicationComponent
  sig { params(billing_enabled: T::Boolean, is_enterprise_managed_user: T::Boolean, in_stafftools: T::Boolean).void }
  def initialize(billing_enabled:, is_enterprise_managed_user: false, in_stafftools: false)
    @billing_enabled = billing_enabled
    @is_enterprise_managed_user = is_enterprise_managed_user
    @in_stafftools = in_stafftools
  end

  private

  sig { returns T.nilable(T::Boolean) }
  def render?
    GitHub.models_enabled?
  end

  sig { returns T::Boolean }
  attr_reader :billing_enabled, :is_enterprise_managed_user

  sig { returns T::Boolean }
  def in_stafftools?
    @in_stafftools
  end
end
