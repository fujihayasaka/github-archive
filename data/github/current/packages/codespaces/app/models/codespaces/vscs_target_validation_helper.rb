# typed: true
# frozen_string_literal: true

module Codespaces
  module VscsTargetValidationHelper
    def self.validate(record)
      validate_inclusion(record)
      validate_target_url_and_vscs_target(record)
    end

    private_class_method def self.validate_inclusion(record)
      if !Codespaces::Vscs.targets.include?(record.vscs_target) && record.vscs_target.present?
        record.errors.add(:vscs_target, "'#{record.send(:vscs_target)}' is not a valid target")
      end
    end

    private_class_method def self.validate_target_url_and_vscs_target(record)
      vscs_target, vscs_target_url = record.vscs_target&.to_sym, record.vscs_target_url
      if vscs_target == :local && vscs_target_url.blank?
        record.errors.add(:vscs_target_url, "must be present when vscs_target is local")
      elsif vscs_target != :local && vscs_target_url.present?
        record.errors.add(:vscs_target_url, "must be blank when vscs_target is not local")
      end
    end
  end
end
