# typed: strict
# frozen_string_literal: true

module Copilot
  class BusinessTrialStatusFooterComponent < ApplicationComponent

    sig { returns(BusinessTrial) }
    attr_reader :business_trial

    sig { params(business_trial: BusinessTrial).void }
    def initialize(business_trial:)
      @business_trial = business_trial
    end

    sig { returns(T::Boolean) }
    def render?
      return false if business_trial.final_day?
      return true if business_trial.pending?
      business_trial.active? && business_trial.days_left > 0
    end

    sig { returns(String) }
    def trial_expires_message
      if business_trial.copilot_plan_business?
        "Your GitHub Copilot free trial expires"
      else
        "Your GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} trial expires"
      end
    end

    sig { returns(String) }
    def trial_requirements_message
      if business_trial.copilot_plan_business?
        "#{business_trial.trial_length} days after the first seat is added."
      else
        "#{business_trial.trial_length} days after #{Copilot::COPILOT_IN_DOTCOM} policy is enabled and seats are assigned."
      end
    end
  end
end
