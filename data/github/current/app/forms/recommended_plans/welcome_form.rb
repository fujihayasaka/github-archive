# typed: strict
# frozen_string_literal: true

module RecommendedPlans
  class WelcomeForm < ApplicationForm
    ERROR_MESSAGES = T.let({
      size: "Please select the number of team members",
      user_self_description: "Select an option"
    }.freeze, T::Hash[Symbol, String])

    sig do
      params(
        current_user: User,
        validation_errors: T::Set[Symbol],
      ).void
    end
    def initialize(current_user:, validation_errors: T.let(Set.new, T::Set[Symbol]))
      @validation_errors = validation_errors
      @current_user = current_user
    end

    sig { returns(T::Set[Symbol]) }
    attr_reader :validation_errors

    sig { returns(User) }
    attr_reader :current_user

    sig { params(key: Symbol).returns(T.nilable(String)) }
    def validation_message(key)
      ERROR_MESSAGES[key] if validation_errors.include?(key) && ERROR_MESSAGES.key?(key)
    end

    sig { returns(T::Boolean) }
    def nux_user_self_description_enabled?
      current_user.feature_enabled?(:nux_user_self_description)
    end

    form do |welcome_form|
      T.bind(self, WelcomeForm)
      welcome_form.radio_button_group(
        name: :user_self_description,
        label: "How would you describe yourself?",
        class: "FormControl-radio-group-wrap--tiles FormControl-radio-group-wrap--tiles-two",
        validation_message: validation_message(:user_self_description),
      ) do |user_self_description|
        user_self_description.radio_button(
          label: "Student",
          value: "education_student",
          class: "FormControl-radio--tile"
        )

        user_self_description.radio_button(
          label: "Teacher",
          value: "education_teacher",
          class: "FormControl-radio--tile"
        )

        user_self_description.radio_button(
          label: "Working developer",
          value: "working_developer",
          class: "FormControl-radio--tile"
        )

        user_self_description.radio_button(
          label: "Other",
          value: "other",
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
