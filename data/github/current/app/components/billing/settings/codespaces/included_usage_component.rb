# typed: true
# frozen_string_literal: true

class Billing::Settings::Codespaces::IncludedUsageComponent < ApplicationComponent
  attr_reader :included_usage_percentage, :spending_limit

  def initialize(included_usage_percentage:, spending_limit:)
    @included_usage_percentage = included_usage_percentage
    @spending_limit = spending_limit
  end

  def render?
    included_usage_percentage.is_a? Numeric
  end

  def usage_exhausted_color
    spending_limit ? :attention_emphasis : :danger_emphasis
  end

end
