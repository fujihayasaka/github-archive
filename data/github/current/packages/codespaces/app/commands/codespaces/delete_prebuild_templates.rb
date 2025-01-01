# typed: true
# frozen_string_literal: true

module Codespaces
  # delete from vscs db
  class DeletePrebuildTemplates < Command
    class Error < Codespaces::Error; end

    attr_reader :repository, :repository_id, :branch, :locations, :vscs_target, :vscs_target_url, :devcontainer_path, :configuration_id

    def initialize(branch:, locations:, repository_id:, vscs_target: Codespaces::Vscs.default_target, vscs_target_url: nil, devcontainer_path: nil, configuration_id: nil)
      @repository_id = repository_id
      @repository = find_repository if repository_id
      @branch = branch
      @locations = locations
      @vscs_target = vscs_target.to_sym
      @vscs_target_url = vscs_target_url
      @devcontainer_path = devcontainer_path
      @configuration_id = configuration_id
    end

    def perform
      validate!
      delete_invalid_prebuilds!

      max_attempts = 3
      retry_backoff = 0.2

      locations.each do |single_location|
        attempts = 0
        begin
          attempts += 1
          single_location_client = client_for_location(single_location)

          single_location_client.delete_prebuild_templates!(
            location: single_location,
            repository_id: repository_id,
            branch: branch,
            configuration_id: configuration_id,
            devcontainer_path: devcontainer_path,
          )

        rescue Codespaces::Client::BadResponseError, Faraday::TimeoutError, Faraday::ConnectionFailed => error
          # log the error and retry
          Failbot.report(
            error,
            "catalog_service" => "github/codespaces",
            "gh.repo.id" => repository_id,
            "gh.codespaces.vscs_target" => vscs_target,
            "gh.codespaces.region" => single_location,
          )

          if attempts <= max_attempts
            sleep retry_backoff
            retry
          end
        end
      end
    end

    private

    def validate!
      # bypass validations if repository is deleted or codespaces is disabled for org
      return if repository.blank? || repository.deleted? || codespaces_disabled_for_org?(repository.owner)

      Codespaces::ValidatePrebuildAccess.call(
        repository: repository, vscs_target: vscs_target, vscs_target_url: vscs_target_url, require_enabled_org: false
      )
    end

    def delete_invalid_prebuilds!
      return unless configuration_id

      configuration = Codespaces::PrebuildConfiguration.find_by(id: configuration_id)
      return unless configuration

      configuration.prebuild_templates.each do |template|
        unless template.matches_configuration?
          template.destroy!
        end
      end
    end

    def client_for_location(single_location)
      Codespaces::VscsClient.for_prebuild(
        location: single_location,
        vscs_target: vscs_target,
        vscs_target_url: vscs_target_url,
        branch: branch,
      )
    end

    def codespaces_disabled_for_org?(owner)
      owner&.organization? && !Codespaces::OrgPolicy.enabled_by_organization?(owner)
    end

    def find_repository
      Repository.find_by(id: repository_id)
    end
  end
end
