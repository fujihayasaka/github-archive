# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/config/ignore_condition"
require "github_helpers"

class FindOrCreateIgnoreCondition
  def initialize(pull_request:, precision_to_ignore: nil, comment_id: nil, dep_name: nil)
    @pull_request = pull_request
    @precision_to_ignore = precision_to_ignore
    @comment_id = comment_id
    @dep_name = dep_name
  end

  def run
    pull_request.updated_dependencies.map do |dep|
      process_dependency(dep) if dependency_to_ignore?(dep)
    end.compact.any?
  end

  private

  attr_reader :pull_request, :precision_to_ignore, :comment_id

  def dependency_to_ignore?(dep)
    @dep_name.nil? || dep.name.casecmp?(@dep_name)
  end

  def process_dependency(dep)
    current_version = current_version_for(dep)
    requirement = requirement_to_ignore(dep)
    return unless requirement

    if should_update_requirements?(current_version, requirement)
      reqs = requirement.requirements.reject { |r| r.first == ">=" }.map(&:join)
      reqs << "> #{current_version}"
      requirement = requirement_class.new(reqs)
    end

    find_or_create_ignore_condition(dependency: dep, requirement: requirement)
  end

  def should_update_requirements?(current_version, requirement)
    valid_version?(current_version) && requirement.satisfied_by?(version_class.new(current_version))
  end

  def requirement_to_ignore(dep)
    new_version = dep.version
    current_version = current_version_for(dep)

    if precision_to_ignore == 1 && valid_version?(current_version)
      requirement_class.new("> #{current_version}")
    elsif precision_to_ignore == 1
      requirement_class.new(Dependabot::Config::IgnoreCondition::ALL_VERSIONS)
    elsif valid_version?(new_version)
      requirement_class.new(
        IgnoreConditionBuilder.new(dep: dep, precision_to_ignore: precision_to_ignore,
                                   version: version_class.new(new_version)).run
      )
    end
  end

  def current_version_for(dep) # rubocop:disable Metrics/PerceivedComplexity
    return dep.version if pull_request.in_state?(:merged)
    return dep.previous_version if dep.previous_version

    # Find a version that satisfies the current requirements, and treat
    # that as our current version. Ensures we will still have a resolvable
    # range when combining existing requirements with the ignore condition in
    # future resolution runs.
    dep.previous_requirements.map { |r| r.fetch("requirement") }.compact.
      flat_map { |req_str| requirement_class.requirements_array(req_str) }.
      flat_map(&:requirements).
      reject { |req_array| req_array.first.start_with?("<") }.
      map(&:last).
      max&.to_s
  end

  def valid_version?(version)
    return false if version.blank?

    version_class.correct?(version)
  end

  def numeric_version?(version)
    return false if version.blank?

    Gem::Version.correct?(version)
  end

  def find_or_create_ignore_condition(dependency:, requirement:)
    existing_ic =
      pull_request.update_config.ignore_conditions.
      find_by(
        dependency_name: dependency.name,
        version_requirement: requirement.to_s,
      )

    return existing_ic if existing_ic

    pull_request.update_config.ignore_conditions.
      create!(
        dependency_name: dependency.name,
        version_requirement: requirement.to_s,
        issue_comment_id: comment_id,
      )
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def version_class
    Dependabot::Utils.version_class_for_package_manager(package_manager)
  end

  def requirement_class
    Dependabot::Utils.requirement_class_for_package_manager(package_manager)
  end

  def package_manager
    @package_manager ||= pull_request.update_config.package_manager
  end
end
