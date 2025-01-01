# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CliFormComponent < ApplicationComponent
      include GitHub::Memoizer

      renders_one :form_content

      sig { returns T.any(::Organization, ::Business) }
      attr_reader :configurable

      sig { params(configurable: T.any(::Organization, ::Business), skip_form: T::Boolean, button_type: String, input_id: T.nilable(String), default_value: T.nilable(String)).void }
      def initialize(configurable:, skip_form: false, button_type: "submit", input_id: nil, default_value: nil)
        @configurable = configurable
        @default_value = default_value
        @button_type = button_type
        @skip_form = skip_form
        @input_id = input_id
      end

      private

      sig { returns(T::Boolean) }
      def standalone_business?
        return false unless configurable.is_a?(::Business)
        copilot_object(configurable).copilot_standalone?
      end

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      def menu_items
        base_options.map do |item|
          checked = if @default_value == "enabled"
            item == Copilot::Policies::MenuItems::Cli::Enabled
          elsif @default_value == "disabled"
            item == Copilot::Policies::MenuItems::Cli::Disabled
          end
          item.new(copilot_configurable: copilot_object(configurable), type: @button_type, checked: checked).component
        end.compact
      end

      sig { returns(T::Array[T.untyped]) }
      def base_options
        base_options = T.let([
          Copilot::Policies::MenuItems::Cli::Enabled,
          Copilot::Policies::MenuItems::Cli::Disabled
        ], T::Array[T.untyped])

        base_options.prepend(Copilot::Policies::MenuItems::Cli::NoPolicy) unless standalone_business?
        base_options
      end

      sig { returns(String) }
      def submit_path
        update_settings_copilot_policy_enterprise_path(configurable)
      end


      sig { params(configurable_object: T.any(::Organization, ::Business)).returns(T.any(Copilot::Business, Copilot::Organization)) }
      def copilot_object(configurable_object)
        if configurable_object.is_a?(::Business)
          Copilot::Business.new(configurable_object)
        else
          Copilot::Organization.new(configurable_object)
        end
      end
    end
  end
end
