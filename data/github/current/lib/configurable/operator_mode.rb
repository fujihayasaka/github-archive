# typed: true
# frozen_string_literal: true

module Configurable
  module OperatorMode
    extend T::Helpers

    requires_ancestor { Configurable }

    def enable_operator_mode(actor)
      config.enable("operator_mode", actor)
    end

    def disable_operator_mode(actor)
      config.delete("operator_mode", actor)
    end

    def operator_mode_enabled?
      config.enabled?("operator_mode")
    end
  end
end
