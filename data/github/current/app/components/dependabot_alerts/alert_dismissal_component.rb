# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class AlertDismissalComponent < ApplicationComponent
    attr_reader :dismissal_path, :body_system_arguments, :system_arguments, :summary_button_param, :summary_system_arguments, :bulk_items_system_arguments, :pluralize, :id

    renders_one :summary

    sig do
      params(
        id: String,
        dismissal_path: String,
        pluralize: T::Boolean,
        summary_button: T::Boolean,
        summary_system_arguments: T.untyped,
        body_system_arguments: T.untyped,
        bulk_items_system_arguments: T.untyped,
        system_arguments: T.untyped
      ).void
    end
    def initialize(
      id:,
      dismissal_path:,
      pluralize: false,
      summary_button: true,
      summary_system_arguments: {},
      body_system_arguments: {},
      bulk_items_system_arguments: {},
      **system_arguments
    )
      @dismissal_path = dismissal_path
      @pluralize = pluralize
      @summary_button_param = summary_button
      @summary_system_arguments = summary_system_arguments
      @bulk_items_system_arguments = bulk_items_system_arguments

      @body_system_arguments = body_system_arguments
      @body_system_arguments[:tag] = :"details-menu" unless @body_system_arguments.key?(:tag)
      @body_system_arguments[:classes] = "SelectMenu" unless @body_system_arguments.key?(:classes)
      @id = id

      @system_arguments = system_arguments
      @system_arguments[:reset] = true unless @system_arguments.key?(:reset)
      @system_arguments[:overlay] = :default unless @system_arguments.key?(:overlay)
      @system_arguments[:classes] = "dropdown" unless @system_arguments.key?(:classes)
    end

    sig { returns(T.untyped) }
    def dismiss_reasons
      RepositoryVulnerabilityAlert::DISMISS_REASONS
    end

    sig { returns(String) }
    def close_id
      "close-alert-menu-#{id}"
    end
  end
end
