# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class RuleNameForm < ApplicationForm
    form do |f|
      T.bind(self, RuleNameForm)

      f.text_field(
        name: :name,
        label: "Rule name",
        placeholder: "Add a rule name",
        autocomplete: "off",
        validation_message: validation_message(f.builder.object),
        mt: 1,
        mb: 1,
        data: {
          target: "dependabot-alert-rule-form.name",
        }
      )
    end

    def validation_message(model)
      if model.errors.added?(:name, :blank)
        "Enter rule name"
      end
    end
  end
end
