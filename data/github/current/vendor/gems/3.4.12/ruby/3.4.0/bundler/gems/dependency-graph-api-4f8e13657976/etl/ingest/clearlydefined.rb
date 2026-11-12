require "net/http"
require "uri"
require "json"
module Ingest
  module Clearlydefined
    class Config
      attr_reader :harvester_host, :harvester_auth_token, :harvester_enabled

      def initialize
        @harvester_host = ENV["CLEARLYDEFINED_HARVESTER_HOST"] || "https://ospo-clearlydefined-harvester-gh-staging.service.iad.github.net"
        @harvester_auth_token = ENV["CLEARLYDEFINED_HARVESTER_AUTH_TOKEN"]
        @harvester_enabled = ENV["CLEARLYDEFINED_HARVESTER_ENABLED"] == "true"
      end
    end

    class Harvester
      def initialize(config)
        @auth_token = config.harvester_auth_token
        @endpoint = "#{config.harvester_host}/requests"
      end

      def harvest(package_manager, package_with_version)
        payload = get_harvester_payload(package_manager, package_with_version)
        return false unless payload

        unless send_harvest_request(payload)
          DependencyGraph.logger.error(
            "Failed to send harvest request with payload #{payload}",
            "gh.job.name" => "package_loader")
          return false
        end
        true
      end

      def get_harvester_payload(package_manager, package_with_version)

        # Define mapping of package managers to their coordinate converters
        coordinate_converters = {
          rubygems: :convert_to_rubygems_coordinates,
          npm: :convert_to_npm_coordinates,
          pip: :convert_to_pypi_coordinates,
          maven: :convert_to_maven_coordinates,
          nuget: :convert_to_nuget_coordinates,
          composer: :convert_to_composer_coordinates,
          go: :convert_to_go_coordinates,
          rust: :convert_to_rust_coordinates
        }

        # Handle unsupported package managers
        unsupported_managers = [:actions, :pub, :swift]
        return if unsupported_managers.include?(package_manager.to_sym)

        # Get the converter method for the package manager
        converter_method = coordinate_converters[package_manager.to_sym]
        if converter_method
          coordinates = send(converter_method, package_with_version)
          return if coordinates.nil?
          convert_to_harvester_payload(coordinates)
        else
          DependencyGraph.logger.error(
            "Package manager '#{package_manager}' is UNKNOWN.",
            "gh.job.name" => "package_loader"
          )
          return
        end
      end

      def convert_to_harvester_payload(coordinates)
        {
          "type" => "package",
          "url" => "cd:/#{coordinates}"
        }
      end

      def convert_to_rubygems_coordinates(package_version)
        parts = package_version.split("/")
        if parts.length == 2
          package_name = parts[0]
          version = parts[1]
        else
          DependencyGraph.logger.error(
            "******** Invalid rubygems package-version: #{package_version}",
            "gh.job.name" => "package_loader")
          return nil
        end

        "gem/rubygems/-/#{package_name}/#{version}"
      end

      def convert_to_npm_coordinates(package_version)
        parts = package_version.split("/")
        if parts.length == 2
          namespace = "-"
          package_name = parts[0]
          version = parts[1]
        elsif parts.length == 3
          namespace = parts[0]
          package_name = parts[1]
          version = parts[2]
        else
          DependencyGraph.logger.error(
            "******** Invalid npm package-version: #{package_version}",
            "gh.job.name" => "package_loader")
          return nil
        end

        "npm/npmjs/#{namespace}/#{package_name}/#{version}"
      end

      def convert_to_pypi_coordinates(package_version)
        parts = package_version.split("/")
        if parts.length == 2
          package_name = parts[0]
          version = parts[1]
        else
          DependencyGraph.logger.error(
            "******** Invalid pip package-version: #{package_version}",
            "gh.job.name" => "package_loader")
          return nil
        end

        "pypi/pypi/-/#{package_name}/#{version}"
      end

      def convert_to_maven_coordinates(package_version)
        parts = package_version.split("/")
        if parts.length == 2
          ns_pn = parts[0]
          version = parts[1]

          parts = ns_pn.split(":")
          if parts.length == 2
            namespace = parts[0]
            package_name = parts[1]
          else
            DependencyGraph.logger.error(
              "******** Invalid maven namespace + package_name: #{package_version}",
              "gh.job.name" => "package_loader")
            return nil
          end
        else
          DependencyGraph.logger.error(
            "******** Invalid maven package-version: #{package_version}",
            "gh.job.name" => "package_loader")
          return nil
        end

        provider = if namespace.include?("android")
                     "mavengoogle"
                  elsif package_name.include?("gradle")
                    "gradleplugin"
                  else
                    "mavencentral"
                  end

        "maven/#{provider}/#{namespace}/#{package_name}/#{version}"
      end

      def convert_to_nuget_coordinates(package_version)
        parts = package_version.split("/")
        if parts.length == 2
          package_name = parts[0]
          version = parts[1]
        else
          DependencyGraph.logger.error(
            "******** Invalid nuget package-version: #{package_version}",
            "gh.job.name" => "package_loader")
          return nil
        end

        "nuget/nuget/-/#{package_name}/#{version}"
      end

      def convert_to_composer_coordinates(package_version)
        parts = package_version.split("/")
        if parts.length == 3
          namespace = parts[0]
          package_name = parts[1]
          version = parts[2]
        else
          DependencyGraph.logger.error(
            "******** Invalid composer package-version: #{package_version}",
            "gh.job.name" => "package_loader")
          return nil
        end

        "composer/packagist/#{namespace}/#{package_name}/#{version}"
      end

      def convert_to_go_coordinates(package_version)
        parts = package_version.split("/")
        if parts.length >= 3
          version = parts[-1]
          package_name = parts[-2]
          namespace = parts[0...-2].join("%2f")
        else
          DependencyGraph.logger.error(
            "******** Invalid gomod package-version: #{package_version}",
            "gh.job.name" => "package_loader")
          return nil
        end

        "go/golang/#{namespace}/#{package_name}/#{version}"
      end

      def convert_to_rust_coordinates(package_version)
        parts = package_version.split("/")
        if parts.length == 2
          package_name = parts[0]
          version = parts[1]
        else
          DependencyGraph.logger.error(
            "******** Invalid rust package-version: #{package_version}",
            "gh.job.name" => "package_loader")
          return nil
        end

        "crate/cratesio/-/#{package_name}/#{version}"
      end

      def error_unknown(package_manager_id)
        DependencyGraph.logger.error(
          "Package manager '#{package_manager_id}' is UNKNOWN.",
          "gh.job.name" => "package_loader")
      end

      def send_harvest_request(payload)
        unless @auth_token
          DependencyGraph.logger.error(
            "******** CRAWLER_SERVICE_AUTH_TOKEN not set",
            "gh.job.name" => "package_loader")
          return false
        end

        headers = { "X-token" => @auth_token }

        begin

          uri = URI(@endpoint)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"

          request = Net::HTTP::Post.new(uri.path)
          headers.each { |key, value| request[key] = value }
          request.body = payload.to_json
          request["Content-Type"] = "application/json"

          response = http.request(request)

          if response.code == "201" # HTTP Status CREATED
            DependencyGraph.logger.debug(
              "******** Harvester request successfully created",
              "gh.job.name" => "package_loader")
            return true # successfully created harvest request
          else
            DependencyGraph.logger.error(
              "Harvester request failed: #{response.code}, body: #{response.body}",
              "gh.job.name" => "package_loader")
          end
        rescue StandardError => e
          DependencyGraph.logger.error(
            "Harvester request exception: #{e}",
            "gh.job.name" => "package_loader")
        end

        false # failed to send harvest request
      end
    end
  end
end
