# typed: true
# frozen_string_literal: true

class Businesses::BillingSettings::ShowView
  class ActionsUsage
    attr_reader :organization
    delegate :total_standard_runners_minutes_used, to: :usage

    def initialize(organization, usage:)
      @organization = organization
      @usage = usage
    end

    private

    attr_reader :usage
  end
end
