# typed: true
# frozen_string_literal: true

class Businesses::Billing::AzureMeteredPaymentComponent < ApplicationComponent

  attr_reader :view, :metered_via_azure, :self_serve, :trial, :trial_cancelled

  def initialize(view:, metered_via_azure:, self_serve: false, trial: false, trial_cancelled: false)
    @view = view
    @metered_via_azure = metered_via_azure
    @self_serve = self_serve
    @trial = trial
    @trial_cancelled = trial_cancelled
  end

  def render?
    !(trial || trial_cancelled)
  end

  def self_serve?
    self_serve
  end
end
