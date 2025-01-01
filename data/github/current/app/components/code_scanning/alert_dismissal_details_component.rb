# typed: true
# frozen_string_literal: true

class CodeScanning::AlertDismissalDetailsComponent < ApplicationComponent # TODO can we switch to ViewComponent::Base?
  include CodeScanningHelper

  attr_reader :body_system_arguments, :close_path, :button_label, :number, :pull_request_review_thread, :pluralize, :ref_names, :system_arguments, :summary_button_param, :summary_system_arguments, :form_turbo_frame, :require_dismissal_comment

  renders_one :summary

  def initialize(
    close_path:,
    button_label:,
    number: nil,
    pull_request_review_thread: nil,
    ref_names: [],
    pluralize: false,
    summary_button: true,
    summary_system_arguments: {},
    body_system_arguments: {},
    form_turbo_frame: "_self",
    require_dismissal_comment: false,
    **system_arguments
  )

    @close_path = close_path
    @button_label = button_label
    @number = number
    @pull_request_review_thread = pull_request_review_thread
    @ref_names = ref_names || []
    @pluralize = pluralize
    @form_turbo_frame = form_turbo_frame
    @require_dismissal_comment = require_dismissal_comment

    @summary_button_param = summary_button
    @summary_system_arguments = summary_system_arguments

    @body_system_arguments = body_system_arguments
    @body_system_arguments[:tag] = :div unless @body_system_arguments.key?(:tag)
    @body_system_arguments[:classes] = "SelectMenu" unless @body_system_arguments.key?(:classes)

    @system_arguments = system_arguments
    @system_arguments[:reset] = true unless @system_arguments.key?(:reset)
    @system_arguments[:overlay] = :default unless @system_arguments.key?(:overlay)
    @system_arguments[:classes] = "dropdown" unless @system_arguments.key?(:classes)
  end
end
