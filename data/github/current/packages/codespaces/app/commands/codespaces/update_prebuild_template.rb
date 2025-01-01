# typed: true
# frozen_string_literal: true

module Codespaces
  class UpdatePrebuildTemplate < Command

    class Error < Codespaces::Error; end
    class ConnectionFailed < Codespaces::UpdatePrebuildTemplate::Error; end
    class BadResponse < Codespaces::UpdatePrebuildTemplate::Error; end
    class InvalidTemplateState < Codespaces::UpdatePrebuildTemplate::Error; end
    class FeatureNotSupported < Codespaces::UpdatePrebuildTemplate::Error; end

    def initialize(guid:, repository:, state:)
      @guid = guid
      @repository = repository
      @state = state
    end

    def perform
      begin
        validate!

        if prebuild_template.present?
          is_success = state == "archived"
          client.update_prebuild_template_status(
            location: prebuild_template.location,
            template_guid: prebuild_template.guid,
            is_success: is_success,
          )

          prebuild_template.update!(state: state)

          configuration = prebuild_template.configuration

          if configuration.present?
            Codespaces::UpdatePrebuildTemplateVersionsJob.perform_later(
              prebuild_configuration_id: configuration.id,
              repository: repository,
              location: prebuild_template.location,
              vscs_target: prebuild_template.vscs_target,
            )
          end

          prebuild_template
        end
      rescue Codespaces::Client::BadResponseError
        raise BadResponse, "Bad response"
      rescue VscsClient::TimeoutError, VscsClient::ConnectionFailed
        raise ConnectionFailed, "Connection failed"
      end
    end

    private

    attr_reader :guid, :repository, :state

    def prebuild_template
      return @prebuild_template if defined?(@prebuild_template)
      @prebuild_template = PrebuildTemplate.find_by(guid: guid, repository: repository)
    end

    def client
      VscsClient.for_prebuild(
        location: prebuild_template.location,
        oid: prebuild_template.oid,
        branch: prebuild_template.branch,
        vscs_target: prebuild_template.vscs_target,
        vscs_target_url: prebuild_template.vscs_target_url,
      )
    end

    def validate!
      unless repository&.owner.codespaces_feature_enabled?
        raise FeatureNotSupported, "prebuilds are not supported for this repository"
      end

      if !state.present? || !%w[archived failed].include?(state)
        raise InvalidTemplateState, "prebuild template state must be archived or failed"
      end
    end
  end
end
