# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class RuleErrorDescriptionComponent < ApplicationComponent
    attr_reader :attributes

    sig { params(attributes: T::Array[String]).void }
    def initialize(attributes = [])
      @attributes = attributes
    end
  end
end
