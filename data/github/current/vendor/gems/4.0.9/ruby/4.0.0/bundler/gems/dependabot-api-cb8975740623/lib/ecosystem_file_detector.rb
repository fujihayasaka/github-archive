# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

# Shared utility for detecting the presence of specific ecosystem files in a repository.
# Used by VulnerabilityAlertHandler and UpdateGraphEventHandler to
# determine the correct package manager (e.g. UV vs pip, Gradle vs Maven, Conda vs pip).
class EcosystemFileDetector
  extend T::Sig

  sig do
    params(
      package_manager: String,
      account: T.untyped,
      repo_id: Integer,
      directories: T.any(String, T::Array[String]),
      metric_prefix: String,
      ref: T.nilable(String),
      manifest_name: T.nilable(String)
    ).returns(String)
  end
  def self.resolve_package_manager(package_manager:, account:, repo_id:, directories:, metric_prefix:, ref: nil,
                                   manifest_name: nil)
    directories = Array(directories)
    case package_manager
    when PackageManagers::MAVEN
      matches_ecosystem?(PackageManagers::GRADLE, manifest_name) ? PackageManagers::GRADLE : PackageManagers::MAVEN
    when PackageManagers::PIP
      if matches_ecosystem?(PackageManagers::CONDA, manifest_name)
        PackageManagers::CONDA
      elsif uv_manifest?(manifest_name) || uv_lock_exists?(account:, repo_id:, directories:, ref:, metric_prefix:)
        PackageManagers::UV
      else
        PackageManagers::PIP
      end
    else
      package_manager
    end
  end

  sig do
    params(
      account: T.untyped,
      repo_id: Integer,
      directories: T::Array[String],
      ref: T.nilable(String),
      metric_prefix: String
    ).returns(T::Boolean)
  end
  def self.uv_lock_exists?(account:, repo_id:, directories:, ref: nil,
                           metric_prefix: "uv_lock_check")
    return false unless account

    directories.any? do |directory|
      file_path = build_file_path(directory, "uv.lock")
      check_for_file(
        account: account, repo_id: repo_id, file_path: file_path, ref: ref,
        metric_prefix: metric_prefix,
        check_event: "uv_lock_check", detected_event: "uv_lock_detected",
        not_found_event: "uv_lock_not_found", error_event: "uv_lock_check_error",
      )
    end
  end

  sig { params(manifest_name: T.nilable(String)).returns(T::Boolean) }
  def self.uv_manifest?(manifest_name)
    return false unless manifest_name

    manifest_name.match?(/\Auv\.lock\z/)
  end

  sig { params(package_manager: String, manifest_name: T.nilable(String)).returns(T::Boolean) }
  def self.matches_ecosystem?(package_manager, manifest_name)
    return false unless manifest_name

    EcosystemFileRegex.new(package_manager).updated_files_regex.any? { |pattern| manifest_name.match?(pattern) }
  end

  sig { params(directory: String, filename: String).returns(String) }
  def self.build_file_path(directory, filename)
    path = File.join(directory, filename)
    path.delete_prefix("./")
  end

  sig do
    params(
      account: T.untyped,
      repo_id: Integer,
      file_path: String,
      ref: T.nilable(String),
      metric_prefix: String,
      check_event: String,
      detected_event: String,
      not_found_event: String,
      error_event: String
    ).returns(T::Boolean)
  end
  def self.check_for_file(account:, repo_id:, file_path:, ref:, metric_prefix:,
                          check_event:, detected_event:, not_found_event:, error_event:)
    cache_key = ["ecosystem_file_exists", repo_id, ref, file_path].compact.join("/")

    MetricsClient.increment("#{metric_prefix}.#{check_event}",
                            tags: { repo_id: repo_id, cached: Rails.cache.exist?(cache_key) })

    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      fetch_file_exists(
        account: account, repo_id: repo_id, file_path: file_path, ref: ref,
        metric_prefix: metric_prefix,
        detected_event: detected_event, not_found_event: not_found_event, error_event: error_event,
      )
    end
  end

  sig do
    params(
      account: T.untyped,
      repo_id: Integer,
      file_path: String,
      ref: T.nilable(String),
      metric_prefix: String,
      detected_event: String,
      not_found_event: String,
      error_event: String
    ).returns(T::Boolean)
  end
  def self.fetch_file_exists(account:, repo_id:, file_path:, ref:, metric_prefix:,
                             detected_event:, not_found_event:, error_event:)
    client = GitHubHelpers::ClientWithRetries.new(account: account)
    T.unsafe(client).contents(repo_id, { path: file_path, ref: ref }.compact)
    MetricsClient.increment("#{metric_prefix}.#{detected_event}", tags: { repo_id: repo_id })
    true
  rescue Octokit::NotFound
    MetricsClient.increment("#{metric_prefix}.#{not_found_event}", tags: { repo_id: repo_id })
    false
  rescue StandardError => e
    MetricsClient.increment("#{metric_prefix}.#{error_event}", tags: { repo_id: repo_id })
    Dependabot::Logger.warn(
      msg: "Failed to check for #{file_path}",
      "code.namespace": name.to_s,
      "gh.repo.id": repo_id,
      "exception.type": e.class.name,
      "exception.message": e.message
    )
    false
  end

  private_class_method :uv_lock_exists?,
                       :uv_manifest?,
                       :matches_ecosystem?,
                       :build_file_path,
                       :check_for_file,
                       :fetch_file_exists
end
