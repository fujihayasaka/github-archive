# typed: true
# frozen_string_literal: true

require "actions-broker"

class Api::Internal::Twirp
  module ActionsBrokerService
    module BillingOwner
      module V1
        class BillingOwnerApiHandler < Api::Internal::Twirp::Handler
          allow_access_for :client, allowed_clients: %w[actions_broker_listener actions_runner_admin].freeze
          handles_service GitHub::ActionsBrokerService::BillingOwner::V1::BillingOwnerAPIService

          def get_billing_owner(req, _env)
            return Twirp::Error.invalid_argument("must be non-empty", argument: "entity_id") if req.entity_id.empty?

            begin
              decoded_id = Platform::Helpers::NodeIdentification.from_global_id(req.entity_id)
            rescue Platform::Errors::NotFound
              return Twirp::Error.not_found("unresolvable entity id", argument: "entity_id")
            end

            case decoded_id.first
            when "Enterprise"
              business = Business.find_by(id: decoded_id.last)
              return Twirp::Error.not_found("enterprise not found", argument: "entity_id") unless business.present?
              billing_owner_id = get_global_id(business)
            when "Organization"
              org = Organization.find_by(id: decoded_id.last)
              return Twirp::Error.not_found("organization not found", argument: "entity_id") unless org.present?
              if org.business.nil?
                billing_owner_id = get_global_id(org)
              else
                billing_owner_id = get_global_id(org.business)
              end
            when "Repository"
              repo = Repository.find_by(id: decoded_id.last)
              return Twirp::Error.not_found("repository not found", argument: "entity_id") unless repo.present?
              if repo.owner.nil?
                return Twirp::Error.not_found("repository owner not found", argument: "entity_id")
              elsif repo.owner&.business.nil?
                billing_owner_id = get_global_id(repo.owner)
              else
                billing_owner_id = get_global_id(repo.owner&.business)
              end
            else
              return Twirp::Error.invalid_argument("must be a valid repo, org, or enterprise", argument: "entity_id")
            end

            {
              billing_owner_id: billing_owner_id
            }
          end

          def get_global_id(entity)
            !GitHub.enterprise? ? entity.next_global_id : entity.global_relay_id
          end

        end
      end
    end
  end
end
