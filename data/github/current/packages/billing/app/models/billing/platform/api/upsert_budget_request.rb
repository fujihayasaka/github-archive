# typed: true
# frozen_string_literal: true

module Billing
  module Platform
    module Api
      class UpsertBudgetRequest
        class Error < StandardError; end
        class InvalidTargetError < Error; end
        class InvalidAccessError < Error; end
        class InvalidRequestError < Error; end

        include Billing::Platform::Api::Utils

        # Schema
        # {
        #   targetAmount: number
        #   targetType: string
        #   targetId: string
        #   pricingTargetType: string
        #   pricingTargetId: string
        #   alertEnabled: boolean
        #   alertRecipientUserIds: string[]
        # }

        delegate :[], to: :raw_upsert_budget_request

        def initialize(raw_upsert_budget_request:, current_user:, this_entity:, customer_id:)
          @raw_upsert_budget_request = raw_upsert_budget_request.with_indifferent_access
          @current_user = current_user
          @this_entity = this_entity
          @customer_id = customer_id

          validate_params
          validate_target
          validate_ownership
        end

        def target_amount
          raw_upsert_budget_request[:targetAmount]
        end

        def target_type
          raw_upsert_budget_request[:targetType]
        end

        def license_count
          raw_upsert_budget_request[:licenseCount]
        end

        # Both targetId and recipientUserIds come to us from React as global IDs that need to be converted to
        # their database ID
        def target_id
          case target_type
          when CUSTOMER_TARGET, ENTERPRISE_TARGET, MULTIUSERCUSTOMER_TARGET # remove enterprise when we remove enterprise budgets
            @customer_id
          when ORGANIZATION_TARGET, REPOSITORY_TARGET
            # The new API endpoint passes numeric IDs; the existing customers UI passes global relay IDs.
            # Accept both formats.
            raw_id = raw_upsert_budget_request[:targetId].to_s
            return raw_id if raw_id.match?(/\A\d+\z/)

            ::Platform::Helpers::GlobalId.parse(raw_id).id.to_s
          when COSTCENTER_TARGET, USER_TARGET
            raw_upsert_budget_request[:targetId]
          else
            ::Platform::Helpers::GlobalId.parse(raw_upsert_budget_request[:targetId]).id
          end
        end

        def alert_recipient_user_ids
          raw_upsert_budget_request[:alertRecipientUserIds].map { |i| ::Platform::Helpers::GlobalId.parse(i).id }.map(&:to_s)
        end

        def pricing_target_type
          raw_upsert_budget_request[:pricingTargetType]
        end

        def pricing_target_id
          raw_upsert_budget_request[:pricingTargetId]
        end

        def alert_enabled?
          raw_upsert_budget_request[:alertEnabled]
        end

        def budget_limit_type
          raw_upsert_budget_request[:budgetLimitType].to_s
        end

        def uuid
          raw_upsert_budget_request[:uuid].to_s
        end

        def exclude_cost_center_usage
          raw_upsert_budget_request[:excludeCostCenterUsage]
        end

        def json_key
          {
            targetType: target_type,
            pricingTargetType: pricing_target_type,
            targetId: target_id.to_s,
            pricingTargetId: pricing_target_id,
            customerId: customer_id,
          }
        end

        def to_json
          result = {
            targetAmount: target_amount,
            licenseCount: license_count,
            key: json_key,
            budgetLimitType: budget_limit_type,
            budgetAlerting: {
              willAlert: alert_enabled?,
              recipientUserIds: alert_recipient_user_ids
            },
            uuid: uuid,
          }
          result[:excludeCostCenterUsage] = exclude_cost_center_usage || false
          result
        end

        private

        attr_reader :raw_upsert_budget_request, :current_user, :customer_id, :this_entity

        def validate_params
          fields = %i[targetId targetType pricingTargetType pricingTargetId alertEnabled alertRecipientUserIds]
          if fields.any? { |f| @raw_upsert_budget_request[f].nil? }
            raise InvalidRequestError
          end

          if @raw_upsert_budget_request[:targetAmount].nil? && @raw_upsert_budget_request[:licenseCount].nil?
            raise InvalidRequestError
          end

          target_amount_value = @raw_upsert_budget_request[:targetAmount]

          if target_amount_value
            # Convert to numeric value, handling both string and numeric inputs
            begin
              numeric_amount = target_amount_value.is_a?(String) ? Float(target_amount_value) : target_amount_value.to_f
              if numeric_amount < 0 || numeric_amount > 20000000
                raise InvalidRequestError, "Target amount must be between 0 and 20,000,000"
              end
            rescue ArgumentError
              raise InvalidRequestError, "Target amount must be a valid number"
            end
          end

          if pricing_target_id.blank?
            raise InvalidRequestError, "Pricing target ID must be provided"
          end

          if alert_enabled? && alert_recipient_user_ids.empty?
            raise InvalidRequestError, "If budget alerting is enabled, alert recipient list must be provided"
          end
        end

        def validate_target
          target = get_target_entity_from_id(target_type: target_type, target_id: target_id, this_entity: this_entity)

          raise InvalidTargetError if target.nil?
        end

        def validate_ownership
          raise InvalidAccessError if !targets_owned_by_user?(
            target_type: target_type,
            target_ids: [target_id],
            current_user: current_user,
            this_entity: this_entity
          )
        end
      end
    end
  end
end
