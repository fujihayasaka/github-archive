# typed: true
# frozen_string_literal: true

module SinglePageWizard
  class WizardComponent < ApplicationComponent
    attr_reader :complete_url, :cancel_url, :cancel_confirm_text, :show_last_step_celebration, :horizontal_steps

    renders_many :steps, StepComponent
    delegate :javascript_bundle, to: :helpers

    #
    # Options:
    #
    # complete_url - Url used to redirect on complete button (final step 'next') click (if undefined, you must handle the `single-page-wizard-complete` event with a wrapping catalyst component)
    # cancel_url - Url used to redirect on cancel button click (if undefined, you must handle the `single-page-wizard-cancel` event with a wrapping catalyst component)
    # cancel_confirm_text - Text displayed in confirm dialog before cancel succeeds (if undefined, no confirmation will be applied before navigating to the cancel_url)
    # show_last_step_celebration - Whether or not to show confetti animation on the last step
    # horizontal_steps - Whether to display the step/progress indicators horizontally (true) or vertically (false)
    #
    # Slots:
    #
    # step - Renders StepComponent as children (see 'single_page_wizard/step_component.rb')
    #
    # Example Usage:
    #
    # <%= render SinglePageWizard::WizardComponent.new do |c| %>
    #   <% c.with_step(title: "Step 1") do %>
    #     <div>Step 1 Content</div>
    #   <% end %>
    # <% end %>
    #
    def initialize(complete_url: "", cancel_url: "", cancel_confirm_text: nil, show_last_step_celebration: false, horizontal_steps: false, test_selector: nil)
      @complete_url = complete_url
      @cancel_url = cancel_url
      @cancel_confirm_text = cancel_confirm_text
      @show_last_step_celebration = show_last_step_celebration
      @horizontal_steps = horizontal_steps
      @test_selector = test_selector
    end
  end
end
