require "httparty"
require "json"
require_relative "repository_finder"

class ClearlyDefined
  include HTTParty
  include RepositoryFinder

  base_uri "https://api.clearlydefined.io"
  headers "Content-Type"=>"application/json"
  MIRROR_URL = "https://clearlydefinedprod.blob.core.windows.net/production-definition/"

  # Takes in package versions and returns a hash of package versions and their respective json data obtained from Clearly Defined
  def get_definitions(package_versions, retries = 5)
    clearly_defined_requests = package_versions.collect { |package_version| package_coordinates(package_version) }
    definitions = {}

    begin
      response = Instrument.time("sync_package_versions.clearly_defined_api_request_time") do
        self.class.post("/definitions/?expand=-files/", body: clearly_defined_requests.to_json)
      end

      if response.code != 200
        Instrument.increment("sync_package_versions.bad_clearly_defined_api_request", status: response.code)
        DependencyGraph.logger.info("Non-200 HTTP response in ClearlyDefined#get_definitions",
          "gh.dependency_graph.clearly_defined.response.body" => response.body[0..500],
          "gh.dependency_graph.clearly_defined.response.code" => response.code,
        )
        return nil
      end

      # json returned contains json data for package versions obtained from clearly defined
      package_versions_json = begin
        JSON.parse(response.body)
      rescue ArgumentError, JSON::ParserError => e
        Failbot.report(e)
        DependencyGraph.logger.info("Unexpected exception occurred in get_definitions", "exception.type" => e, "gh.dependency_graph.clearly_defined.response.code" => response.code)
        return nil
      end

      # map package version object to its corresponding response from clearly defined
      package_versions.map { |package_version, defintion| definitions[package_version] = package_versions_json[package_coordinates(package_version)] }

    rescue Timeout::Error => e
      Instrument.increment("sync_package_versions.clearly_defined_server_time_outs")
      if retries > 0
        # Sleep for 3 seconds after each timed out batched process
        sleep(3)
        get_definitions(package_versions, retries-1)
      else
        return nil
      end
    end

    definitions
  end

  def get_mirror_definition(coordinates)
    package_version_mirror_url = MIRROR_URL + coordinates + ".json"

    # mirror url uses downcase for all package names
    package_version_mirror_url = package_version_mirror_url.downcase

    response = begin
      HTTParty.get(package_version_mirror_url)
    rescue URI::InvalidURIError, Timeout::Error, Errno::ECONNREFUSED => e
      Failbot.report(e)
      DependencyGraph.logger.info("Unexpected exception occurred in get_mirror_definition", "exception.type" => e, "gh.exception.is_timeout" => true, "url.full" => package_version_mirror_url)
      nil
    end
  end

  # Enqueues harvesting jobs onto Clearly Defined to grab missing package release data from their records
  def harvest(harvest_queue, retries = 5)
    body = harvest_queue.map { |package_version| { "coordinates": package_coordinates(package_version) } }.to_json

    DependencyGraph.logger.info("Attempting to harvest data for package versions",
      "gh.dependency_graph.clearly_defined.harvest_queue_count" => harvest_queue.count,
    )

    begin
      harvest_response = Instrument.time("sync_package_versions.clearly_defined_harvest_api_request_time") do
        self.class.post("/harvest/?turbo=true", body: body)
      end

      # 201 is response code for creation
      if harvest_response.code == 201
        DependencyGraph.logger.info("Successfully harvested data for package versions",
          "gh.dependency_graph.clearly_defined.harvest_queue_count" => harvest_queue.count,
        )
        Instrument.count("sync_package_versions.package_versions_harvested", harvest_queue.count)
      else
        DependencyGraph.logger.info("Failed to harvest data for package versions. Got non-201 response code from Clearly Defined",
          "gh.dependency_graph.clearly_defined.harvest_queue_count" => harvest_queue.count,
          "http.response.status_code" => harvest_response.code,
        )
        Instrument.count("sync_package_versions.failed_package_versions_harvests", harvest_queue.count)
      end
    rescue Timeout::Error => e
      Instrument.increment("sync_package_versions.clearly_defined_harvest_server_time_outs")
      if retries > 0
        # Sleep for 3 seconds after each timed out batched process
        sleep(3)
        harvest(harvest_queue, retries-1)
      else
        return nil
      end
    end
  end

  # Returns the desired coordinate URL for a given package version
  def package_coordinates(package_version)
    package_name = package_version.package_name
    package_manager = package_version.package_manager.human_name.downcase
    version = package_version.version

    package_version_path = case package_manager
    when "npm"
      npm_package_coordinate(package_name, version, harvest = true)
    when "maven"
      org_id, artifact_id = package_name.split(":")
      "maven/mavencentral/#{org_id}/#{artifact_id}/#{version}"
    when "rubygems"
      "gem/rubygems/-/#{package_name}/#{version}"
    when "pip"
      "pypi/pypi/-/#{package_name}/#{version}"
    when "composer"
      "composer/packagist/#{package_name}/#{version}"
    when "go modules"
      namespace_parts = package_name.split("/")
      package = namespace_parts.pop
      namespace = namespace_parts.join("%2f")
      "go/golang/#{namespace}/#{package}/#{version}"
    else
      "#{package_manager}/#{package_manager}/-/#{package_name}/#{version}"
    end
  end

  def mirror_coordinates(batch)
    mirror_coordinates = {}
    batch.each { |package_version| mirror_coordinates[package_version] = mirror_coordinate(package_version) }

    mirror_coordinates
  end

  # Returns the desired mirror coordinate URL for a given package version
  def mirror_coordinate(package_version)
    package_name = package_version.package_name
    package_manager = package_version.package_manager.human_name.downcase
    version = package_version.version

    package_version_path = case package_manager
    when "npm"
      npm_package_coordinate(package_name, version)
    when "maven"
      org_id, artifact_id = package_name.split(":")
      "maven/mavencentral/#{org_id}/#{artifact_id}/revision/#{version}"
    when "rubygems"
      "gem/rubygems/-/#{package_name}/revision/#{version}"
    when "pip"
      "pypi/pypi/-/#{package_name}/revision/#{version}"
    when "composer"
      "composer/packagist/#{package_name}/revision/#{version}"
    else
      "#{package_manager}/#{package_manager}/-/#{package_name}/revision/#{version}"
    end
  end

  # Returns coordinate for npm package depending on whether package is scoped or not
  # Uses Regex to catch npm package name into respective matching groups and determines if package is scoped
  # Scoped packages have the same mirror and harvest coordinates so if package is scope, we use scoped coordinate
  # Unscoped packages have different harvest and mirror coordinates, so if we are in mirror mode, coordinated changes
  def npm_package_coordinate(package_name, version, harvest = false)
    match = package_name.match(/^(?:@([^\/]+)\/)?([^\/]+)$/)

    # explicitly doing this cause for some reason assigning variables to match does not work
    full_package_name, scope, name = match[0], match[1], match[2]
    coordinate = nil

    if harvest
      coordinate = (scope.nil?) ? "npm/npmjs/-/#{package_name}/#{version}" : "npm/npmjs/@#{scope}/#{name}/#{version}"
    else
      coordinate = (scope.nil?) ? "npm/npmjs/-/#{package_name}/revision/#{version}" : coordinate = "npm/npmjs/@#{scope}/#{name}/revision/#{version}"
    end

    coordinate
  end

  # Checks if package version object response from clearly defined has valid license data
  def has_license_data?(package_version)
    package_version["licensed"].present? && package_version["licensed"]["declared"].present? && (package_version["licensed"]["toolScore"]["total"] != 0)
  end

  # Checks if the package version message from CD has attributions attached to it
  def has_attribution_data?(package_version)
    !package_version.dig("licensed", "facets", "core", "attribution", "parties").nil?
  end

  # Updates the license data for specified package version
  def update_license_data(package_version, license, clearly_defined_score, checkpoint)
    return unless package_version.present?
    return unless clearly_defined_score.present?
    return unless license.present?

    ActiveRecord::Base.connected_to(role: :writing) do
      # license column has length of 255 characters
      # SPDX licenses can have a very long combination that can surpass column string length
      # Truncate SPDX string if it exceeds 255 character limit DB column supports
      if license.length > 254
        license = license.truncate(250)
      end

      package_version.update(license: license, clearly_defined_score: clearly_defined_score)
    end
  end

  # Updates the license data for specified package version
  def update_attributions_data(package_version, attributions, checkpoint)
    return unless package_version.present?
    return unless attributions.present?

    ActiveRecord::Base.connected_to(role: :writing) do
      Attribution.upsert_all(
        attributions.map do |data|
          {
            dg_package_versions_id: package_version.id,
            attribution: data
          }
        end
      )
    end
  end

  # Updates the repo_nwo column for a package and all its associated versions
  def update_repo_id_on_packages_and_releases(package_version, repo_nwo)
    return unless package_version.present?
    return unless repo_nwo.present?

    ActiveRecord::Base.connected_to(role: :writing) do
      repo_id = get_gh_repo_id(nwo: repo_nwo)
      return if repo_id.nil?

      if package_version.package.repository_id.nil?
        package_version.package.update(repository_id: repo_id, repository_id_certainty: PackageToRepoMapping::Certainty::CLEARLY_DEFINED_MATCH)
      end

      PackageRelease.where(package_id: package_version.package_id, repository_id: [nil, 0]).update_all(repository_id: repo_id, repository_id_certainty: PackageToRepoMapping::Certainty::CLEARLY_DEFINED_MATCH)
    end
  end

  def process_package_version_licenses(package_version_json, package_version, package_name, package_manager, version, checkpoint)
    if has_license_data?(package_version_json)
      declared_license = package_version_json["licensed"]["declared"]
      clearly_defined_score = package_version_json["licensed"]["score"]["total"]

      # Update the license data and clearly defined score for given package release
      DependencyGraph.logger.info("Updating license data for package", "gh.dependency_graph.package.name" => package_name, "gh.dependency_graph.package_manager" => package_manager, "gh.dependency_graph.package.version" => version)
      update_license_data(package_version, declared_license, clearly_defined_score, checkpoint)

      Instrument.increment("sync_package_versions.licenses_processed", license_type: declared_license, package_manager: package_manager)
    else
      Instrument.increment("sync_package_versions.no_licenses_found", package_manager: package_manager)
      DependencyGraph.logger.info("No License Data in Clearly Defined for package", "gh.dependency_graph.package.name" => package_name, "gh.dependency_graph.package.version" => version, "gh.dependency_graph.package_manager" => package_manager)
    end

    if has_attribution_data?(package_version_json)
      attributions = package_version_json.dig("licensed", "facets", "core", "attribution", "parties")

      # Update the license data and clearly defined score for given package release
      DependencyGraph.logger.info("Updating attribution data for package", "gh.dependency_graph.package.name" => package_name, "gh.dependency_graph.package_manager" => package_manager, "gh.dependency_graph.package.version" => version)

      update_attributions_data(package_version, attributions, checkpoint)

      Instrument.increment("sync_package_versions.attributions_processed", package_manager: package_manager)
    else
      Instrument.increment("sync_package_versions.no_attributions_found", package_manager: package_manager)
      DependencyGraph.logger.info("No Attribution Data in Clearly Defined for package", "gh.dependency_graph.package.name" => package_name, "gh.dependency_graph.package.version" => version, "gh.dependency_graph.package_manager" => package_manager)
    end

    # Update checkpoint to processed package version's id if checkpoint is passed
    checkpoint.blank? ? return : Checkpoint.where(name: checkpoint.name).update(last_checkpointed_id: package_version.id)

    version_source = package_version_json["described"]["sourceLocation"]

    # If desired package version is hosted on GitHub, and it has nil repo_id field, use nwo to update it
    if version_source.present? && (version_source["provider"] == "github") && package_version.repository_id.nil?
      namespace = version_source["namespace"]
      name = version_source["name"]
      repo_nwo = "#{namespace}/#{name}"

      # Update the repo_id for associated package and package release
      DependencyGraph.logger.info("Updating repo_id for package and its associated versions", "gh.dependency_graph.package.name" => package_name, "gh.dependency_graph.package_manager" => package_manager)
      update_repo_id_on_packages_and_releases(package_version, repo_nwo)
    end

    # NOTE: All licenses in a package version, and asset url of a package version are properties we could persist in the future
    # To get All licenses: package_version_json["licensed"]["facets"]["core"]["discovered"]["expressions"]
    # To get asset url/download link of package version: package_version_json["described"]["urls"]["download"]
  end
end
