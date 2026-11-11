# frozen_string_literal: true

require "dependabot/utils"
require "serialized_bytesize_validator"

class UpdatedDependency < ApplicationRecord
  MAX_CHARS_FOR_NAME = 190
  REQUIREMENTS_MAX_BYTES = 65_535

  belongs_to :pull_request

  attribute :directory, StringFromBinary.new

  validates :directory, length: { maximum: 1024 }, allow_nil: true
  validates :pull_request, presence: true
  validates :name, presence: true,
                   length: {
                     maximum: 190,
                     message: lambda { |_object, data|
                       "is too long (max: #{MAX_CHARS_FOR_NAME} actual: #{data[:value].length})"
                     },
                   }
  validates :version, presence: true, unless: -> { removed }
  validates :non_breaking_if_semver, inclusion: { in: [true, false] }
  validates :package_manager, inclusion: { in: PackageManagers::ALL }

  validates :requirements, serialized_bytesize: { maximum: REQUIREMENTS_MAX_BYTES }
  validates :previous_requirements, serialized_bytesize: { maximum: REQUIREMENTS_MAX_BYTES }

  before_validation :set_non_breaking_if_semver

  delegate :production?, to: :to_dependabot_dependency

  serialize :requirements, coder: JSON
  serialize :previous_requirements, coder: JSON

  def self.from_dependabot_dependency(dependency)
    new(
      name: dependency.name,
      package_manager: dependency.package_manager,
      previous_requirements: dependency.previous_requirements,
      previous_version: dependency.previous_version,
      removed: dependency.removed?,
      requirements: dependency.requirements,
      directory: dependency.directory,
      version: dependency.version,
    )
  end

  def to_dependabot_dependency
    Dependabot::Dependency.new(
      name: name,
      version: version,
      package_manager: package_manager,
      requirements: requirements,
      directory: directory,
      previous_requirements: previous_requirements,
      previous_version: previous_version,
      removed: removed
    )
  end

  def version_class
    Dependabot::Utils.version_class_for_package_manager(package_manager)
  end

  def requirement_class
    Dependabot::Utils.requirement_class_for_package_manager(package_manager)
  end

  private

  def feature_enabled?(feature)
    pull_request.repo.feature_enabled?(feature) ||
      pull_request.repo.account.feature_enabled?(feature)
  end

  # rubocop:disable Metrics/AbcSize
  # rubocop:disable Metrics/PerceivedComplexity
  def set_non_breaking_if_semver
    self.non_breaking_if_semver =
      if previous_version.nil? || version.nil? then false
      elsif PackageManagers::ALL.exclude?(package_manager) then false
      elsif !version_class.correct?(previous_version) then false
      elsif !version_class.correct?(version) then false
      elsif version_class.new(version).prerelease? then false
      elsif version_class.new(previous_version).prerelease? then false
      elsif version.split(".").first != previous_version.split(".").first
        false
      else
        version_class.new(previous_version) >= version_class.new("1.0.0")
      end
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/PerceivedComplexity
end
