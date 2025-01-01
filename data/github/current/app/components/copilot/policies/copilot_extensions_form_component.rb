# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CopilotExtensionsFormComponent < ApplicationComponent
      extend T::Sig
      include GitHub::Memoizer

      renders_one :form_content

      sig { returns(::Business) }
      attr_reader :configurable

      sig { params(configurable: (::Business)).void }
      def initialize(configurable:)
        @configurable = configurable
      end

      private

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      def menu_items
        [Copilot::Policies::MenuItems::CopilotExtensions::NoPolicy,
         Copilot::Policies::MenuItems::CopilotExtensions::Enabled,
         Copilot::Policies::MenuItems::CopilotExtensions::Disabled].map do |item|
          item.new(copilot_configurable: copilot_object, type: "submit").component
        end.compact
      end

      sig { returns(String) }
      def submit_path
        update_settings_copilot_policy_enterprise_path(configurable)
      end

      sig { returns(Copilot::Business) }
      memoize def copilot_object
        Copilot::Business.new(configurable)
      end
    end
  end
end
