# typed: true
# frozen_string_literal: true

class Billing::Settings::CopilotForBusiness::BusinessUsageComponent < ApplicationComponent
  attr_reader :organizations_copilot_usage, :number_of_organizations_without_copilot_usage

  def initialize(
    organizations_copilot_usage:,
    number_of_organizations_without_copilot_usage:
  )

    @organizations_copilot_usage = organizations_copilot_usage
    @number_of_organizations_without_copilot_usage = number_of_organizations_without_copilot_usage
  end
end
