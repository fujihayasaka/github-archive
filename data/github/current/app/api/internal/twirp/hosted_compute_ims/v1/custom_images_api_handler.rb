# typed: true
# frozen_string_literal: true

require "hosted-compute-ims"

module Api::Internal::Twirp::HostedComputeIms
  module V1
    class CustomImagesApiHandler < Api::Internal::Twirp::Handler
      allow_access_for :client, allowed_clients: ["hosted_compute_ims"].freeze
      handles_service MonolithTwirp::HostedComputeIms::MonolithCustomImagesAPIService

      def get_retention_policies_for_entity(req, env)
        return Twirp::Error.invalid_argument("must be non-empty", argument: "entity_global_id") if req.entity_global_id.empty?

        entity = find_entity(req.entity_global_id)
        return Twirp::Error.not_found("entity does not exist", argument: "entity_global_id") unless entity

        {
          image_versions_per_image_limit: entity.custom_image_versions_per_image_limit,
          image_version_unused_age_limit: entity.custom_image_version_unused_age_limit,
          image_version_max_age_limit: entity.custom_image_version_max_age_limit
        }
      end

      private

      def find_entity(global_id)
        begin
          type, entity_id = Platform::Helpers::NodeIdentification.from_global_id(global_id)
        rescue Platform::Errors::NotFound
          return nil
        end

        case type
        when "Enterprise"
          Business.find_by(id: entity_id)
        when "Organization"
          Organization.find_by(id: entity_id)
        else
          nil
        end
      end
    end
  end
end
