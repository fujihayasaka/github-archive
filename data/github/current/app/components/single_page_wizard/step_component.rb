# typed: true
# frozen_string_literal: true

module SinglePageWizard
  class StepComponent < ApplicationComponent
    attr_reader :title, :id, :cancel_text, :previous_text, :next_text, :show_cancel_button, :show_previous_button, :hide_next_button, :inside_buttons, :step_icon, :warn_unsaved, :show_banner, :banner_text

    #
    # Options:
    #
    # title - Text to use for the title of the step
    # cancel_text - Text to use for the cancel button caption
    # previous_text - Text to use for the previous button caption
    # next_text - Text to use for the next button caption
    # show_cancel_button - show/hide the cancel button
    # show_previous_button - show/hide the previous button
    # hide_next_button - show/hide the next button
    # inside_buttons - Whether to display the next/cancel buttons inside of the step component (true) or outside (false)
    # step_icon - The octicon to show above the title in the step. (Default: no icon)
    # warn_unsaved - will pop up a warning before performing a browser action like back, close, refresh (uses cancel_confirm_text if applicable)
    # show_banner - Whether to show a banner above the step component
    # banner_text - Text to show in the banner above the step component
    #
    def initialize(title: "", id: nil, cancel_text: "Cancel", previous_text: "Previous", next_text: "Next", show_cancel_button: false, show_previous_button: false, hide_next_button: false, inside_buttons: false, step_icon: "", warn_unsaved: false, show_banner: false, banner_text: "")
      @title = title
      @id = id
      @cancel_text = cancel_text
      @previous_text = previous_text
      @next_text = next_text
      @show_cancel_button = show_cancel_button
      @show_previous_button = show_previous_button
      @hide_next_button = hide_next_button
      @inside_buttons = inside_buttons
      @step_icon = step_icon
      @warn_unsaved = warn_unsaved
      @show_banner = show_banner
      @banner_text = banner_text
    end

    def cancel_button
      Primer::ButtonComponent.new(
        scheme: :invisible,
        mr: 2,
        hidden: true,
        w: :fit,
        classes: "wizard-step-button",
        data: {
          action: "click:single-page-wizard-step#onCancel",
          target: "single-page-wizard-step.cancelButton"
        }).with_content(cancel_text)
    end

    def previous_button
      Primer::ButtonComponent.new(
        mr: 2,
        hidden: true,
        w: :fit,
        classes: "wizard-step-button",
        data: {
          action: "click:single-page-wizard-step#onPrevious",
          target: "single-page-wizard-step.previousButton"
        }).with_content(previous_text)
    end

    def next_button
      Primer::ButtonComponent.new(
        scheme: :primary,
        display: :flex,
        align_items: :center,
        w: :fit,
        classes: "wizard-step-button",
        data: {
          action: "click:single-page-wizard-step#onNext",
          target: "single-page-wizard-step.nextButton"
        })
    end
  end
end
