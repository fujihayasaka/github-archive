# typed: true
# frozen_string_literal: true

class Copilot::SummarizeBannerStaffbarComponent < ApplicationComponent
  extend T::Sig

  sig { params(icon: Symbol, default_prompt: String, test_selector: String).void }
  def initialize(icon:, default_prompt:, test_selector: "copilot-summarize-banner-staffbar-controls")
    @icon = icon
    @default_prompt = default_prompt
    @test_selector = test_selector
  end

  class SummaryOptionsForm < ApplicationForm
    extend T::Sig

    form do |f|
      f.text_area(
        name: "copilot_summary_prompt",
        id: "copilot_summary_prompt",
        label: "Prompt:",
        caption: "Custom instructions for what the model should do. If omitted, the default prompt will be used.",
        rows: 7,
        value: @default_prompt,
      )
      f.submit(
        label: "Summarize using these options",
        name: "",
        scheme: :primary,
        data: { target: "copilot-summarize-banner-staffbar-controls.customPromptSummarizeButton" },
      )
    end

    sig { params(default_prompt: String).void }
    def initialize(default_prompt:)
      @default_prompt = default_prompt
    end
  end

  private

  sig { returns String }
  attr_reader :default_prompt, :test_selector

  sig { returns Symbol }
  attr_reader :icon

  sig { returns T.nilable(T::Boolean) }
  def render?
    logged_in? && (current_user.site_admin? || current_user.employee?) &&
      user_feature_enabled?(:copilot_summary_custom_prompt)
  end
end
