# typed: true
# frozen_string_literal: true

class Platform::Models::FeatureFlagState
  attr_reader :name
  attr_reader :enabled

  def initialize(name, enabled)
    @name = name
    @enabled = enabled
  end
end
