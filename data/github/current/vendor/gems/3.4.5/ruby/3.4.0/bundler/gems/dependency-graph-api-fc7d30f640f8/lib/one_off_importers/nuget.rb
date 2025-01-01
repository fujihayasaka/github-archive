module OneOffImporters
  class Nuget < Base
    # Request JSON from Nuget for a specific package.
    #
    def request(url: "https://api.nuget.org/v3/registration3/#{package_name.downcase}/index.json")
      response = HTTParty.get(url)

      raise "Error requesting Nuget package: HTTP #{response.code} #{response.message}" unless response.ok?
      response.to_hash
    end

    # Transform the data from Nuget into something we expect.
    #
    def parse(request_input)
      releases = []

      # need to check if package index has all the versions or it's just a list of pages of json we need to also request
      items = []

      if request_input["items"].size > 1
        request_input["items"].each do |page|
          #need to make a request for every page, then add to the items array
          page_request = request(url: page["@id"])
          items += page_request["items"]
        end
      else
        items = request["items"][0]["items"]
      end

      items.each do |item|
        parsed_version = ParsedVersion.new(
          parsed_version: item["catalogEntry"],
          request_input: request_input,
          version: item["catalogEntry"]["version"],
        )
        releases << parsed_version.to_hash
      end

      releases
    end

    class ParsedVersion
      PACKAGE_MANAGER = "nuget"

      attr_reader :info, :authors, :description, :package_name, :published_at, :source_url, :version, :dependency_groups

      def initialize(request_input:, version: , parsed_version:)
        @authors = parsed_version["authors"]
        @description = parsed_version["description"]
        @package_name = parsed_version["id"]
        @published_at = parsed_version["published"]
        @source_url = parsed_version["projectUrl"]
        @version = version
        @dependency_groups = parsed_version["dependencyGroups"]
      end

      def to_hash
        {
          "authors" => authors,
          "description" => description,
          "package_manager" => PACKAGE_MANAGER,
          "package_name" => package_name,
          "published_at" => published_at,
          "source_url" => source_url,
          "version" => version,
          "dependencies" => dependencies,
        }
      end

      private

      def dependencies
        return [] if dependency_groups.blank?

        dependencies = []

        dependency_groups.each do |group|
          unless group["dependencies"].nil?
            dependencies += group["dependencies"].map do |dependency|
              { package_name: dependency["id"], requirements: dependency["range"] }
            end
          end
        end

        dependencies
      end
    end
  end
end
