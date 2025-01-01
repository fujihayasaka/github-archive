# typed: strict
# frozen_string_literal: true

module Dashboard
  class NewRepositoryForm < ApplicationForm
    extend T::Sig

    sig do
      params(
        user: User,
        validation_path: String,
        return_to_on_error: String,
        analytics_on_submit: T::Hash[String, String]
      ).void
    end
    def initialize(user:, validation_path:, return_to_on_error:, analytics_on_submit: {})
      @user = user
      @validation_path = validation_path
      @return_to_on_error = return_to_on_error
      @analytics_on_submit = analytics_on_submit
    end

    sig { returns(User) }
    attr_reader :user

    sig { returns(String) }
    attr_reader :validation_path

    sig { returns(String) }
    attr_reader :return_to_on_error

    sig { returns(T::Hash[String, String]) }
    attr_reader :analytics_on_submit

    form do |new_repository_form|
      T.bind(self, NewRepositoryForm)

      new_repository_form.hidden(
        name: :owner,
        value: user.display_login,
      )

      new_repository_form.hidden(
        name: :return_to_on_error,
        value: return_to_on_error,
      )

      new_repository_form.hidden(
        name: :experiment_form,
        value: "true",
      )

      new_repository_form.text_field(
        name: :"repository[name]",
        label: "Repository name",
        required: true,
        auto_check_src: validation_path,
        placeholder: "name your new repository...",
        classes: "js-prevent-default-behavior",
      )

      new_repository_form.radio_button_group(name: "repository[visibility]") do |radio_group|
        radio_group.radio_button(
          value: "public",
          label: "Public",
          caption: "Anyone on the internet can see this repository",
          font_size: 6,
        )
        radio_group.radio_button(
          value: "private",
          label: "Private",
          caption: "You choose who can see and commit to this repository",
          checked: true,
          font_size: 6,
        )
      end

      new_repository_form.submit(
        name: :submit,
        label: "Create a new repository",
        scheme: :primary,
        font_size: 6,
        data: analytics_on_submit,
      )
    end
  end
end
