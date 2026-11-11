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

      def get_billing_customer_id_for_entity(req, env)
        return Twirp::Error.invalid_argument("must be non-empty", argument: "entity_global_id") if req.entity_global_id.empty?

        entity = find_entity(req.entity_global_id)
        return Twirp::Error.not_found("entity does not exist", argument: "entity_global_id") unless entity

        customer_id =
          if entity.delegate_billing_to_business?
            entity.business.customer_id
          else
            entity.customer&.id
          end

        { customer_id: customer_id }
      end

      def set_retention_policies_for_entity(req, env)
        return Twirp::Error.invalid_argument("must be non-empty", argument: "entity_global_id") if req.entity_global_id.empty?

        entity = find_entity(req.entity_global_id)
        return Twirp::Error.not_found("entity does not exist", argument: "entity_global_id") unless entity

        bus = nil
        if entity.respond_to?(:business)
          bus = entity.business
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          # image_versions_per_image_limit
          if req.image_versions_per_image_limit.present? && req.image_versions_per_image_limit.value.present?
            if bus.present?
              # if entity is org which belongs to business, ensure business limit is at least as high as org limit
              if req.image_versions_per_image_limit.value > bus.custom_image_versions_per_image_limit
                bus.set_custom_image_versions_per_image_limit(limit: req.image_versions_per_image_limit.value, actor: User.ghost)
              end
            end
            entity.set_custom_image_versions_per_image_limit(limit: req.image_versions_per_image_limit.value, actor: User.ghost)
          end

          # image_version_unused_age_limit
          if req.image_version_unused_age_limit.present? && req.image_version_unused_age_limit.value.present?
            if bus.present?
              # if entity is org which belongs to business, ensure business limit is at least as high as org limit
              if req.image_version_unused_age_limit.value > bus.custom_image_version_unused_age_limit
                bus.set_custom_image_version_unused_age_limit(limit: req.image_version_unused_age_limit.value, actor: User.ghost)
              end
            end
            entity.set_custom_image_version_unused_age_limit(limit: req.image_version_unused_age_limit.value, actor: User.ghost)
          end

          # image_version_max_age_limit
          if req.image_version_max_age_limit.present? && req.image_version_max_age_limit.value.present?
            if bus.present?
              # if entity is org which belongs to business, ensure business limit is at least as high as org limit
              if req.image_version_max_age_limit.value > bus.custom_image_version_max_age_limit
                bus.set_custom_image_version_max_age_limit(limit: req.image_version_max_age_limit.value, actor: User.ghost)
              end
            end
            entity.set_custom_image_version_max_age_limit(limit: req.image_version_max_age_limit.value, actor: User.ghost)
          end
        end

        {}
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
