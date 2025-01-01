# typed: strict
# frozen_string_literal: true

module RecommendedPlans
  class WelcomeForm < ApplicationForm
    extend T::Sig

    ERROR_MESSAGES = T.let({
      education_type: "Select an option",
      size: "Please select the number of team members"
    }.freeze, T::Hash[Symbol, String])

    sig { params(validation_errors: T::Set[Symbol]).void }
    def initialize(validation_errors: T.let(Set.new, T::Set[Symbol]))
      @validation_errors = validation_errors
    end

    sig { returns(T::Set[Symbol]) }
    attr_reader :validation_errors

    sig { params(key: Symbol).returns(T.nilable(String)) }
    def validation_message(key)
      ERROR_MESSAGES[key] if validation_errors.include?(key) && ERROR_MESSAGES.key?(key)
    end

    form do |welcome_form|
      T.bind(self, WelcomeForm)

      welcome_form.radio_button_group(
        name: :education_type,
        label: "How would you describe yourself?",
        class: "FormControl-radio-group-wrap--tiles FormControl-radio-group-wrap--tiles-two",
        validation_message: validation_message(:education_type),
      ) do |education_type|

        education_type.radio_button(
          label: "N/A",
          value: "education_na",
          class: "FormControl-radio--tile"
        )

        education_type.radio_button(
          label: "Student",
          value: "education_student",
          class: "FormControl-radio--tile"
        )

        education_type.radio_button(
          label: "Teacher",
          value: "education_teacher",
          class: "FormControl-radio--tile"
        )
      end

      welcome_form.radio_button_group(
        name: :size,
        label: "How many team members will be working with you?",
        class: "FormControl-radio-group-wrap--tiles FormControl-radio-group-wrap--tiles-three",
        validation_message: validation_message(:size),
      ) do |size|
        size.radio_button(
          label: "Just me",
          value: "1",
          class: "FormControl-radio--tile"
        )

        size.radio_button(
          label: "2-5",
          value: "2-5",
          class: "FormControl-radio--tile"
        )

        size.radio_button(
          label: "5-10",
          value: "5-10",
          class: "FormControl-radio--tile"
        )

        size.radio_button(
          label: "10-20",
          value: "10-20",
          class: "FormControl-radio--tile"
        )

        size.radio_button(
          label: "20-50",
          value: "20-50",
          class: "FormControl-radio--tile"
        )

        size.radio_button(
          label: "50+",
          value: "50+",
          class: "FormControl-radio--tile"
        )
      end

      welcome_form.submit(
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
