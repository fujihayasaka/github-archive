# typed: true
# frozen_string_literal: true

class Billing::Settings::Copilot::StandaloneUsageComponent < ApplicationComponent
  attr_reader :total_copilot_usage_for_business

  def initialize(total_copilot_usage_for_business)
    @total_copilot_usage_for_business = total_copilot_usage_for_business
  end
end
