# typed: strict
# frozen_string_literal: true

module Repos
  module Security
    class RuntimeRisksComponent < ApplicationComponent
      sig { params(risks: T::Array[String]).void }
      def initialize(risks:)
        @risks = risks
      end

      sig { returns(T::Boolean) }
      def render?
        @risks.present?
      end

      sig { returns(T::Array[String]) }
      def risks
        @risks
      end
    end
  end
end
