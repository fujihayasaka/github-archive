# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/config/ignore_condition"

class IgnoreCondition < ApplicationRecord
  belongs_to :update_config

  validates :update_config, presence: true
  validates :dependency_name, presence: true
  validates :update_types, absence: true, if: -> { version_requirement.present? }
  validates :update_types, presence: true, if: -> { version_requirement.blank? }
  validates :version_requirement, absence: true, if: -> { update_types.present? }
  validates :version_requirement, presence: true, if: -> { update_types.blank? }
  validate :version_requirement_is_a_valid_requirement

  scope :from_config_file, -> { where(from_config_file: true) }

  def parsed_version_requirements
    return [] if version_requirement.blank?

    requirement_class.requirements_array(version_requirement)
  rescue requirement_class::BadRequirementError
    []
  end

  def includes?(version)
    return false if version_requirement.blank?
    return true if version_requirement == Dependabot::Config::IgnoreCondition::ALL_VERSIONS
    return false unless version_class.correct?(version)

    version = version_class.new(version)
    parsed_version_requirements.any? { |r| r.satisfied_by?(version) }
  end

  def source
    config_file_path = update_config.repo.config_file_path || ".github/dependabot.yml"
    return config_file_path if from_config_file?

    "@dependabot ignore command"
  end

  private

  def version_requirement_is_a_valid_requirement
    return if version_requirement.nil?

    requirement_class.requirements_array(version_requirement)
  rescue requirement_class::BadRequirementError
    errors.add(:version_requirement, "must be a valid requirement")
  end

  def version_class
    @version_class ||=
      Dependabot::Utils.version_class_for_package_manager(
        update_config.package_manager,
      )
  end

  def requirement_class
    @requirement_class ||=
      Dependabot::Utils.requirement_class_for_package_manager(
        update_config.package_manager,
      )
  end
end
