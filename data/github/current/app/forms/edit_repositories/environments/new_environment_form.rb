# typed: true
# frozen_string_literal: true

module EditRepositories
  module Environments
    class NewEnvironmentForm < ApplicationForm
      form do |new_environment_form|
        new_environment_form.text_field(
          name: :name,
          label: "Name",
          required: true
        )

        new_environment_form.submit(
          name: :submit,
          label: "Configure environment",
          scheme: :primary
        )
      end
    end
  end
end
