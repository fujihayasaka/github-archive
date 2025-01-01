# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CopilotForDotcomFormComponent < ApplicationComponent
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

      sig { returns(T::Boolean) }
      memoize def copilot_mixed_licenses_enabled?
        @configurable.feature_enabled?(:copilot_mixed_licenses)
      end

      sig { returns(T::Boolean) }
      def render_copilot_feedback_opt_in_settings?
        copilot_object.copilot_for_dotcom_enabled?
      end

      sig { returns(Numeric) }
      memoize def number_of_enterprise_organizations
        copilot_object.number_of_enterprise_organizations
      end

      sig { returns(T::Boolean) }
      def render_copilot_beta_features_opt_in_settings?
        T.must(user_feature_enabled?(:copilot_beta_features_opt_in) &&
          copilot_object.copilot_for_dotcom_enabled? &&
          copilot_object.copilot_organizations.any? { |org| org.copilot_enabled? && org.copilot_plan_enterprise? })
      end
    end
  end
end
