# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class BusinessOptInFormComponent < ApplicationComponent
      include GitHub::Memoizer
      renders_one :description

      sig { returns(::Business) }
      attr_reader :configurable

      sig { returns(String) }
      attr_reader :display_name

      sig { returns(String) }
      attr_reader :policy_id

      sig { returns(String) }
      attr_reader :tab

      sig do params(
        policy_class: Copilot::PolicyInterface,
        configurable: (::Business),
        tab: String,
        display_name: T.nilable(String),
        can_write: T::Boolean,
        return_to: T.nilable(String),
      ).void
      end
      def initialize(
        policy_class:,
        configurable:,
        tab: "policies",
        display_name: nil,
        can_write: true,
        return_to: nil
      )
        @copilot_object = T.let(copilot_object(configurable), T.any(Copilot::Business, Copilot::Organization))
        @configurable = configurable
        @policy_class = policy_class
        @tab = tab
        @display_name = T.let(display_name || "Opt in to #{policy_class.display_name}", String)
        @policy_id = T.let(policy_class.config_name, String)
        @can_write = T.let(can_write, T::Boolean)
        @return_to = return_to
      end

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      sig { returns(T::Boolean) }
      attr_reader :can_write

      private

      sig { returns(T::Boolean) }
      def checked?
        @policy_class.enabled?(@copilot_object)
      end

      sig { returns(String) }
      def submit_path
        if FeatureFlag.vexi.enabled?(:enterprise_ai_controls, configurable, default: false) && @return_to.present?
          update_settings_copilot_policy_enterprise_path(configurable, return_to: @return_to)
        else
          update_settings_copilot_policy_enterprise_path(configurable)
        end
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
