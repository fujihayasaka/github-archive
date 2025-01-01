# typed: strict
# frozen_string_literal: true

module Settings
  module Copilot
    class SnippyConfigurationComponent < ApplicationComponent
      extend T::Sig

      sig { params(can_modify_copilot_settings: T::Boolean, public_code_suggestions_configured: T::Boolean).void }
      def initialize(can_modify_copilot_settings, public_code_suggestions_configured)
        @can_modify_copilot_settings        = can_modify_copilot_settings
        @public_code_suggestions_configured = public_code_suggestions_configured
      end

      sig { returns(T::Boolean) }
      def render?
        @can_modify_copilot_settings && !@public_code_suggestions_configured
      end
    end
  end
end
