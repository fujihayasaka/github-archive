# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class EditorChatFormComponent < ApplicationComponent
      renders_one :form_content

      sig { params(configurable: T.any(::Organization, ::Business), button_type: String, input_id: T.nilable(String), skip_form: T::Boolean, default_enabled: T::Boolean).void }
      def initialize(configurable:, button_type: "submit", input_id: nil, skip_form: false, default_enabled: false)
        @configurable = configurable
        @copilot_object = T.let(copilot_object(configurable), T.any(Copilot::Business, Copilot::Organization))
        @button_type = button_type
        @input_id = input_id
        @skip_form = skip_form
        @default_enabled = default_enabled
      end

      private

      sig { returns(T::Boolean) }
      def standalone_business?
        return false unless @configurable.is_a?(::Business)
        @copilot_object.copilot_standalone?
      end

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      def menu_items
        items = if @configurable.is_a?(::Business)
          [Copilot::Policies::MenuItems::EditorChat::Unconfigured,
           Copilot::Policies::MenuItems::EditorChat::NoPolicy,
           Copilot::Policies::MenuItems::EditorChat::Enabled,
           Copilot::Policies::MenuItems::EditorChat::Disabled]
        else
          [Copilot::Policies::MenuItems::EditorChat::Enabled,
           Copilot::Policies::MenuItems::EditorChat::Disabled]
        end

        items.map do |item|
          checked = if @default_enabled
            item == Copilot::Policies::MenuItems::EditorChat::Enabled
          end

          item.new(copilot_configurable: @copilot_object, type: @button_type, checked: checked).component
        end.compact
      end

      sig { returns(String) }
      def submit_path
        update_settings_copilot_policy_enterprise_path(@configurable)
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
