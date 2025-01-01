# typed: true
# frozen_string_literal: true

class Billing::Settings::ExtraBillingInfoModalComponent < ApplicationComponent
  def initialize(target:)
    @target = target
  end

  private

  attr_reader :target

  def render?
    GitHub.billing_enabled? && target.present? && logged_in?
  end

  def form_path
    target.organization? ? org_extra_update_path(target) : billing_extra_update_path
  end
end
