# typed: strict
# frozen_string_literal: true

class Devtools::FeatureEnabledFlashComponent < ApplicationComponent
  sig { returns(FeatureManagement::Models::DevtoolsFeature) }
  attr_reader :feature

  sig { params(feature: FeatureManagement::Models::DevtoolsFeature).void }
  def initialize(feature:)
    @feature = feature
  end

  sig { returns(Symbol) }
  def flash_scheme
    feature.fully_enabled? ? :default : :warning
  end

  sig { returns(String) }
  def title
    if feature.fully_enabled?
      "This feature is fully enabled"
    elsif feature.fully_disabled?
      "This feature is fully disabled"
    else
      "This feature is partially shipped"
    end
  end

  sig { returns(T::Boolean) }
  def render?
    title.present?
  end
end
