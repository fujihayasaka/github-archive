# typed: strict
# frozen_string_literal: true

module EditRepositories
  module DeployKeys
    class NewKeyForm < ApplicationForm
      form do |new_key_form|
        new_key_form.text_field(
          name: :title,
          label: "Title"
        )

        new_key_form.text_area(
          name: :key,
          label: "Key",
          rows: 9,
        )

        new_key_form.check_box(
          name: :read_only,
          label: "Allow write access",
          value: 0,
          unchecked_value: 1
        )

        new_key_form.submit(
          name: :key_submit,
          label: "Add key",
          scheme: :primary
        )
      end
    end
  end
end
