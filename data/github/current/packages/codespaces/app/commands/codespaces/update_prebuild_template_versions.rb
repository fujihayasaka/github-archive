
# typed: true
# frozen_string_literal: true

module Codespaces
  class UpdatePrebuildTemplateVersions < Command

    class Error < Codespaces::Error; end
    class ConnectionFailed < Codespaces::UpdatePrebuildTemplateVersions::Error; end
    class BadResponse < Codespaces::UpdatePrebuildTemplateVersions::Error; end
    class InvalidLocation < Codespaces::UpdatePrebuildTemplateVersions::Error; end

    attr_reader :prebuild_configuration_id, :location

    def initialize(prebuild_configuration_id:, location:)
      @prebuild_configuration_id = prebuild_configuration_id
      @location = location
    end

    def perform
      begin
        if prebuild_configuration.present?
          validate!

          client = get_client(
            location: location,
            vscs_target: prebuild_configuration.vscs_target,
            vscs_target_url: prebuild_configuration.vscs_target_url,
            branch: prebuild_configuration.branch
          )

          client.update_prebuild_template_versions(
            location: location,
            repository: prebuild_configuration.repository,
            branch: prebuild_configuration.branch,
            maximum_template_versions: prebuild_configuration.maximum_template_versions,
            vscs_target: prebuild_configuration.vscs_target,
            devcontainer_path: prebuild_configuration.devcontainer_path
          )

          GitHub.logger.info(
            "template versions updated",
            "gh.catalog_service" => "github/codespaces",
            "gh.codespaces.prebuild_configuration.id" => prebuild_configuration.id,
            "gh.codespaces.maximum_prebuild_template_versions" => prebuild_configuration.maximum_template_versions,
          )

        end
      rescue Codespaces::Client::BadResponseError => e
        raise BadResponse, "Bad response: #{e.message}"
      rescue VscsClient::TimeoutError, VscsClient::ConnectionFailed
        raise ConnectionFailed, "Connection failed"
      end
    end

    private

    def validate!
      unless prebuild_configuration.region_names.include?(location)
        raise InvalidLocation, "Location #{location} is not configured for prebuild configuration #{prebuild_configuration.id}"
      end
    end

    def get_client(location:, vscs_target:, vscs_target_url:, branch:)
      Codespaces::VscsClient.for_prebuild(
        location: location,
        vscs_target: vscs_target,
        vscs_target_url: vscs_target_url,
        branch: branch,
      )
    end

    def prebuild_configuration
      return @prebuild_configuration if defined?(@prebuild_configuration)
      @prebuild_configuration = Codespaces::PrebuildConfiguration.find_by(id: prebuild_configuration_id)
    end
  end
end
