# typed: true
# frozen_string_literal: true

module SecurityCenter
  class PhaseComponent < ApplicationComponent

    TEST_SELECTOR = "security-center-phase"

    attr_accessor :phase, :system_arguments
    private :phase, :system_arguments

    sig { params(phase: Symbol, system_arguments: T.untyped).void }
    def initialize(phase, **system_arguments)
      raise ArgumentError, "Invalid phase: #{phase}" unless Phase::VALID_PHASES.include?(phase)

      @phase = phase
      @system_arguments = system_arguments
    end

    sig { returns(T::Boolean) }
    def render?
      label.present?
    end

    private

    sig { returns(String) }
    def label
      return phase.to_s.humanize if [:alpha, :private_beta, :beta].include?(phase)
      ""
    end
  end
end
