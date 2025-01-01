module OneOffImporters
  class Pypi < Base
    PACKAGE_MANAGER = "pip"

    # Request JSON from PyPi for a specific package.
    #
    def request
      url = "https://pypi.org/pypi/#{package_name}/json"
      response = HTTParty.get(url)

      raise "Error requesting PyPi package: HTTP #{response.code} #{response.message}" unless response.ok?

      response.to_hash
    end

    # Transform the data from PyPi into something we expect.
    #
    def parse(request_input)
      releases = []

      request_input["releases"].each do |version, info|
        parsed_version = info.first
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
      PACKAGE_MANAGER = "pip"

      attr_reader :info, :parsed_version, :version

      def initialize(request_input:, version: , parsed_version:)
        @info =  request_input["info"]
        @parsed_version = parsed_version
        @version = version
      end

      def to_hash
        data = {
          "authors" => authors,
          "description" => description,
          "home_url" => home_url,
          "package_manager" => PACKAGE_MANAGER,
          "package_name" => package_name,
          "version" => version,
          # FIXME: It doesn't look like the JSON API currently supports returning dependencies - maybe we can open a PR?
          #   https://github.com/pypa/warehouse/blob/master/warehouse/legacy/api/json.py
        }
        unless parsed_version.nil?
          data["download_count"] = download_count
          data["published_at"] = published_at
        end
        data
      end

      private

      def authors
        info["author"]
      end

      def description
        info["summary"]
      end

      def download_count
        downloads = parsed_version["downloads"]
        downloads.is_a?(String) ? downloads.to_i : nil
      end

      def home_url
        info["home_page"]
      end

      def package_name
        info["name"]
      end

      def published_at
        parsed_version["upload_time"]
      end
    end
  end
end
