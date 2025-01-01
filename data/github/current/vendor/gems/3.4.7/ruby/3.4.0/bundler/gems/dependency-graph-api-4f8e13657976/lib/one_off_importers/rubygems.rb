module OneOffImporters
  class Rubygems < Base
    # Request JSON from Rubygems for a specific package.
    #
    def request
      begin
        response = {}

        info_url = "https://rubygems.org/api/v1/gems/#{package_name}.json"
        info_response = HTTParty.get(info_url)

        response["info"] = info_response.to_hash

        versions_url = "https://rubygems.org/api/v1/versions/#{package_name}.json"
        versions_response = HTTParty.get(versions_url)

        response["versions"] = versions_response.to_a

        response
      rescue JSON::ParserError => e
        raise "Error requesting Rubygems package '#{package_name}': #{e.message}"
      end
    end

    # Transform the data from Rubygems into something we expect.
    #
    def parse(request_input)
      releases = []
      request_input["versions"].each do |parsed_version|
        parsed_version = ParsedVersion.new(
          parsed_version: parsed_version,
          request_input: request_input,
          version: parsed_version["number"],
        )
        releases << parsed_version.to_hash
      end

      releases
    end

    class ParsedVersion
      PACKAGE_MANAGER = "rubygems"

      attr_reader :info, :authors, :description, :published_at, :version

      def initialize(request_input:, version: , parsed_version:)
        @info = request_input["info"]
        @authors = parsed_version["authors"]
        @description = parsed_version["description"]
        @version = version
        @published_at = parsed_version["created_at"]
      end

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

      private

      def home_url
        info["homepage_uri"]
      end

      def package_name
        info["name"]
      end

      def source_url
        info["source_code_uri"]
      end

      def dependencies
        return [] if info["dependencies"].blank?

        mapped_dependencies(:runtime, info["dependencies"]["runtime"]) +
          mapped_dependencies(:development, info["dependencies"]["development"])
      end

      def mapped_dependencies(scope, dependencies)
        return [] if dependencies.blank?

        dependencies.map do |dependency|
          { package_name: dependency["name"], requirements: dependency["requirements"], scope: scope }
        end
      end
    end
  end
end
