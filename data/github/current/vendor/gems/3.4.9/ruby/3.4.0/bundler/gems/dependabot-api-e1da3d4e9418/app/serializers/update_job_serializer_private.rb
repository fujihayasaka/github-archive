# frozen_string_literal: true

require "github_helpers"
require "dependabot/utils"

class UpdateJobSerializerPrivate < ActiveModel::Serializer # rubocop:disable Metrics/ClassLength
  attributes %i(
    id
    command
    allowed_updates
    commit_message_options
    credentials_metadata
    debug
    dependencies
    dependency_groups
    dependency_group_to_refresh
    existing_pull_requests
    existing_group_pull_requests
    experiments
    ignore_conditions
    lockfile_only
    max_updater_run_time
    package_manager
    proxy_log_response_body_on_auth_failure
    requirements_update_strategy
    reject_external_code
    security_advisories
    security_updates_only
    source
    updating_a_pull_request
    update_subdependencies
    vendor_dependencies
    enable_beta_ecosystems
    repo_private
    cooldown
    multi_ecosystem_update
    exclude_paths
  )

  delegate :allowed_updates, to: :object

  # Only include cooldown if it's present
  attribute :cooldown, if: -> { cooldown.present? }

  def updating_a_pull_request
    object.updating_a_pull_request?
  end

  def multi_ecosystem_update
    object.multi_ecosystem_update?
  end

  def source
    update_config = object.update_config

    source = {
      provider: "github",
      repo: update_config.repo.full_name,
      branch: update_config.target_branch,
      directory: update_config.directory,
      api_endpoint: Dependabot::Application.target_github_api_endpoint(update_config.repo.account),
      hostname: Dependabot::Application.target_github_hostname(update_config.repo.account),
    }

    if object.directories
      source[:directories] = object.directories
      source.delete(:directory)
    elsif update_config.directories
      source[:directories] = update_config.directories
    end

    source
  end

  def security_advisories
    object.relevant_security_advisories_hash
  end

  def credentials_metadata
    creds = object.update_config.registries.
            map(&:serialized_credential_metadata)

    hostname = Dependabot::Application.target_github_hostname(object.update_config.repo.account)
    creds << { "type" => "git_source", "host" => hostname }

    github = "github.com"
    unless creds.any? { |c| c["type"] == "git_source" && c["host"] == github }
      creds << { "type" => "git_source", "host" => "github.com" }
    end

    creds
  end

  def dependency_groups
    return [] unless object.grouping_requested?

    if object.security_updates_only? && user_defined_dependency_groups.none? && no_user_groups_defined?
      [object.fallback_dependency_group.serialize]
    else
      user_defined_dependency_groups
    end
  end

  # This method returns the dependency group associated with any existing PR
  # that is being updated as part of this job.
  def dependency_group_to_refresh
    return nil unless object.updating_a_pull_request?

    if object.current_dependency_group.present?
      object.current_dependency_group.name
    elsif object.security_updates_only? && object.grouping_requested? && no_user_groups_defined?
      object.increment_metric("fallback_dependency_group_used")
      # grouped security updates do not require users to define groups
      object.fallback_dependency_group.name
    else
      nil
    end
  end

  # We pass previous PRs that are open or closed to the updater so it knows to
  # skip some updates. The same does not apply to merged PRs as we may want to
  # recreate them (if the dependency version has regressed).
  def existing_pull_requests
    return [] if object.command == :graph

    # Some PRs were incorrectly transitioned to closed after being merged. We
    # should treat them as if they were merged.
    merged_but_now_closed_prs =
      object.update_config.pull_requests.
      where(grouped_update: false).
      in_state(:closed).
      previously_merged

    # Narrow this to the PRs that were incorrectly closed after being merged
    closed_but_should_be_merged_pr_ids = Set.new(
      merged_but_now_closed_prs.
       filter(&:incorrectly_in_closed_state?).pluck(:id)
    )

    prs = object.update_config.pull_requests.
          where(grouped_update: false).
          not_in_state(:pending, :merged).
          includes(:updated_dependencies).
          filter { |pr| closed_but_should_be_merged_pr_ids.exclude?(pr.id) }
    if object.update_config.repo.monolith_feature_enabled?(:change_pr_data_format)
      prs.map(&method(:serialize_pull_request_with_number))
    else
      prs.map(&method(:serialize_pull_request_dependencies))
    end
  end

  # We pass previous PRs for DependencyGroups that are separately as:
  # - we should only include 'open' PRs for this set
  # - they require a different data structure in order to encode PR-level info
  #   about the group.
  # - these two sets are mutually exclusive within the updater, a job will only
  #   consider this set when creating new group PRs.
  def existing_group_pull_requests
    return [] if object.command == :graph

    object.update_config.pull_requests.
      where(grouped_update: true).
      not_in_state(:pending, :merged, :closed).
      includes(:updated_dependencies, :dependency_group, :update_job).map do |pr|
      # The group security update was generated by the button which doesn't create a real group
      if pr.dependency_group.nil? && pr.update_job.security_updates_only?
        next {
          dependency_group_name: object.fallback_dependency_group.name,
          dependencies: serialize_pull_request_dependencies(pr),
          pr_number: pr.github_number,
        }
      end
      # In the event the dependency group has been logically deleted but the
      # PR has not yet been closed, we omit it to avoid it blocking a new rule
      # with the same name.
      next unless pr.dependency_group&.active?

      {
        dependency_group_name: pr.dependency_group.name,
        dependencies: serialize_pull_request_dependencies(pr),
        pr_number: pr.github_number,
      }
    end.compact
  end

  # We pass non group update closed PRs as ignore conditions.
  def closed_prs_as_ignore_conditions
    object.update_config.pull_requests.
      where(grouped_update: false).
      where(multiple_dependencies: false).
      in_state(:closed).
      includes(:updated_dependencies).
      map do |pr|
        pr.updated_dependencies.map do |dep|
          {
            dependency_name: dep.name,
            version_requirement: create_version_requirement(dep, pr),
            update_types: nil,
            source: "pr-closed",
          }
        end
      end.flatten
  end

  def create_version_requirement(dependency, pull_request)
    ignored_dependency = Dependabot::Dependency.new(
      name: dependency.name,
      # The versions displayed in a pull request may include prefixes or suffixes, so we cast the version from the
      # pull request to a Dependabot::Version for any version preprocessing
      version: to_version(dependency.version, pull_request).to_s,
      previous_version: to_version(dependency.previous_version, pull_request).to_s,
      requirements: [],
      package_manager: dependency.package_manager
    )

    ignore_requirement = FindOrCreateIgnoreCondition::IgnoreConditionBuilder.new(
      dep: ignored_dependency, version: to_version(dependency.version, pull_request)
    ).run
    to_requirement(ignore_requirement, pull_request).to_s
  end

  def ignore_conditions
    if object.update_config.repo.config_feature_enabled?(:add_closed_pr_in_ignore_hash)
      object.ignore_conditions_hash.dup.concat(closed_prs_as_ignore_conditions)
    else
      object.ignore_conditions_hash
    end
  end

  def cooldown
    object.update_config&.cooldown
  end

  def update_subdependencies
    object.update_subdependencies?
  end

  delegate :command, to: :object

  def security_updates_only
    object.security_updates_only?
  end

  def vendor_dependencies
    object.update_config.vendor
  end

  def enable_beta_ecosystems
    object.beta_ecosystems_enabled?
  end

  def reject_external_code
    object.update_config.reject_external_code?
  end

  def commit_message_options
    {
      prefix: object.commit_message_prefix,
      prefix_development: object.commit_message_prefix_development,
      include_scope: object.commit_message_include_scope,
    }
  end

  def exclude_paths
    object.update_config&.exclude_paths
  end

  # We return false if enabled, nil otherwise so the key can be omitted by
  # dependabot/cli to avoid churn in test fixtures.
  def debug
    return true if object.update_config.debug_logging_enabled?

    nil
  end

  def repo_private
    object.repo.private?
  end

  def proxy_log_response_body_on_auth_failure
    object.proxy_log_response_body_on_auth_failure?
  end

  private

  def no_user_groups_defined?
    object.update_config.dependency_groups.active.none?
  end

  def user_defined_dependency_groups
    @user_defined_dependency_groups ||=
      object.
      dependency_groups.
      map(&:serialize)
  end

  def serialize_pull_request_dependencies(pull_request)
    pull_request.updated_dependencies.map do |dep|
      {
        dependency_name: dep.name,
        dependency_version: dep.version,
        directory: dep.directory,
        dependency_removed: dep.removed? || nil,
      }.compact
    end
  end

  def serialize_pull_request_with_number(pull_request)
    {
      pr_number: pull_request.github_number,
      dependencies: serialize_pull_request_dependencies(pull_request),
    }
  end

  def version_class(package_manager)
    Dependabot::Utils.version_class_for_package_manager(package_manager)
  end

  def requirement_class(package_manager)
    Dependabot::Utils.requirement_class_for_package_manager(package_manager)
  end

  def package_manager(pull_request)
    @package_manager ||= pull_request.update_config.package_manager
  end

  def to_version(version, pull_request)
    package_manager = package_manager(pull_request)
    version_class(package_manager).new(version)
  end

  def to_requirement(requirement, pull_request)
    package_manager = package_manager(pull_request)
    requirement_class(package_manager).new(requirement)
  end
end
