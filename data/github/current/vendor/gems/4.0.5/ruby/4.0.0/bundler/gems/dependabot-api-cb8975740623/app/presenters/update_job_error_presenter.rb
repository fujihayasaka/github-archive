# frozen_string_literal: true

# rubocop:disable Metrics/MethodLength
# rubocop:disable Metrics/ClassLength
# rubocop:disable Metrics/CyclomaticComplexity
class UpdateJobErrorPresenter
  MANUAL_TRIGGER_HELP_URL = "https://docs.github.com/en/github/managing-security-vulnerabilities/troubleshooting-dependabot-errors#triggering-a-dependabot-pull-request-manually"

  def initialize(error_hash:, update_job:)
    @error_hash = error_hash
    @update_job = update_job
  end

  def issue_type
    error_hash.fetch("error-type")
  end

  # rubocop:disable Metrics/AbcSize
  def issue_detail # rubocop:disable Metrics/PerceivedComplexity
    error_message =
      error_detail&.
      fetch("message", nil)&.
      delete("\0")&.
      gsub(/npm\.fontawesome\.com.*/, "npm\.fontawesome\.com")

    case issue_type
    when "branch_not_found"
      error_detail&.fetch("branch-name")
    when "directory_not_found"
      error_detail.fetch("directory-name")
    when "config_not_valid"
      error_detail&.fetch("message")
    when "dependency_file_not_found"
      error_detail&.fetch("file-path")
    when "dependency_file_not_parseable"
      error_detail&.fetch("file-path")
    when "dependency_file_not_evaluatable" then error_message
    when "dependency_file_not_resolvable" then error_message
    when "dependency_file_content_not_changed" then error_message
    when "path_dependencies_not_reachable"
      error_detail&.fetch("dependencies")
    when "missing_environment_variable"
      error_detail&.fetch("environment-variable")
    when "private_source_not_reachable"
      error_detail&.fetch("source")
    when "private_source_authentication_failure"
      error_detail&.fetch("source")
    when "private_source_bad_response"
      error_detail&.fetch("source")
    when "private_source_timed_out"
      error_detail&.fetch("source")
    when "private_source_certificate_failure"
      error_detail&.fetch("source")
    when "pull_request_creation_failure"
      error_message
    when "git_dependencies_not_reachable"
      get_git_url_from(error_detail&.fetch("dependency-urls"))
    when "git_dependency_reference_not_found"
      error_detail&.fetch("dependency")
    when "misconfigured_tooling"
      error_detail&.fetch("message")
    when "go_module_path_mismatch"
      error_detail&.fetch("declared-path")
    when "dependency_not_found"
      error_detail&.fetch("source")
    when "git_token_auth_error"
      error_detail&.fetch("message")
    when "unresolvable_version"
      error_detail&.fetch("dependencies", nil)
    when "tool_feature_not_supported"
      {
        tool_name: error_detail.fetch("tool-name"),
        tool_type: error_detail.fetch("tool-type"),
        feature: error_detail.fetch("feature"),
      }
    end
  end
  # rubocop:enable Metrics/AbcSize

  # rubocop:disable Metrics/PerceivedComplexity
  def issue_title # rubocop:disable Metrics/AbcSize
    case issue_type
    when "branch_not_found"
      branch_not_found_title
    when "directory_not_found"
      directory_not_found_title
    when "config_not_valid"
      config_not_valid_title
    when "tool_version_not_supported"
      ununsupported_tool_version_title
    when "dependency_file_not_found"
      missing_dependency_file_title
    when "dependency_file_not_supported"
      unsupported_dependency_file_title
    when "dependency_file_not_evaluatable"
      unevaluatable_dependency_file_title
    when "dependency_file_not_parseable"
      unparseable_dependency_file_title
    when "dependency_file_not_resolvable"
      unresolvable_dependency_file_title
    when "dependency_file_content_not_changed"
      file_content_not_changed_title
    when "path_dependencies_not_reachable"
      path_based_dependencies_title
    when "missing_environment_variable"
      environment_variable_not_supported_title
    when "not_implemented"
      not_implemented_title
    when "private_source_not_reachable"
      private_source_not_reachable_title
    when "private_source_authentication_failure"
      private_source_authentication_failure_title
    when "private_source_bad_response"
      private_source_bad_response_title
    when "private_source_timed_out"
      private_source_timed_out_title
    when "private_source_certificate_failure"
      private_source_certificate_failure_title
    when "git_dependencies_not_reachable"
      git_dependencies_not_supported_title
    when "git_dependency_reference_not_found"
      git_dependency_reference_not_found_title
    when "misconfigured_tooling"
      misconfigured_tooling_title
    when "go_module_path_mismatch"
      go_module_path_mismatch_title
    when "update_not_possible"
      update_not_possible_title
    when "security_update_dependency_not_found"
      security_update_dependency_not_found_title
    when "security_update_not_found"
      security_update_not_found_title
    when "security_update_not_possible"
      security_update_not_possible_title
    when "transitive_update_not_possible"
      transitive_update_not_possible_title
    when "security_update_not_needed"
      security_update_not_needed_title
    when "open_pull_request_limit_exceeded"
      open_pull_request_limit_exceeded_title
    when "timed_out"
      timed_out_title
    when "bad_gitmodules"
      bad_gitmodules_title
    when "all_versions_ignored"
      all_versions_ignored_title
    when "cancelled_update"
      cancelled_update_title
    when "pull_request_creation_failure"
      pull_request_creation_failure_title
    when "pull_request_exists_for_latest_version"
      pull_request_exists_for_latest_version_title
    when "pull_request_exists_for_security_update"
      pull_request_exists_for_security_update_title
    when "edited_pull_request_exists"
      edited_pull_request_exists_title
    when "out_of_disk"
      out_of_disk_title
    when "network_unsafe_http"
      network_unsafe_http_title
    when "unexpected_external_code"
      unexpected_external_code_title
    when "secret_not_found", "secret_not_valid"
      secret_not_found_title
    when "job_repo_not_found"
      job_repo_not_found_title
    when "actions_service_unavailable"
      actions_service_unavailable_title
    when "actions_workflow_image"
      actions_workflow_image_title
    when "self_hosted_runner_unavailable"
      self_hosted_runner_unavailable_title
    when "resource_unavailable_to_installation"
      resource_unavailable_to_installation_title
    when "dependency_not_found"
      dependency_not_found_title
    when "git_token_auth_error"
      git_token_auth_error_title
    when "unresolvable_version"
      unresolvable_version_title
    when "tool_feature_not_supported"
      tool_feature_not_supported_title
    when "internal_pull_request_creation_failure"
      internal_pull_request_creation_failure_title
    else
      unknown_error_title
    end
  end
  # rubocop:enable Metrics/PerceivedComplexity

  # rubocop:disable Metrics/PerceivedComplexity
  def issue_body # rubocop:disable Metrics/AbcSize
    case issue_type
    when "branch_not_found"
      branch_not_found_body
    when "directory_not_found"
      directory_not_found_body
    when "config_not_valid"
      config_not_valid_body
    when "tool_version_not_supported"
      unsupported_tool_version_body
    when "dependency_file_not_found"
      missing_dependency_file_body
    when "dependency_file_not_supported"
      unsupported_dependency_file_body
    when "dependency_file_not_evaluatable"
      unevaluatable_dependency_file_body
    when "dependency_file_not_parseable"
      unparseable_dependency_file_body
    when "dependency_file_not_resolvable"
      unresolvable_dependency_file_body
    when "dependency_file_content_not_changed"
      file_content_not_changed_body
    when "path_dependencies_not_reachable"
      path_based_dependencies_body
    when "missing_environment_variable"
      environment_variable_not_supported_body
    when "not_implemented"
      not_implemented_body
    when "private_source_not_reachable",
         "private_source_authentication_failure",
         "private_source_bad_response",
         "private_source_timed_out",
         "private_source_certificate_failure"
      private_source_error_common_body
    when "git_dependencies_not_reachable"
      git_dependencies_not_supported_body
    when "git_dependency_reference_not_found"
      git_dependency_reference_not_found_body
    when "misconfigured_tooling"
      misconfigured_tooling_body
    when "go_module_path_mismatch"
      go_module_path_mismatch_body
    when "update_not_possible"
      update_not_possible_body
    when "security_update_dependency_not_found"
      security_update_dependency_not_found_body
    when "security_update_not_found"
      security_update_not_found_body
    when "security_update_not_possible"
      security_update_not_possible_body
    when "transitive_update_not_possible"
      transitive_update_not_possible_body
    when "security_update_not_needed"
      security_update_not_needed_body
    when "open_pull_request_limit_exceeded"
      open_pull_request_limit_exceeded_body
    when "timed_out"
      timed_out_body
    when "bad_gitmodules"
      bad_gitmodules_body
    when "all_versions_ignored"
      all_versions_ignored_body
    when "cancelled_update"
      cancelled_update_body
    when "pull_request_creation_failure"
      pull_request_creation_failure_body
    when "pull_request_exists_for_latest_version"
      pull_request_exists_for_latest_version_body
    when "pull_request_exists_for_security_update"
      pull_request_exists_for_security_update_body
    when "internal_pull_request_creation_failure"
      internal_pull_request_creation_failure_body
    when "edited_pull_request_exists"
      edited_pull_request_exists_body
    when "network_unsafe_http"
      network_unsafe_http_body
    when "out_of_disk"
      out_of_disk_body
    when "unexpected_external_code"
      unexpected_external_code_body
    when "secret_not_found", "secret_not_valid"
      secret_not_found_body
    when "job_repo_not_found"
      job_repo_not_found_body
    when "actions_service_unavailable"
      actions_service_unavailable_body
    when "actions_workflow_image"
      actions_workflow_image_body
    when "self_hosted_runner_unavailable"
      self_hosted_runner_unavailable_body
    when "resource_unavailable_to_installation"
      resource_unavailable_to_installation_body
    when "dependency_not_found"
      dependency_not_found_body
    when "git_token_auth_error"
      git_token_auth_error_body
    when "unresolvable_version"
      unresolvable_version_body
    when "tool_feature_not_supported"
      tool_feature_not_supported_body
    else
      unknown_error_body
    end
  end
  # rubocop:enable Metrics/PerceivedComplexity

  private

  attr_reader :error_hash, :update_job

  def branch_not_found_title
    "Dependabot couldn't find the branch #{issue_detail}"
  end

  def branch_not_found_body
    "Dependabot was set up to create pull requests against the branch "\
    "`#{issue_detail}`, but couldn't find it."
  end

  def directory_not_found_title
    "Dependabot couldn't find the directory #{issue_detail}"
  end

  def directory_not_found_body
    "Dependabot was set up to run in directory "\
    "`#{issue_detail}`, but couldn't find it."
  end

  def config_not_valid_title
    "Dependabot found a problem with its configuration"
  end

  def config_not_valid_body
    error_text = issue_detail

    explanation = "Dependabot failed to update your dependencies because there "\
      "was an error evaluating its configuration."

    return explanation unless error_text

    explanation +
      "\n\nDependabot encountered the following error:\n\n" \
      "```\n" \
      "#{error_text}\n" \
      "```"
  end

  def ununsupported_tool_version_title
    tool_name = error_detail.fetch("tool-name")

    "Dependabot does not support your #{tool_name} version"
  end

  def unsupported_tool_version_body
    tool_name = error_detail.fetch("tool-name", "").to_s.strip
    detected_version = error_detail.fetch("detected-version", "").to_s.strip
    supported_versions = error_detail.fetch("supported-versions", "").to_s.strip.gsub(".*", '.\*')

    message = "Dependabot detected the following #{tool_name} requirement for your project: '#{detected_version}'."

    # Check if supported_versions is not nil or empty
    unless supported_versions.empty?
      message += "\n\nCurrently, the following #{tool_name} versions are supported in " \
                 "Dependabot: #{supported_versions}."
    end

    message
  end

  def missing_dependency_file_title
    if update_job.package_manager == PackageManagers::SUBMODULES
      "Dependabot couldn't find the submodule #{issue_detail}"
    elsif issue_detail.present?
      file_name = issue_detail.split("/").last
      "Dependabot couldn't find a #{file_name}"
    else
      "Dependabot couldn't find any dependency files in the directory"
    end
  end

  def missing_dependency_file_body
    return "Dependabot couldn't find any dependency files in the configured directory" if issue_detail.nil?

    if update_job.package_manager == PackageManagers::SUBMODULES &&
       !issue_detail.end_with?(".gitmodules")
      msg = "Dependabot failed to update your dependencies because there was an "\
        "error finding the submodule `#{issue_detail}`. Perhaps it isn't committed, or isn't a submodule?"
      return msg
    end

    file_path = issue_detail
    file_name = issue_detail.split("/").last

    msg =
      "Dependabot requires a #{file_name} to evaluate your " \
      "#{language} dependencies. It had expected to find " \
      "one at the path: `#{file_path}`."
    if update_job.update_config.using_config_file?
      msg += "\n\nIf this isn't a #{language} project, you may wish to "\
             "disable updates for it in the "\
             "`#{update_job.update_config.repo.config_file_path}` config file "\
             "in this repo."
    end
    msg
  end

  def unevaluatable_dependency_file_title
    "Dependabot can't evaluate your #{language} dependency files"
  end

  def unevaluatable_dependency_file_body
    error_text = issue_detail

    explanation = "Dependabot failed to update your dependencies because there "\
      "was an error evaluating your #{language} dependency files."

    return explanation unless error_text

    explanation +
      "\n\nDependabot encountered the following error:\n\n" \
      "```\n" \
      "#{error_text}\n" \
      "```"
  end

  def file_content_not_changed_title
    "Dependency file content did not change"
  end

  def file_content_not_changed_body
    "Dependabot failed to update your dependencies because there "\
      "is no difference between the current and previous requirements."
  end

  def unparseable_dependency_file_title
    file_name = issue_detail.split("/").last

    "Dependabot can't parse your #{file_name}"
  end

  def unparseable_dependency_file_body
    file_path = issue_detail
    file_name = issue_detail.split("/").last

    error_text = error_detail&.fetch("message", nil)

    explanation = "Dependabot failed to update your dependencies because there "\
      "was an error parsing the #{file_name} found at `#{file_path}`."

    return explanation unless error_text

    explanation +
      "\n\nDependabot encountered the following error:\n\n" \
      "```\n" \
      "#{error_text}\n" \
      "```"
  end

  def unresolvable_dependency_file_title
    "Dependabot can't resolve your #{language} dependency files"
  end

  def unresolvable_dependency_file_body
    error_text = issue_detail

    explanation =
      "Dependabot failed to update your dependencies because there was an error "\
      "resolving your #{language} dependency files."

    return explanation unless error_text

    explanation +
      "\n\nDependabot encountered the following error:\n\n" \
      "```\n" \
      "#{error_text}\n" \
      "```\n\n"
  end

  def unsupported_dependency_file_title
    requirement =
      if update_job.update_config.supports_lockfile?
        "lockfile"
      else
        "pinned version"
      end

    "Dependabot can't update vulnerable dependencies without a #{requirement}"
  end

  def unsupported_dependency_file_body
    fix_text =
      if update_job.update_config.supports_lockfile?
        "add a supported lockfile "\
        "(#{update_job.update_config.formatted_lockfile_name})"
      else
        "pin the version to a specific release in your manifest file"
      end

    "The currently installed version can't be determined.\n\n"\
    "To resolve the issue #{fix_text}."
  end

  def git_dependency_reference_not_found_title
    "Dependabot couldn't fetch the branch/reference for #{issue_detail}"
  end

  def git_dependency_reference_not_found_body
    msg = "Your dependency file specified a branch or reference for "\
          "`#{issue_detail}`, but Dependabot couldn't find it at the "\
          "project's source. Has it been removed?"

    if update_job.package_manager == PackageManagers::BUNDLER
      msg += "\n\n"\
             "For Ruby dependencies, this can be caused by a branch specified "\
             "in your Gemfile being deleted at the source, or having been "\
             "rebased, so the commit reference in your Gemfile.lock is no "\
             "longer included in the branch. In that case, it can be fixed "\
             "by running `bundler update #{issue_detail}` locally."
    end

    msg
  end

  def path_based_dependencies_title
    "Dependabot couldn't fetch all your path-based dependencies"
  end

  def path_based_dependencies_body
    dependency_names_string =
      issue_detail.
      map { |n| "`#{n}`" }.
      to_sentence(last_word_connector: " and ", two_words_connector: " and ")

    "The affected dependencies were #{dependency_names_string}." \
    "\n\n" \
    "To use path-based dependencies with Dependabot the paths must be " \
    "relative, resolve to a directory in this project's source code, " \
    "and contain a valid #{language} project."
  end

  def environment_variable_not_supported_title
    "Dependabot can't update dependencies that "\
    "require environment variables."
  end

  def environment_variable_not_supported_body
    "The following environment variable was required and "\
    "caused the update to fail: #{issue_detail}."
  end

  def private_source_not_reachable_title
    "Dependabot can't reach a dependency in a private package registry"
  end

  def private_source_authentication_failure_title
    "Dependabot can't authenticate to a private package registry"
  end

  def private_source_bad_response_title
    "Dependabot received an unexpected response from a private package registry"
  end

  def private_source_timed_out_title
    "Dependabot timed out while waiting for a private package registry"
  end

  def private_source_certificate_failure_title
    "Dependabot couldn't validate the certificate for a private package registry"
  end

  def private_source_error_common_body
    "The following private package registry was used and caused the update to fail: #{issue_detail}."
  end

  def git_dependencies_not_supported_presenter
    @git_dependencies_not_supported_presenter ||=
      GitDependenciesNotSupportedPresenter.new(issue_detail: issue_detail, update_job: update_job)
  end

  def git_dependencies_not_supported_title
    git_dependencies_not_supported_presenter.title
  end

  def git_dependencies_not_supported_body
    git_dependencies_not_supported_presenter.body
  end

  def bad_gitmodules_title
    "Dependabot couldn't create a PR because your .gitmodules file is invalid"
  end

  def bad_gitmodules_body
    "Please review your `.gitmodules` file. This error is normally due to an "\
    "invalid component in a git path."
  end

  def misconfigured_tooling_title
    tool_name = error_detail.fetch("tool-name")

    "Dependabot could not run #{tool_name} to update your dependencies due to a configuration error"
  end

  def misconfigured_tooling_body
    tool_name = error_detail.fetch("tool-name")

    "Please review your #{tool_name} setup. Dependabot encountered the following error when running it:\n\n" \
      "```\n" \
      "#{issue_detail}\n" \
      "```"
  end

  def go_module_path_mismatch_title
    "Dependabot wasn't able to update #{issue_detail}"
  end

  def go_module_path_mismatch_body
    declared_path = error_detail&.fetch("declared-path")
    discovered_path = error_detail&.fetch("discovered-path")
    go_mod = error_detail&.fetch("go-mod")

    "The module path `#{declared_path}` found in your `#{go_mod}` doesn't "\
    "match the actual path `#{discovered_path}` found in the dependency's "\
    "`go.mod`.\n\n"\
    "Updating the module path in your `go.mod` to `#{discovered_path}` should "\
    "resolve this issue."
  end

  def update_not_possible_title
    "Dependabot cannot update to the required version"
  end

  def update_not_possible_body
    "One or more other dependencies require a version that is incompatible with this update."
  end

  def security_update_dependency_not_found_title
    "Dependabot can't find the vulnerable dependency in the repository."
  end

  def security_update_dependency_not_found_body
    "This is an indirect dependency not explicitly present in any manifest file, so Dependabot cannot update it."
  end

  def security_update_not_found_title
    dependency_name = error_detail&.fetch("dependency-name")

    "Dependabot can't find a published or compatible non-vulnerable version "\
    "for #{dependency_name}"
  end

  def security_update_not_found_body
    dependency_version = error_detail&.fetch("dependency-version")

    "The latest published and compatible version is `#{dependency_version}`."
  end

  def transitive_update_not_possible_title
    dependency_name = error_detail&.fetch("dependency-name")

    "Dependabot cannot update #{dependency_name} " \
    "because it is required by another dependency through a transitive dependency."
  end

  def transitive_update_not_possible_body
    dependency_name = error_detail&.fetch("dependency-name")
    latest_allowed_version = error_detail&.fetch("latest-resolvable-version")
    lowest_non_vulnerable_version = error_detail&.fetch("lowest-non-vulnerable-version")
    conflicting_dependencies = error_detail["conflicting-dependencies"]

    conflicting_dependencies_msg = conflicting_dependencies.pluck("explanation").join("\n")
    <<~MSG.chomp
      The latest possible version of #{dependency_name} that can be installed is `#{latest_allowed_version}` because of the following conflicting dependencies:

      ```
      #{conflicting_dependencies_msg}
      ```

      The earliest fixed version is `#{lowest_non_vulnerable_version}`.\n
    MSG
  end

  def security_update_not_possible_title
    dependency_name = error_detail&.fetch("dependency-name")

    "Dependabot cannot update #{dependency_name} to a non-vulnerable version"
  end

  def security_update_not_possible_body
    dependency_name = error_detail&.fetch("dependency-name")
    latest_allowed_version = error_detail&.fetch("latest-resolvable-version")
    lowest_non_vulnerable_version = error_detail&.fetch("lowest-non-vulnerable-version")
    conflicting_dependencies = error_detail["conflicting-dependencies"]

    unless lowest_non_vulnerable_version
      return "Could not find a compatible non-vulnerable version. Has it been released yet?"
    end

    # We are encountering a mystery value every so often in production, it isn't clear where in core it is being
    # leaked from.
    #
    # See: https://github.com/github/dependabot-updates/issues/2340
    begin
      if conflicting_dependencies&.any?
        conflicting_dependencies_msg = conflicting_dependencies.pluck("explanation").join("\n")
        return <<~MSG
          The latest possible version that can be installed is `#{latest_allowed_version}` because of the following conflicting #{'dependency'.pluralize(conflicting_dependencies.count)}:

          ```
          #{conflicting_dependencies_msg}
          ```

          The earliest fixed version is `#{lowest_non_vulnerable_version}`.
        MSG
      end
    rescue NoMethodError => e
      Dependabot::Logger.info(
        msg: "unexpected value for 'conflicting-dependencies'",
        "code.namespace": self.class.name,
        value: conflicting_dependencies.to_s,
        **update_job.telemetry_attributes,
      )

      Dependabot::Exceptions.report!(e)
    end

    <<~MSG.chomp
      The latest possible version of #{dependency_name} that can be installed is `#{latest_allowed_version}`.

      The earliest fixed version is `#{lowest_non_vulnerable_version}`.
    MSG
  end

  def security_update_not_needed_title
    dependency_name = error_detail&.fetch("dependency-name")

    "No security update is needed as #{dependency_name} is no longer vulnerable"
  end

  def security_update_not_needed_body
    dependency_name = error_detail&.fetch("dependency-name")

    "Dependabot hasn't attempted to update #{dependency_name} as it's no "\
    "longer vulnerable."
  end

  def tool_feature_not_supported_title
    tool_name = issue_detail[:tool_name]
    tool_type = issue_detail[:tool_type]
    feature = issue_detail[:feature]

    "Dependabot doesn't support the '#{feature}' feature for #{tool_name} #{tool_type}"
  end

  def tool_feature_not_supported_body
    tool_name = issue_detail[:tool_name]
    tool_type = issue_detail[:tool_type]
    feature = issue_detail[:feature]

    "Dependabot attempted to update your dependencies but encountered an unsupported feature: '#{feature}' " \
    "for #{tool_name} #{tool_type}. Currently, this feature is not supported by Dependabot.\n\n"
  end

  def open_pull_request_limit_exceeded_title
    "Dependabot cannot open any more pull requests"
  end

  def open_pull_request_limit_exceeded_body
    "The open pull request "\
    "limit has been exceeded. The current limit is: "\
    "#{update_job.update_config.open_pull_requests_limit}.\n\n"\
    "Dependabot will open new pull requests once you merge or close the "\
    "already open pull requests. "\
    "You can also update this limit in the config file."
  end

  def unknown_error_title
    "Dependabot encountered an unknown error"
  end

  def unknown_error_body
    "Dependabot failed to update your dependencies because an unexpected error occurred. See the logs for more details."
  end

  def actions_service_unavailable_title
    "Actions runners unavailable"
  end

  def actions_service_unavailable_body
    "Dependabot was unable to update your dependencies as no Actions runners were available."
  end

  def actions_workflow_image_title
    "Actions encountered a problem preparing Dependabot"
  end

  def actions_workflow_image_body
    <<~MESSAGE.squish
      Dependabot was unable to update your dependencies as Actions encountered a problem retrieving
      Docker images. #{self_hosted_runner_workflow_image_body if update_job.self_hosted?}
    MESSAGE
  end

  def self_hosted_runner_unavailable_title
    "Self-hosted runner unavailable"
  end

  def self_hosted_runner_unavailable_body
    error_detail&.fetch("message", nil) || "No self-hosted runner was available to execute this job."
  end

  def self_hosted_runner_workflow_image_body
    "Please make sure Docker is running on the Actions host and can connect to #{hostname}."
  end

  def timed_out_title
    "Dependabot timed out during its update"
  end

  def timed_out_body
    "Dependabot failed to update your dependencies because it took too long to complete."
  end

  def out_of_disk_title
    "Dependabot ran out of disk space during its update"
  end

  def out_of_disk_body
    "Dependabot failed to update your dependencies because there was not enough disk space available."
  end

  def network_unsafe_http_title
    "Dependabot encountered an unsafe HTTP network request"
  end

  def network_unsafe_http_body
    "Dependabot failed to update your dependencies because there was an unsafe HTTP network request. "\
     "Please make sure any private registries are accessed over HTTPS."
  end

  def unexpected_external_code_title
    "Dependabot refused to execute external code"
  end

  def unexpected_external_code_body
    "Dependabot blocked external code required for this update. "\
    "Please set `insecure-external-code-execution: allow` in the config "\
    "if you trust all dependencies' supply chain."
  end

  def job_repo_not_found_title
    "Dependabot couldn't access the repository"
  end

  def job_repo_not_found_body
    registry = update_job.update_config.find_registry_by(type: :git_source,
                                                         host: hostname)
    if registry.blank?
      return "Dependabot encountered a temporary problem accessing the repository. " \
        "Please [check for updates again](#{MANUAL_TRIGGER_HELP_URL})."
    end

    secret = registry.serialized_credentials["password"]
    "In the config file, the #{registry.name} registry uses the #{secret} " \
    "access token, but that token doesn't have access to this repository. "\
    "Please provide an access token that has access to this repository."
  end

  def secret_not_found_title
    "Dependabot could not read a required secret"
  end

  def secret_not_found_body
    secret_name = error_detail&.fetch("secret-name")

    "The secret `#{secret_name}` referenced in the config file could not be read. "\
    "Please ensure the secret has been created and that this repo has access to it."
  end

  def all_versions_ignored_title
    "Dependabot cannot update to the required version as all versions "\
    "were ignored"
  end

  def all_versions_ignored_body
    "Dependabot was configured to ignore all versions that could satisfy "\
    "this requirement."
  end

  def cancelled_update_title
    "Dependabot cancelled the update"
  end

  def cancelled_update_body
    "The repository is no longer supported."
  end

  def pull_request_creation_failure_title
    "Dependabot failed to create a pull request"
  end

  def pull_request_creation_failure_body
    explanation = "Dependabot ran into an issue when attempting to create the pull request"

    return explanation unless issue_detail

    explanation +
      "\n\nDependabot encountered the following error:\n\n" \
      "```\n" \
      "#{issue_detail}\n" \
      "```"
  end

  def internal_pull_request_creation_failure_title
    "Dependabot cannot track a pull request from this job"
  end

  def internal_pull_request_creation_failure_body
    github_number = error_detail.fetch("github_number") { nil }

    <<~MESSAGE.squish
      During job execution, Dependabot created a pull request #{github_number ? "(#{github_number})" : ''},
      which it will not be able to track.
    MESSAGE
  end

  def pull_request_exists_for_latest_version_title
    "Dependabot cannot update to the required version as there is already an "\
    "existing pull request for the latest version"
  end

  def pull_request_exists_for_latest_version_body
    latest_version = error_hash&.dig("error-detail", "dependency-version")
    "There is already an existing pull request for the latest version: "\
    "#{latest_version}"
  end

  def pull_request_exists_for_security_update_title
    "Dependabot cancelled the update as there is already an "\
    "existing pull request for the fixed version"
  end

  def pull_request_exists_for_security_update_body
    updated_dependencies = error_detail&.fetch("updated-dependencies") || []
    updated_dependency_names = updated_dependencies.map do |d|
      if d.fetch("dependency-removed", false)
        "#{d.fetch('dependency-name')}@removed"
      else
        "#{d.fetch('dependency-name')}@#{d.fetch('dependency-version')}"
      end
    end

    "There is already an existing pull request for the fixed version: `#{updated_dependency_names.join(', ')}`"
  end

  # TODO: migrate `updated_dependencies` keys in production
  def edited_pull_request_exists_title
    updated_dependencies = error_detail&.fetch("updated_dependencies", nil) ||
                           error_detail&.fetch("updated-dependencies", nil)
    updated_dependency_names = updated_dependencies.map do |d|
      d.fetch("dependency-name", nil) || d.fetch("name", nil)
    end

    "Dependabot cancelled the update as there is an existing edited "\
    "pull request for #{updated_dependency_names.join(', ')}"
  end

  # TODO: migrate `updated_dependencies` and `edited_pull_request_id` keys in production
  # rubocop:disable Metrics/PerceivedComplexity
  def edited_pull_request_exists_body
    updated_dependencies = error_detail&.fetch("updated_dependencies", nil) ||
                           error_detail&.fetch("updated-dependencies", nil)
    updated_dependency_names = updated_dependencies.map do |d|
      d.fetch("dependency-name", nil) || d.fetch("name", nil)
    end
    pull_request_id = error_detail&.fetch("edited_pull_request_id", nil) ||
                      error_detail&.fetch("edited-pull-request-id", nil)
    pull_request = PullRequest.includes(:repo).find(pull_request_id)

    "There is an existing open pull request for `#{updated_dependency_names.join(', ')}` that has "\
    "been edited by someone other than Dependabot: #{pull_request.github_url}\n\n"\
    "You can retry this update once the edited pull request is closed or merged."
  end
  # rubocop:enable Metrics/PerceivedComplexity

  def not_implemented_title
    "Dependabot cannot complete this update"
  end

  def not_implemented_body
    "The job attempted to use an unimplemented method, please contact support."
  end

  def resource_unavailable_to_installation_title
    "Resource unavailable to the Dependabot installation"
  end

  def resource_unavailable_to_installation_body
    "The Dependabot installation does not have access to the required resources."
  end

  def dependency_not_found_title
    "Dependabot could not find a dependency."
  end

  def dependency_not_found_body
    source = error_detail&.fetch("source")
    "The following dependency could not be found : #{source}"
  end

  def git_token_auth_error_title
    "Dependabot can't reach a dependency in a GitHub package registry."
  end

  def git_token_auth_error_body
    "Dependabot encountered a Git authorization failure : #{issue_detail}"
  end

  def unresolvable_version_title
    "Dependabot could not find a dependency version."
  end

  def unresolvable_version_body
    msg = "Dependabot could not resolve semantic versions for dependencies"

    # coalesce any issue detail value(s) to an array
    dependencies = Array(issue_detail)
    msg = "#{msg} : #{dependencies.join(', ')}" if dependencies.present?

    msg
  end

  def language
    @language ||= update_job.formatted_language
  end

  def get_git_url_from(dependency_urls)
    # TODO: Currently we're ignoring all the git dependency errors
    # except the first one. Obviously that's not sensible - we should
    # create separate errors for each one.
    first_url = dependency_urls.first
    first_url = first_url.gsub(/.git$/, "")
    return first_url unless first_url.include?(hostname)

    first_url.split(%r{/|:}).last(2).join("/")
  end

  def hostname
    @hostname ||= Dependabot::Application.target_github_hostname(update_job.update_config.repo.account)
  end

  def error_detail
    error_hash["error-detail"]
  end

  class GitDependenciesNotSupportedPresenter
    GITHUB_SHORT_PATH_PATTERN = %r{^[^:/]+/[^:/]+$}
    GIT_REGISTRY_HELP_URL = "https://docs.github.com/en/code-security/supply-chain-security/configuration-options-for-dependency-updates#git"
    MANUAL_TRIGGER_HELP_URL = "https://docs.github.com/en/free-pro-team@latest/github/managing-security-vulnerabilities/troubleshooting-dependabot-errors#triggering-a-dependabot-pull-request-manually"
    ORG_ACCOUNT_HELP_URL = "https://docs.github.com/en/free-pro-team@latest/github/getting-started-with-github/types-of-github-accounts#organization-accounts"
    REPO_ACCESS_HELP_URL = "https://docs.github.com/en/free-pro-team@latest/github/setting-up-and-managing-organizations-and-teams/managing-security-and-analysis-settings-for-your-organization#allowing-dependabot-to-access-private-repositories"

    def initialize(issue_detail:, update_job:)
      @issue_detail = issue_detail
      @update_job = update_job
    end

    def title
      "Dependabot failed to update your dependencies"
    end

    def body
      summary =
        "The following git repository was unreachable and caused the update to fail: [#{repo_name}](#{repo_url})."
      private_git_registry_footer = "Please consider using a [git registry](#{GIT_REGISTRY_HELP_URL})."

      details = []
      if package_manager_lacks_repo_access?
        details.push(
          "Dependabot can't update #{update_job.package_manager} dependency files that reference private " \
          "git repositories. #{private_git_registry_footer}"
        )
      end

      if dependency_owned_by_other_account?
        details.push(
          "Dependabot can't update dependency files that reference private git repositories owned by " \
          "other accounts. #{private_git_registry_footer}"
        )
      end

      if non_github_url?
        details.push(
          "Dependabot can't update dependency files that reference private git repositories hosted on " \
          "external sites. #{private_git_registry_footer}"
        )
      end

      if public_repo?
        details.push(
          "Public repositories don’t support updating dependency files that reference private git repositories. " +
          private_git_registry_footer
        )
      end

      if user_account?
        details.push(
          "Personal user accounts don't support updating dependency files that reference private git repositories. " \
          "To use Dependabot with dependency files that reference private git repositories, you can use a " \
          "[git registry](#{GIT_REGISTRY_HELP_URL}), or you can use an " \
          "[organization account](#{ORG_ACCOUNT_HELP_URL}) and " \
          "[grant Dependabot access to private repositories](#{REPO_ACCESS_HELP_URL})."
        )
      end

      if details.empty?
        details.push(
          "If this repository exists, you can fix the issue by " \
          "[granting Dependabot access to the repository](#{REPO_ACCESS_HELP_URL}) and then " \
          "[checking for updates again](#{MANUAL_TRIGGER_HELP_URL})."
        )
      end

      [summary, *details].join("\n\n")
    end

    private

    attr_reader :issue_detail, :update_job

    def account
      update_config&.account
    end

    def dependency_owned_by_other_account?
      return false if non_github_url?
      return false if account.nil?

      owner, _name = issue_detail.split("/").last(2)

      owner != account.github_login
    end

    def non_github_url?
      repo_url.exclude?(hostname)
    end

    def package_manager_lacks_repo_access?
      UpdateConfig::PACKAGE_MANAGERS_WITH_CODE_EXECUTION.include?(update_job.package_manager)
    end

    def public_repo?
      !update_config&.repo&.private?
    end

    def repo_name
      issue_detail.split("/").last
    end

    def repo_url
      if issue_detail.match?(GITHUB_SHORT_PATH_PATTERN)
        "https://#{hostname}/#{issue_detail}"
      else
        issue_detail
      end
    end

    def hostname
      @hostname ||= Dependabot::Application.target_github_hostname(update_job.update_config.repo.account)
    end

    def update_config
      update_job&.update_config
    end

    def user_account?
      account&.user?
    end
  end
end
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/ClassLength
# rubocop:enable Metrics/CyclomaticComplexity
