# typed: true
# frozen_string_literal: true

class Businesses::TrialAccounts::CancelActionComponent < ApplicationComponent
  attr_reader :business, :ref_loc

  delegate :cancel_trial_flavor, :cancelling_trial_flavor, to: :business

  def initialize(business:, button_size: nil, ref_loc: nil)
    @business = business
    @button_size = button_size
    @ref_loc = ref_loc
  end

  private

  def render?
    business.trial? && !business.trial_conversion_initiated?
  end

  def button_size
    return @button_size if @button_size.present?

    if business.trial_expired?
      :medium
    else
      :large
    end
  end
end
