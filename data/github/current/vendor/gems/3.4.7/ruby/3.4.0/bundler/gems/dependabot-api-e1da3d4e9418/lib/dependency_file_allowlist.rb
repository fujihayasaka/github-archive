# frozen_string_literal: true

require "ecosystem_file_regex.rb"

# This class checks if a given dependency file name is allowed for a specific package manager
# It checks if a given file name matches the allowed patterns for the corresponding package manager
# and logs any unauthorized access attempts.
# Issue: https://github.com/github/dependabot-updates/issues/5840

class DependencyFileAllowlist
  class PackageManagerNotFound < StandardError; end

  def initialize(update_job)
    @update_job_id = update_job.id
    @package_manager = update_job.package_manager
  end

  def allowed?(file_name)
    unless allowed_patterns.any? { |pattern| file_name.match?(pattern) }
      Dependabot::Logger.info(
        "code.namespace": "DependencyFileAllowlist",
        msg: "File update not allowed by Allowlist",
        update_job_id: @update_job_id,
        package_manager: @package_manager,
        file_name: file_name
      )
      return false
    end
    true
  end

  private

  def allowed_patterns
    regex_provider = EcosystemFileRegex.new(@package_manager)
    regex_provider.updated_files_regex
  rescue NoMethodError => e
    handle_no_method_error(e)
  rescue StandardError => e
    handle_standard_error(e)
  end

  def handle_no_method_error(error)
    Dependabot::Logger.info(
      msg: "The file_updater_class for #{@package_manager} does not define `updated_files_regex`",
      "code.namespace": self.class.name.to_s,
      "update_job.id": @update_job_id,
      "exception.type": error.class,
      "exception.message": error.message
    )
    raise NoMethodError,
          "The file_updater_class for #{@package_manager} does not define `updated_files_regex`."
  end

  def handle_standard_error(error)
    Dependabot::Logger.info(
      msg: error.message,
      "code.namespace": self.class.name.to_s,
      "update_job.id": @update_job_id,
      "exception.type": error.class,
      "exception.message": error.message
    )
    raise PackageManagerNotFound, error.message
  end
end
