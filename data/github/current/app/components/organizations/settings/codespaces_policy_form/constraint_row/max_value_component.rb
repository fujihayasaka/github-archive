# typed: true
# frozen_string_literal: true

class Organizations::Settings::CodespacesPolicyForm::ConstraintRow::MaxValueComponent < ApplicationComponent
  attr_reader :constraint_config, :data_key_name, :existing_policy

  def initialize(constraint_config:, data_key_name:, existing_policy: nil)
    @constraint_config = constraint_config
    @data_key_name = data_key_name
    @existing_policy = existing_policy
  end

  def current_maximum_value
    return constraint_config[:maximum_allowable_value] unless has_existing_policy_constraint?
    value = existing_policy_constraint[:maximum_value]
    value = value.minutes.in_days.to_i if constraint_config[:name] == Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD
    value.to_s
  end

  def has_existing_policy_constraint?
    existing_policy_constraint.present?
  end

  def value_category
    case constraint_config[:name]
    when Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT then "minute"
    when Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD then "day"
    else ""
    end
  end

  def error_message
    max = constraint_config[:maximum_allowable_value]
    between_phrase = "must be between #{constraint_config[:minimum_allowable_value]} and #{max}"

    case constraint_config[:name]
    when Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT
      "Timeout #{between_phrase} #{value_category.pluralize(max)}"
    when Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD
      "Retention period #{between_phrase} #{value_category.pluralize(max)}"
    when Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS
      "Codespaces limit #{between_phrase} #{value_category.pluralize(max)}"
    else
      "Value #{between_phrase}"
    end
  end

  private

  memoize def existing_policy_constraint
    return nil if existing_policy.nil?
    return nil if existing_policy[:current_policy_constraints].nil?

    existing_policy[:current_policy_constraints].find do |current_constraint|
      current_constraint[:name] == constraint_config[:name]
    end
  end
end
