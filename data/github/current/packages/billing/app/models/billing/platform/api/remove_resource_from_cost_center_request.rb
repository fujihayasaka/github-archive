# typed: true
# frozen_string_literal: true

module Billing
  module Platform
    module Api
      class RemoveResourceFromCostCenterRequest
        class Error < StandardError; end
        class InvalidTargetError < Error; end
        class InvalidAccessError < Error; end
        class InvalidRequestError < Error; end

        include Billing::Platform::Api::Utils
        include GitHub::Memoizer

        # Schema
        # {
        #   name: string
        #   costCenterKey: {
        #     customerId: string
        #     targetId: string
        #     targetType: string
        #     uuid: string
        #   }
        #   resources: { id: string, type: string }[]
        # }

        def initialize(key:, resources:, user:, business:)
          @cost_center_key = key
          @raw_resources = resources
          @user = user
          @business = business
          @customer_id = business.customer_id.to_s

          validate_resources
          validate_ownership
        end

        # resource.id comes to us from React as global IDs that need to be converted to
        # their database ID
        memoize def resources
          resources = raw_resources.map(&:clone)
          resources.map do |r|
            r[:id] = ::Platform::Helpers::GlobalId.parse(r[:id]).id.to_s
            r.symbolize_keys
          end
        end

        def json_key
          {
            customerId: customer_id,
            targetType: cost_center_key[:targetType],
            targetId: cost_center_key[:targetId].to_s,
            uuid: cost_center_key[:uuid]
          }
        end

        def to_json
          {
            costCenterKey: json_key,
            resources: resources
          }
        end

        private

        attr_reader :user, :customer_id, :business, :cost_center_key, :raw_resources

        def validate_resources
          if resources.any? { |r| get_target_entity_from_id(target_type: r[:type], target_id: r[:id]).nil? }
            raise InvalidTargetError
          end
        end

        def validate_ownership
          resources.group_by { |r| r[:type] }.any? do |type, entries|
            raise InvalidAccessError unless targets_owned_by_user?(
              target_type: type,
              target_ids: entries.map { |e| e[:id] },
              current_user: user,
              this_entity: business
            )
          end
        end
      end
    end
  end
end
