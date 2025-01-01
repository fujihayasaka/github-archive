module OneOffImporters
  class Npm < Base
    # Request JSON from NPM for a specific package.
    #
    def request

      package_manager = "npm"

      encoded_name = URI.encode_uri_component(package_name)
      url = "https://replicate.npmjs.com/registry/#{encoded_name}"
      response = HTTParty.get(url)

      raise "Error requesting NPM package: HTTP #{response.code} #{response.message}" unless response.ok?
      response.to_hash
    end

    # Transform the data from NPM into something we expect.
    #
    def parse(request_input)
      releases = []

      request_input["versions"].each do |version, parsed_version|
        parsed_version = ParsedVersion.new(
          parsed_version: parsed_version,
          request_input: request_input,
          version: version,
        )
        releases << parsed_version.to_hash
      end

      releases
    end

    class ParsedVersion
      PACKAGE_MANAGER = "npm"

      attr_reader :author, :description, :homepage, :package_name, :published_at, :version, :license, :runtime_dependencies, :dev_dependencies, :repository, :request_input

      def initialize(request_input:, version: , parsed_version:)
        @author = parsed_version["author"]
        @description = parsed_version["description"]
        @dev_dependencies = parsed_version["devDependencies"]
        @homepage = parsed_version["homepage"]
        @package_name = parsed_version["name"]
        @license = extract_license(parsed_version)
        @published_at = request_input["time"].present? ? request_input["time"][version] : request_input["mtime"]
        @repository = parsed_version["repository"]
        @request_input = request_input
        @runtime_dependencies = parsed_version["dependencies"]
        @version = version
      end

      def to_hash
        {
          "authors" => authors,
          "dependencies" => dependencies,
          "description" => description,
          "home_url" => home_url,
          "package_manager" => PACKAGE_MANAGER,
          "package_name" => package_name,
          "license" => license,
          "published_at" => published_at,
          "source_url" => source_url,
          "version" => version,
        }
      end

      private

      def authors
        author.present? ? author["name"] : nil
      end

      def home_url
        if homepage.is_a?(String)
          homepage
        elsif homepage.is_a?(Array)
          homepage.first
        else
          request_input["homepage"] || nil
        end
      end

      # can be single string entry or array of objects
      def extract_license(ver)
        return ver["license"] if ver["license"] && ver["license"].is_a?(String)
        return ver["license"]["type"] if ver["license"] && ver["license"].is_a?(Hash)

        licenses = ver["licenses"]
        return nil if licenses.nil? || !licenses.is_a?(Array)
        return nil if licenses.empty?

        licenses.map { |l| l["type"] }.join(" OR ")
      end

      def source_url
        return nil unless repository.present?
        repo = nil

        if repository.is_a?(String)
          repo = repository
        elsif repository.is_a?(Array)
          repo = repository[0]["url"]
        else
          repo = repository["url"]
        end

        repo
      end

      def dependencies
        mapped_dependencies(:runtime, runtime_dependencies) +
          mapped_dependencies(:development, dev_dependencies)
      end

      def mapped_dependencies(scope, dependencies)
        return [] if dependencies.blank?

        dependencies.map do |dependency, version|
          { package_name: dependency, requirements: version, scope: scope }
        end
      end
    end
  end
end
