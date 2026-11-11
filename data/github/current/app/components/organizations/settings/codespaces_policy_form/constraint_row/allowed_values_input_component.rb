# typed: true
# frozen_string_literal: true

class Organizations::Settings::CodespacesPolicyForm::ConstraintRow::AllowedValuesInputComponent < Organizations::Settings::CodespacesPolicyForm::ConstraintRow::AllowedValuesComponent
  attr_reader :constraint, :data_key_name, :input_placeholder, :existing_policy

  def initialize(constraint:, data_key_name:, input_placeholder:, existing_policy: nil)
    @constraint = constraint
    @data_key_name = data_key_name
    @existing_policy = existing_policy
    @input_placeholder = input_placeholder
  end

  def existing_allowed_values_text
    return "None" if existing_allowed_values.blank?

    existing_allowed_values.join(", ")
  end

  def existing_allowed_values
    return [] if existing_policy.nil?
    return [] if existing_policy_constraint.nil?

    existing_policy_constraint[:allowed_values]
  end
end
