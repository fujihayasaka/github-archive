# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class BetaFeaturesOptInFormComponent < ApplicationComponent
      extend T::Sig
      include GitHub::Memoizer

      GITHUB_COPILOT_PREVIEWS_TERMS_URL = "https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features#previews"

      sig { returns(::Business) }
      attr_reader :configurable

      sig { params(configurable: ::Business, button_type: String).void }
      def initialize(configurable:, button_type: "submit")
        @copilot_object = T.let(copilot_object(configurable), T.any(Copilot::Business, Copilot::Organization))
        @configurable = configurable
        @button_type = button_type
      end

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      private

      sig { returns(String) }
      def submit_path
        update_settings_copilot_policy_enterprise_path(configurable)
      end


      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      def menu_items
        items = if @configurable.is_a?(::Business)
          [Copilot::Policies::MenuItems::BetaFeaturesOptIn::NoPolicy,
           Copilot::Policies::MenuItems::BetaFeaturesOptIn::Enabled,
           Copilot::Policies::MenuItems::BetaFeaturesOptIn::Disabled]
        else
          [Copilot::Policies::MenuItems::BetaFeaturesOptIn::Enabled,
           Copilot::Policies::MenuItems::BetaFeaturesOptIn::Disabled]
        end

        items.map do |item|
          item.new(copilot_configurable: @copilot_object, type: @button_type).component
        end.compact
      end

      sig { returns(String) }
      def github_copilot_previews_term_url
        GITHUB_COPILOT_PREVIEWS_TERMS_URL
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
