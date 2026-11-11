# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class McpBaseComponent < ApplicationComponent
      renders_one :description

      sig do params(
        display_name: String,
        configurable: ::Business,
        can_write: T::Boolean
      ).void
      end
      def initialize(
        display_name:,
        configurable:,
        can_write: true
      )
        @display_name = display_name
        @configurable = configurable
        @can_write = T.let(can_write, T::Boolean)
      end

      sig { returns(T::Boolean) }
      attr_reader :can_write

      sig { returns(T::Boolean) }
      def render?
        return false unless logged_in?

        @configurable.actor_can_read_enterprise_ai_controls?(current_user) || false
      end
    end
  end
end
