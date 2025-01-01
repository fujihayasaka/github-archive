# typed: strict
# frozen_string_literal: true

module RecommendedPlans
  class PurposeForm < ApplicationForm
    CAPTION = "Select up to 2 options"
    VALIDATION_MESSAGE = "You can only select 2 options"
    GOALS = T.let([
            ["start_project", "Start a new project"],
            ["enterprise_security", "Start or expand my business"],
            ["use_copilot", "Use GitHub Copilot"],
            ["community", "Connect with other developers"],
            ["contribute", "Contribute to Open Source projects"],
        ].freeze, T::Array[[String, String]])

    sig { params(show_validation_message: T::Boolean).void }
    def initialize(show_validation_message: false)
      @show_validation_message = show_validation_message
    end

    sig { returns(T::Boolean) }
    attr_reader :show_validation_message

    sig { returns(T.nilable(String)) }
    def validation_message
      VALIDATION_MESSAGE if show_validation_message
    end

    sig { returns(T.nilable(String)) }
    def caption
      CAPTION if validation_message.blank?
    end

    form do |purpose_form|
      T.bind(self, PurposeForm)

      purpose_form.check_box_group(
        name: :purpose,
        label: "What are the top 2 things you want to do with GitHub?",
        class: "FormControl-checkbox-group-wrap--tiles FormControl-checkbox-group-wrap--tiles-one",
        caption: caption,
        validation_message: validation_message,
      ) do |goal|
        GOALS.each { |name, label| goal.check_box(label: label, value: name) }
      end

      purpose_form.submit(
        name: :submit,
        label: "Continue",
        block: true,
        display: :flex,
        class: "btn-mktg",
        style: "background-color: #4969ed !important; height: 48px !important;"
      )
    end
  end
end
