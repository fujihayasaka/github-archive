# typed: true
# frozen_string_literal: true

class Organizations::Settings::CodespacesPolicyForm::ConstraintRow::AllowedValuesComponent < ApplicationComponent
  attr_reader :constraint, :data_key_name, :existing_policy

  def initialize(constraint:, data_key_name:, existing_policy: nil)
    @constraint = constraint
    @data_key_name = data_key_name
    @existing_policy = existing_policy
  end

  def existing_policy_has_allowed_values_stored?
    return false if existing_policy.nil?
    return false if existing_policy_constraint.nil?

    constraint_allowable_values =
      constraint[:allowable_values].map { |value| value.name.to_s }

    (existing_policy_constraint[:allowed_values] & constraint_allowable_values).any?
  end

  def existing_policy_has_selected_value?(value)
    return false if existing_policy.nil?
    return false if existing_policy_constraint.nil?

    existing_policy_constraint[:allowed_values].include?(value.name.to_s)
  end

  def existing_allowed_values_text
    constraint[:allowable_values]
      .select { |value| existing_policy_has_selected_value?(value) }
      .map(&:display_name)
      .join(", ")
  end

  private

  memoize def existing_policy_constraint
    return unless existing_policy.present?

    existing_policy[:current_policy_constraints].find { |pc| pc[:name] == constraint[:name] }
  end
end
