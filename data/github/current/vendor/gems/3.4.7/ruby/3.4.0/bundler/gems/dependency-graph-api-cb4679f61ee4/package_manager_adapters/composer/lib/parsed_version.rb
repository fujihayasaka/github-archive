module Composer
  class ParsedVersion
    PACKAGE_MANAGER = "composer"

    attr_reader :info, :description, :home_url, :package_name, :raw_version

    def initialize(raw_version: , info:)
      @info = info
      @description = info["description"]
      @home_url = info["homepage"]
      @package_name = info["name"]
      @raw_version = raw_version
    end

    def to_hash
      raise NotImplementedError, "You need to override the to_hash method in your own class!"
    end

    private

    def version
      raw_version.gsub(/\Av/, "") # some packages have 'v' in front of them, this removes them
    end

    def authors
      begin
        info["authors"].nil? ? "" : info["authors"].map { |author| author.is_a?(Hash) ? author.fetch("name", "").to_s : "" }.join(", ")
      rescue => e
        Failbot.report(e,
          "gh.dependency_graph.package_name" => package_name,
          "gh.dependency_graph.package_authors_hash" => info["authors"].to_s
        )
        raise e
      end
    end

    def published_at
      info["time"].nil? ? "" : Time.parse(info["time"]).to_i
    end

    def source_url
      info["source"].nil? ? "" : info["source"]["url"]
    end

    def dependencies
      mapped_dependencies(:runtime, info["require"]) +
        mapped_dependencies(:development, info["require-dev"])
    end

    def mapped_dependencies(scope, dependencies)
      return [] if dependencies.nil?

      dependencies.map do |name, requirement|
        { package_name: name, requirements: requirement, scope: scope }
      end
    end
  end
end
