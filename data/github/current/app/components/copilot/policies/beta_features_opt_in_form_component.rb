# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class BetaFeaturesOptInFormComponent < ApplicationComponent
      include GitHub::Memoizer

      GITHUB_COPILOT_PREVIEWS_TERMS_URL = "https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features#previews"

      sig { returns(::Business) }
      attr_reader :configurable

      sig { returns(String) }
      attr_reader :parent_product_name

      sig { returns(T.nilable(String)) }
      attr_reader :form_prefix

      sig { returns(String) }
      attr_reader :policy_id

      sig do params(
        configurable: ::Business,
        button_type: String,
        form_prefix: T.nilable(String),
        parent_product_name: String,
        policy_id: String
      ).void
      end
      def initialize(
        configurable:,
        button_type: "submit",
        form_prefix: nil,
        parent_product_name: Copilot::COPILOT_IN_DOTCOM,
        policy_id: "copilot_beta_features_opt_in"
      )
        @copilot_object = T.let(copilot_object(configurable), T.any(Copilot::Business, Copilot::Organization))
        @configurable = configurable
        @button_type = button_type
        @form_prefix = form_prefix
        @parent_product_name = parent_product_name
        @policy_id = policy_id
      end

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      private

      sig { returns(T::Boolean) }
      def checked?
        case @policy_id
        when "copilot_beta_features_opt_in"
          @copilot_object.beta_features_github_chat_enabled?
        when "copilot_code_review_beta_features"
          @copilot_object.code_review_beta_features_enabled?
        # Add additional policies here as needed
        else
          false
        end
      end

      sig { returns(String) }
      def product_preview_name
        if @parent_product_name == Copilot::COPILOT_IN_DOTCOM
          "Copilot"
        else
          @parent_product_name
        end
      end

      sig { returns(T::Boolean) }
      def render_shareable_component?
        @configurable.feature_flag_enabled?(:copilot_code_review_policy, default: false)
      end

      sig { returns(String) }
      def form_target
        form_prefix ? "#{form_prefix}BetaFeaturesOptInForm" : "betaFeaturesOptInForm"
      end

      sig { returns(String) }
      def toggle_target
        form_prefix ? "#{form_prefix}BetaFeaturesOptInCheckbox" : "betaFeaturesOptInCheckbox"
      end

      sig { returns(String) }
      def toggle_action
        "toggle#{form_prefix&.camelize}BetaFeaturesOptIn"
      end

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
