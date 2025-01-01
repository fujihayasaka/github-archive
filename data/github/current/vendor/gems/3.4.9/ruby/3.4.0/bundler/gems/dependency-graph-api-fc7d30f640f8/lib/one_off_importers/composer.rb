require_relative "../../package_manager_adapters/composer/lib/parsed_version.rb"

module OneOffImporters
  class Composer < Base
    # Request JSON from Composer for a specific package.
    #
    def request
      response = HTTParty.get("https://repo.packagist.org/p/#{package_name.downcase.strip}.json")

      raise "Error requesting Composer package: HTTP #{response.code} #{response.message}" unless response.ok?

      packages = response.to_h["packages"]
      return {} if packages.empty?

      # sometimes this endpoint will return multiple packages (??), so make sure we only grab data from the package with an exact name match
      # If we want a specific version, we return a hash of the version's info with the version number as the key
      package = packages[package_name]

      package
    end

    # Transform the data from Composer into something we expect.
    #
    def parse(request_input)
      releases = []
      request_input.each do |raw_version, info|
        parsed_version =  ::Composer::ParsedVersion.new(
          raw_version: raw_version,
          info: info,
        )
        releases << parsed_version.to_hash
      end
      releases
    end
  end
end

module Composer
  class ParsedVersion
    # We use a shared ParsedVersion class between the one-off importer and the package manager adapter, but they send different hash formats to the sink endpoint/model
    def to_hash
      {
        "authors" => authors,
        "description" => description,
        "home_url" => home_url,
        "package_manager" => PACKAGE_MANAGER,
        "package_name" => package_name,
        "published_at" => published_at,
        "source_url" => source_url,
        "version" => version,
        "dependencies" => dependencies,
      }
    end
  end
end
