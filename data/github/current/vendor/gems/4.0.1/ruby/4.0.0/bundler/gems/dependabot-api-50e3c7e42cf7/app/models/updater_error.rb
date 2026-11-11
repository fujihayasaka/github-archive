# frozen_string_literal: true

class UpdaterError < StandardError
  def initialize(error_hash)
    @error_hash = error_hash
  end

  WORKING_DIRECTORY_REGEX = %r{^/home/dependabot/}

  def updater_error?
    true
  end

  def original_error_class
    error_hash.fetch("error-class") { "UnknownError" }
  end

  def message
    error_hash.fetch("error-message") { "" }
  end

  def backtrace
    error_hash.fetch("error-backtrace", "").split("\n").map do |line|
      line.sub(WORKING_DIRECTORY_REGEX, "")
    end
  end

  def rollup
    Digest::SHA256.hexdigest("#{original_error_class}#{backtrace.first}#{fingerprint}")
  end

  def failbot_context
    {
      "package-manager" => package_manager,
      "job-dependencies" => job_dependencies,
      "job-dependency-groups" => job_dependency_groups,
      "fingerprint" => fingerprint,
      "rollup" => rollup,
      "security-update" => security_update,
    }.compact
  end

  private

  def package_manager
    error_hash.fetch("package-manager") { nil }
  end

  def job_dependencies
    error_hash.fetch("job-dependencies") { nil }
  end

  def job_dependency_groups
    error_hash.fetch("job-dependency-groups") { nil }
  end

  def fingerprint
    error_hash.fetch("fingerprint") { nil }
  end

  def security_update
    error_hash.fetch("security-update") { nil }
  end

  attr_reader :error_hash
end
