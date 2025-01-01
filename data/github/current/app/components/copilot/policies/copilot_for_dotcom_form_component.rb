# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CopilotForDotcomFormComponent < ApplicationComponent
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
        [Copilot::Policies::MenuItems::CopilotForDotcom::NoPolicy,
         Copilot::Policies::MenuItems::CopilotForDotcom::Enabled,
         Copilot::Policies::MenuItems::CopilotForDotcom::Disabled].map do |item|
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

      sig { returns(Numeric) }
      memoize def number_of_enterprise_organizations
        copilot_object.number_of_enterprise_organizations
      end
    end
  end
end
