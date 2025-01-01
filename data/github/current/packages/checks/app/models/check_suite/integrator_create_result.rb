# typed: true
# frozen_string_literal: true

# creating for an integrator has three potential outcomes
# - created
# - invalid
# - already existing - for apps with multiple_check_suites_per_sha_enabled? using external_id
class CheckSuite::IntegratorCreateResult
  attr_reader :errors, :record
  DUPLICATE_SHA_MESSAGE = "A CheckSuite already exists for this sha"
  CONFLICT_MESSAGE = "CheckSuite has conflicting resources"

  def initialize(record, existing: false)
    @record = record
    # errors is mutable, so create a new one to keep this Result as an accurate record of what happened
    @errors = ActiveModel::Errors.new(record)
    @errors.merge!(record.errors)
    @existing = existing
  end

  def existing?
    @existing
  end

  def success?
    errors.empty? && @record.persisted?
  end

  def duplicate_for_sha?
    errors[:head_sha].find { |m| m == DUPLICATE_SHA_MESSAGE }
  end

  def conflict?
    errors[:base].find { |m| m == CONFLICT_MESSAGE }
  end

  def check_suite
    @record
  end
end
