# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class PublicSuggestionsFormComponent < ApplicationComponent
      renders_one :form_content

      sig { params(configurable: T.any(::Organization, ::Business), button_type: String, input_id: T.nilable(String), skip_form: T::Boolean).void }
      def initialize(configurable:, button_type: "submit", input_id: nil, skip_form: false)
        @configurable = configurable
        @copilot_configurable = T.let(copilot_object(configurable), T.any(Copilot::Organization, Copilot::Business))
        @enable = T.let(true, T::Boolean)
        @button_type = button_type
        @input_id = input_id
        @skip_form = skip_form

        @copilot_organization = T.let(@configurable.business? ? nil : Copilot::Organization.new(T.cast(@configurable, ::Organization)), T.nilable(Copilot::Organization))

        if !configurable.business?
          organization = T.cast(configurable, ::Organization)
          business = organization.business
          if business
            copilot_business = copilot_object(business)
            @enable = !copilot_business.allow_public_code_suggestions? && !copilot_business.block_public_code_suggestions?
          end
        end
      end

      private

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      def menu_items
        [Copilot::Policies::MenuItems::PublicCodeSuggestions::Unconfigured,
         Copilot::Policies::MenuItems::PublicCodeSuggestions::NoPolicy,
         Copilot::Policies::MenuItems::PublicCodeSuggestions::Blocked,
         Copilot::Policies::MenuItems::PublicCodeSuggestions::Allowed].map do |item|
          item.new(copilot_configurable: @copilot_configurable, type: @button_type).component
        end.compact
      end

      sig { returns(String) }
      def submit_path
        return update_settings_copilot_policy_enterprise_path(@configurable.display_login) if business?
        settings_org_copilot_policies_update_path(@configurable.display_login)
      end

      sig { returns(T::Boolean) }
      def business?
        @configurable.is_a?(::Business)
      end

      sig { returns(String) }
      def current_label
        T.must(menu_items.find { |item| item.checked }).text
      end

      sig { params(configurable_object: T.any(::Organization, ::Business)).returns(T.any(Copilot::Organization, Copilot::Business)) }
      def copilot_object(configurable_object)
        case configurable_object
        when ::Organization
          Copilot::Organization.new(configurable_object)
        else
          Copilot::Business.new(configurable_object)
        end
      end
    end
  end
end
