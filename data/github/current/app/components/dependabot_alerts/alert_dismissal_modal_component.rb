# typed: strict
# frozen_string_literal: true

module DependabotAlerts
  class AlertDismissalModalComponent < ApplicationComponent
    SystemArgumentValues = T.type_alias { T.any(String, Integer, Symbol, T::Boolean, T::Array[T.any(String, Integer, Symbol, T::Boolean)]) }
    SystemArguments = T.type_alias { T::Hash[Symbol, SystemArgumentValues] }

    sig { returns(String) }
    attr_reader :dismissal_path

    sig { returns(SystemArguments) }
    attr_reader :button_system_arguments, :bulk_items_system_arguments, :system_arguments

    renders_one :summary

    sig { params(dismissal_path: String, button_system_arguments: SystemArguments, bulk_items_system_arguments: SystemArguments, system_arguments: SystemArgumentValues).void }
    def initialize(dismissal_path:, button_system_arguments: {}, bulk_items_system_arguments: {}, **system_arguments)
      @dismissal_path = dismissal_path
      @button_system_arguments = button_system_arguments
      @bulk_items_system_arguments = bulk_items_system_arguments
      @system_arguments = system_arguments
    end

    sig { returns(T::Hash[T.any(String, Symbol), String]) }
    def dismiss_reasons
      RepositoryVulnerabilityAlert::DISMISS_REASONS
    end

    sig { returns(String) }
    def close_id
      "close-alert-menu"
    end
  end
end
