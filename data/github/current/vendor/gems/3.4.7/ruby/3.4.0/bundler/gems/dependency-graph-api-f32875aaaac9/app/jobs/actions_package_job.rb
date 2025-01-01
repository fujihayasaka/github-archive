# frozen_string_literal: true
require "faraday"
require_relative "../../lib/repository_finder"

class ActionsPackageJob < RetryJob
  queue_as :actions_package
  INSTRUMENTATION_PREFIX = "actions_package_job.spokes".freeze
  include RepositoryFinder

  # Expected input: [{name: "repo/action-name", version: "1.0.0"},...]
  def perform(packages)
    packages.each do |package_release|
      name, version = package_release[:name], package_release[:version]
      owner, repo = name.split("/")
      repo_id = get_gh_repo_id(nwo: "#{owner}/#{repo}")
      next if name.nil? || version.nil? || package_release_exists?(name, version) || !version_exists_in_repo?(repo_id: repo_id, version: version)
      release = create_release(name, version)
      Rails.env.development? ? LoadPackageJob.perform_now(release) : LoadPackageJob.perform_later(release)
    end
  end

  def create_release(name, version)
    Packages::PackageRelease.new(
      package_manager: Types::PackageManager[:actions],
      package_name: name,
      version: version,
      source_url: create_package_url(name),
    )
  end

  def create_package_url(name)
    owner, repo = name.split("/")
    return "" if owner.nil? || repo.nil?

    return "https://github.com/#{owner}/#{repo}"
  end

  def package_release_exists?(name, version)
    package = Package.find_by(name: name, package_manager: Types::PackageManager[:actions])
    return false unless package

    release = PackageRelease.find_by(name: version, package_id: package.id)

    !!release
  end

  def version_exists_in_repo?(repo_id:, version:)
    return false if repo_id.nil?
    versions = get_versions(version)

    versions.each do |version|
      Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.object_exists")
      begin
        response = client.object_exists?(repository_id: repo_id, object: version, quality_of_service: :QUALITY_OF_SERVICE_DELAYABLE)
        return true if response
      rescue Faraday::TimeoutError
        Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.object_exists.timeouts")
        DependencyGraph.logger.warn("spokes object_exists timeout",
          "gh.repo.id" => repo_id,
          "gh.dependency_graph.package.version" => version,
        )
        raise
      rescue StandardError => e
        Instrument.increment("#{INSTRUMENTATION_PREFIX}.requests.object_exists.errors")
        DependencyGraph.logger.warn("spokes object_exists error",
          {
            "gh.repo.id" => repo_id,
            "gh.dependency_graph.package.version" => version,
          },
          e
        )
        raise
      end
    end
    return false
  end

  rescue_from(StandardError) do |exception|
    Failbot.report(exception,
      "gh.aqueduct.queue.name" => queue_name,
      "gh.aqueduct.job.name" => "etl.actions_package_job"
    )
  end

  private

  # get_versions returns two versions: one version as is and one with `v` prepended at the beginning,
  # as most semantic action tags are v1.0.0 but we remove the `v` in our manifest parsing.
  def get_versions(version)
    versions = [version]
    if version.match?(Versioning::VersionParser::SEMANTIC_PATTERN)
      v_prepended_version = "v" + version
      versions.push(v_prepended_version)
    end
    versions
  end

  def client
    @client ||= BlobOperations::Spokes::Client.new
  end
end
