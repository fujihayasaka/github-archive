# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    class FormActionsComponent < ApplicationComponent
      attr_reader :status, :mode, :force_disable_button, :custom_pattern_owner, :selected_repo_ids

      include SecretScanningCustomPatternsHelper

      def initialize(
        status:,
        mode:,
        force_disable_button:,
        custom_pattern_owner:,
        selected_repo_ids:
      )
        @status = status
        @mode = mode
        @force_disable_button = force_disable_button
        @custom_pattern_owner = custom_pattern_owner
        @selected_repo_ids = selected_repo_ids
      end

      def form_class
        "custom-pattern-form"
      end

      def form_button_js_class
        return "js-save-and-dry-run-button" if changes_not_publishable?
        "js-custom-pattern-submit-button"
      end

      def form_button_disable_with
        return "Cancelling..." if can_cancel_dry_run?
        return "Publishing..." if @status == :COMPLETED
        "Saving..."
      end

      def form_button_disabled?
        return true if @force_disable_button

        return false if can_cancel_dry_run?
        return false if @status == :COMPLETED || @status == :CANCELLED || @status == :FAILED || @status == :NOT_DRY_RUN

        true # button is disabled by default, and enabled via js if pattern publish conditions are satisfied.
      end

      def form_button_text
        save_dry_run_text = "Save and dry run"

        if @mode == :create
          return save_dry_run_text
        elsif @mode == :edit
          return "Save changes"
        end

        return "Cancel dry run" if can_cancel_dry_run? || @status == :UNKNOWN
        return save_dry_run_text if changes_not_publishable?

        if @status == :COMPLETED
          return "Publish pattern" if @mode == :unpublished
          return "Publish changes" if @mode == :published
        end
      end

      def show_form_button_message_icon?
        return false if @mode == :create
        return false if @status == :FAILED
        true
      end

      def form_button_message
        case @mode
        when :create
          nil
        when :edit
          "Saved. Any alerts no longer matching the updated pattern will be closed."
        when :unpublished
          return pattern_saved_message if can_cancel_dry_run?
          return "Dry run successfully cancelled." if @status == :CANCELLED
          nil
        when :published
          return nil if @status == :UNKNOWN
          return pattern_saved_message if can_cancel_dry_run?
          return "Dry run successfully cancelled." if @status == :CANCELLED
          "Published. Any alerts no longer matching the updated pattern will be closed."
        else nil
        end
      end

      def pattern_saved_message
        "Pattern saved. The dry run is in progress, you'll get an email when results are available."
      end

      def form_button_scheme
        return :danger if can_cancel_dry_run?
        return :default if @status == :UNKNOWN && (mode == :unpublished || mode == :published)
        :primary
      end

      def allow_update_after_dry_run?
        return false unless @mode == :unpublished || @mode == :published

        return true if @status == :COMPLETED

        false
      end

      def can_cancel_dry_run?
        SecretScanningCustomPatternsHelper::allow_dry_run_cancellation?(@mode, @status)
      end

      def changes_not_publishable?
        @status == :CANCELLED || @status == :FAILED || @status == :NOT_DRY_RUN
      end

      def show_repo_selector_dialog_button_as_primary?
        return false if @custom_pattern_owner.is_a?(Repository)

        case @mode
        when :create
          return true
        when :edit
          return false
        when :published, :unpublished
          return true if changes_not_publishable?
        end

        false
      end
    end
  end
end
