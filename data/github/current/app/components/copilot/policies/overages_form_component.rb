# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class OveragesFormComponent < ApplicationComponent
      sig { params(configurable: (::Business), input_id: T.nilable(String), technical_preview: T::Boolean).void }
      def initialize(configurable:, input_id: nil, technical_preview: false)
        @business = configurable
        @copilot_business = T.let(copilot_object(configurable), (Copilot::Business))
        @input_id = input_id
        @technical_preview = technical_preview
      end

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      private

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      def menu_items
        [Copilot::Policies::MenuItems::Overages::NoPolicy,
         Copilot::Policies::MenuItems::Overages::Enabled,
         Copilot::Policies::MenuItems::Overages::Disabled].map do |item|
          item.new(copilot_configurable: @copilot_business).component
        end.compact
      end

      sig { returns(String) }
      def submit_path
        update_settings_copilot_policy_enterprise_path(@business)
      end

      sig { params(configurable_object: (::Business)).returns(Copilot::Business) }
      def copilot_object(configurable_object)
        Copilot::Business.new(configurable_object)
      end
    end
  end
end
