# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetAccountDetails
        def self.call(request)
          new(request).call
        end

        def initialize(request)
          @entity_id = request.entity_id.global_id
        end

        def call
          return Twirp::Error.not_found("entity does not exist", argument: "entity_id") unless entity

          {
            account_type: entity_account_type,
            is_billing_owner: is_billing_owner?,
            customer_id: customer_id,
            trust_tier: trust_tier
          }
        end

        private

        def entity
          @entity ||= begin
            decoded_id = Platform::Helpers::NodeIdentification.from_global_id(@entity_id)
            case decoded_id.first
            when "Enterprise"
              return Business.find_by(id: decoded_id.last)
            when "Organization"
              return Organization.find_by(id: decoded_id.last)
            when "Repository"
              return Repository.find_by(id: decoded_id.last)
            else
              return nil
            end
          end
        end

        def entity_account_type
          if entity.is_a?(Business)
            "Business"
          elsif entity.is_a?(Organization)
            "Organization"
          elsif entity.is_a?(Repository)
            "Repository"
          else
            nil
          end
        end

        def is_billing_owner?
          if entity.is_a?(Business)
            # Business is always the billing owner
            true
          elsif entity.is_a?(Organization)
            # Organization is the billing owner if it doesn't have a business
            entity.business.nil?
          else
            false
          end
        end

        def trust_tier
          if entity.is_a?(Repository)
            TrustTiers::Tier.for_repository(entity).tier
          else
            TrustTiers::Tier.for_billable_owner(entity).tier
          end
        end

        def customer_id
          if entity.is_a?(Repository)
            if entity.owner&.delegate_billing_to_business?
              entity.owner.business.customer_id
            else
              entity.owner&.customer&.id
            end
          else
            if entity.delegate_billing_to_business?
              entity.business.customer_id
            else
              entity.customer&.id
            end
          end
        end
      end
    end
  end
end
