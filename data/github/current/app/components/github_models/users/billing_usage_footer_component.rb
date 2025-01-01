# typed: true
# frozen_string_literal: true

class GitHubModels::Users::BillingUsageFooterComponent < ApplicationComponent
  sig { params(billing_enabled: T::Boolean).void }
  def initialize(billing_enabled:)
    @billing_enabled = billing_enabled
  end

  private

  sig { returns T::Boolean }
  attr_reader :billing_enabled

  def box_color
    @billing_enabled ? :attention : :default
  end
end
