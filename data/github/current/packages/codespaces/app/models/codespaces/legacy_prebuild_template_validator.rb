# typed: true
# frozen_string_literal: true

module Codespaces
  class LegacyPrebuildTemplateValidator < ActiveModel::Validator

    REQUIRED_ATTRIBUTES = [:branch, :location, :oid, :repository, :vscs_target]

    def validate(record)
      validate_presence(record)
      validate_plan(record)
      Codespaces::VscsTargetValidationHelper.validate(record)
    end

    def validate_presence(record)
      REQUIRED_ATTRIBUTES.each { |field| record.errors.add(field, "must be present") if record.send(field).blank? }
    end

    def validate_plan(record)
      if record.respond_to?(:plan)
        record.errors.add(:plan, "No plan found for location and vscs_target") unless record.plan.present?
      elsif record.vscs_target.blank? || record.location.blank? || Codespaces::Plan.for(location: record.location, vscs_target: record.vscs_target).nil?
        record.errors.add(:plan, "No plan found for location and vscs_target")
      end
    end
  end
end
