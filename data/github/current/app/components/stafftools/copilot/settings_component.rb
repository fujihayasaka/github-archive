# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::SettingsComponent < ApplicationComponent
  include GitHub::Memoizer

  renders_many :prepended_rows

  sig { returns(Copilot::Types::CopilotEntity) }
  attr_reader :configurable

  sig { params(configurable: Copilot::Types::CopilotEntity).void }
  def initialize(configurable)
    @configurable = configurable
  end

  private

  sig { returns(T::Array[Copilot::Policy]) }
  memoize def policies
    Copilot::Policies::ALL.reject do |policy|
      !policy.available_for?(@configurable)
    end
  end
end
