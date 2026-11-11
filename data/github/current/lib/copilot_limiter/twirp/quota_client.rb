# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilot-limiter"
require "monolith-twirp-copilot-users"

module CopilotLimiter
  module Twirp
    class QuotaClient < CopilotLimiter::Twirp::BaseClient
      include GitHub::Memoizer

      INTERVAL_QUOTA_TYPES = [:immediate_usage_interval, :extended_usage_interval].freeze

      FreeUserQuota = T.type_alias do
        {
          chat: Integer,
          completions: Integer,
        }
      end

      UserQuotaRemaining = T.type_alias do
        {
          entitlement: Integer,
          remaining: Integer,
          quota_remaining: Float,
          unlimited: T::Boolean,
          overage_count: T.nilable(Integer),
          overage_permitted: T.nilable(T::Boolean),
          overage_entitlement: T.nilable(Integer),
          percent_remaining: T.nilable(Float),
          has_quota: T.nilable(T::Boolean),
          quota_reset_at: T.nilable(Integer),
        }
      end

      GetConsumptiveUserResponse = T.type_alias do
        {
          access_type: Symbol,
          business_id: T.nilable(Integer),
          copilot_access_type: T.nilable(String),
          customer_ids: T::Array[Integer],
          id: Integer,
          organization_id: T.nilable(Integer),
          reset_date: T.nilable(MonolithTwirp::Copilot::Limiter::V1::ResetDate),
          copilot_for_business_free: T::Boolean,
          is_staff: T::Boolean,
          use_token_based_billing: T.nilable(T::Boolean),
          cu_cached_at: T.nilable(Integer),
          can_proceed_with_usage: T.nilable(T::Boolean),
          cpwu_cached_at: T.nilable(Integer),
          applicable_budgets: T.nilable(String),
          billable_owner_trust_tier: T.nilable(Symbol),
          cpwu_status: T.nilable(Symbol),
          user_level_budget: T.nilable(MonolithTwirp::Copilot::Limiter::V1::UserLevelBudget),
        }
      end

      ValidateOrgEventEligibilityResponse = T.type_alias do
        {
          is_eligible: T::Boolean,
          denial_reason: T.nilable(String),
        }
      end

      GetCachedOrganizationResponse = T.type_alias do
        {
          id: T.nilable(Integer),
          tracking_id: T.nilable(String),
          customer_id: T.nilable(Integer),
          can_proceed: T.nilable(T::Boolean),
          can_proceed_message: T.nilable(String),
          can_proceed_denial_reason:  T.nilable(MonolithTwirp::Copilot::Limiter::V1::DenialReason),
        }
      end

      class GetQuotaRemainingResponse
        def initialize(token_based_billing:, quota_details:)
          @token_based_billing = token_based_billing
          @quota_details = quota_details
        end

        sig { returns(T::Boolean) }
        def token_based_billing?
          @token_based_billing
        end

        sig { returns(T::Hash[Symbol, UserQuotaRemaining]) }
        def quota_details
          @quota_details
        end
      end

      # This method will call the Limiter service to reset the quota for a given user.
      sig do
        params(
          copilot_tracking_id: String,
          quota_reset_date: MonolithTwirp::Copilot::Limiter::V1::ResetDate,
        ).returns(T::Boolean)
      end
      def cleanup_free_user_quota(copilot_tracking_id:, quota_reset_date:)
        GitHub.logger.with_named_tags({
          "code.function": "cleanup_free_user_quota",
          "code.namespace": "CopilotLimiter::Twirp::QuotaClient",
          "gh.user.analytics_tracking_id": copilot_tracking_id,
          "gh.quota_reset_date.year": quota_reset_date.year,
          "gh.quota_reset_date.month": quota_reset_date.month,
          "gh.quota_reset_date.day": quota_reset_date.day,
        }) do
          GitHub.logger.info("Cleaning up free user quota")

          if emergency_stop_enabled?
            return false
          end

          if copilot_tracking_id.blank?
            GitHub.logger.info("Copilot tracking ID is blank, returning false")
            GitHub.dogstats.increment("copilot_limiter.quota_client.error", tags: { method: "cleanup_free_user_quota", error: "blank_copilot_tracking_id" })
            return false
          end

          # Call the Limiter service to cleanup the free user quota
          response = rpc(
            :CleanupQuota,
            copilot_tracking_id: copilot_tracking_id,
            quota_reset_date: quota_reset_date,
            copilot_access_type: ::MonolithTwirp::Copilot::Users::V1::AccessType::ACCESS_TYPE_FREE_LIMITED_COPILOT,
          )
          GitHub.logger.info(
            "Finished Twirp Call",
            "gh.copilot_limiter.response.status": response&.status,
            "gh.copilot_limiter.response.call_succeeded": response&.call_succeeded,
          )

          if response.call_succeeded? && response.value.success
            GitHub.dogstats.increment("copilot_limiter.quota_client.success", tags: { method: "cleanup_free_user_quota" })
            return true
          else
            GitHub.dogstats.increment("copilot_limiter.quota_client.failure", tags: { method: "cleanup_free_user_quota", status: response.status })
            GitHub.logger.info("Failed to cleanup free user quota")
            return false
          end
        end
      end

      # This method will call the Limiter service to get the quota for a given user.
      # It will return a response with the following fields:
      #   - chat_quota: The quota for chat interactions that this user has USED.
      #   - completions_quota: The quota for completions that this user has USED
      sig do
        params(
          copilot_tracking_id: String,
        ).returns(FreeUserQuota)
      end
      def get_free_user_quota(copilot_tracking_id:)
        GitHub.logger.with_named_tags({
          "code.function": "get_free_user_quota",
          "code.namespace": "CopilotLimiter::Twirp::QuotaClient",
          "gh.user.analytics_tracking_id": copilot_tracking_id,
        }) do
          GitHub.logger.info("Getting free user quota")

          if emergency_stop_enabled?
            GitHub.dogstats.increment("copilot_limiter.quota_client.notice", tags: { method: "get_free_user_quota", reason: "emergency_stop_enabled" })
            return {
              chat: 0,
              completions: 0,
            }
          end

          if copilot_tracking_id.blank?
            GitHub.dogstats.increment("copilot_limiter.quota_client.error", tags: { method: "get_free_user_quota", error: "blank_copilot_tracking_id" })
            GitHub.logger.info("Copilot tracking ID is blank, returning empty values")
            return {
              chat: 0,
              completions: 0,
            }
          end

          # Call the Limiter service to get the free user quota
          response = rpc(
            :GetFreeUserQuota,
            copilot_tracking_id: copilot_tracking_id,
          )
          GitHub.logger.info(
            "Finished Twirp Call",
            "gh.copilot_limiter.response.status": response&.status,
            "gh.copilot_limiter.response.call_succeeded": response&.call_succeeded,
          )
          # If the call succeeded, we will get back a MonolithTwirp::Copilot::Limiter::V1::GetFreeUserQuotaResponse
          # With fields: chat_quota: 50, completions_quota: 2000, so we return those values
          if response&.call_succeeded?
            GitHub.dogstats.increment("copilot_limiter.quota_client.success", tags: { method: "get_free_user_quota" })
            # return the values
            chat_quota = response.value.chat_quota
            completions_quota = response.value.completions_quota

            GitHub.logger.info(
              "Received twirp response",
              "gh.copilot_limiter.response.chat_quota": chat_quota,
              "gh.copilot_limiter.response.completions_quota": completions_quota,
            )

            # return the values
            {
              chat: chat_quota,
              completions: completions_quota,
            }
          else
            GitHub.dogstats.increment("copilot_limiter.quota_client.failure", tags: { method: "get_free_user_quota", status: response.status })
            # If the call failed, we need to return no usage
            {
              chat: 0,
              completions: 0,
            }
          end
        end
      end

      # This method will call the Limiter service to get the REMAINING quota for a given user.
      # If this fails, we will "fail open" meaning that we will return unlimited.
      sig do
        params(
          copilot_tracking_id: String,
          twirp_access_type: Integer,
          interaction_id: T.nilable(String),
        ).returns(GetQuotaRemainingResponse)
      end
      def get_quota_remaining(copilot_tracking_id:, twirp_access_type:, interaction_id: nil)
        GitHub.logger.with_named_tags({
          "code.function": "get_quota_remaining",
          "code.namespace": "CopilotLimiter::Twirp::QuotaClient",
          "gh.user.analytics_tracking_id": copilot_tracking_id,
          "gh.user.twirp_access_type": twirp_access_type,
        }) do
          GitHub.logger.info("Getting quota remaining")

          if emergency_stop_enabled?
            GitHub.dogstats.increment("copilot_limiter.quota_client.notice", tags: { method: "get_quota_remaining", reason: "emergency_stop_enabled" })
            return unlimited_response # fail open
          end

          if copilot_tracking_id.blank?
            GitHub.dogstats.increment("copilot_limiter.quota_client.error", tags: { method: "get_quota_remaining", error: "blank_copilot_tracking_id" })
            GitHub.logger.info("Copilot tracking ID is blank, returning empty values")

            return empty_response
          end

          if twirp_access_type < 1
            GitHub.dogstats.increment("copilot_limiter.quota_client.error", tags: { method: "get_quota_remaining", error: "invalid_sku", sku: twirp_access_type })
            GitHub.logger.info("Copilot access type is invalid, returning empty values", "gh.copilot_limiter.twirp_access_type": twirp_access_type)

            return empty_response
          end

          # The limiter is only including sections for usage_interval features in the twirp response
          # for accounts that have intervals enabled so there's no need for extra filtering here.
          #
          # interaction_id is optional. When provided, that value is sent to limiter.
          # If it is not provided, the interaction_id field is omitted from the request payload.
          #
          # Call the Limiter service to get the free user quota
          request_payload = {
            copilot_tracking_id: copilot_tracking_id,
            copilot_access_type: twirp_access_type,
          }
          request_payload[:interaction_id] = interaction_id if interaction_id.present?

          response = rpc(
            :GetQuotaRemaining,
            **request_payload,
          )
          GitHub.logger.info(
            "Finished Twirp Call",
            "gh.copilot_limiter.response.status": response&.status,
            "gh.copilot_limiter.response.call_succeeded": response&.call_succeeded,
          )
          # If the call succeeded, we will get back a MonolithTwirp::Copilot::Limiter::V1::GetFreeUserQuotaResponse
          # With fields: chat_quota: 50, completions_quota: 2000, so we return those values
          if response&.call_succeeded?
            GitHub.logger.info(
              "Successfully got quota remaining",
              "gh.copilot_limiter.response.quota_details": response.value.quota_details,
            )

            # If the call succeeded, we will get back a MonolithTwirp::Copilot::Limiter::V1::GetQuotaRemainingResponse
            GitHub.dogstats.increment("copilot_limiter.quota_client.success", tags: { method: "get_quota_remaining" })

            token_based_billing = response.value.token_based_billing
            quota_detail = response.value.quota_details.inject({}) do |acc, quota_detail|
              # Get the quota type and convert it to a symbol
              next acc if quota_detail.quota_type == MonolithTwirp::Copilot::Limiter::V1::QuotaType::QUOTA_TYPE_INVALID

              converted = load_quota_type(quota_detail.quota_type)

              # Add the quota detail to the hash
              acc[converted] = {
                overage_count: quota_detail.overage_count,
                overage_permitted: quota_detail.overage_permitted,
                overage_entitlement: quota_detail.overage_entitlement,
                percent_remaining: quota_detail.percent_remaining,
                quota_remaining: quota_detail.quota_remaining,
                unlimited: quota_detail.unlimited,
                has_quota: quota_detail.has_quota,
                quota_reset_at: quota_detail.quota_reset_at,
              }

              # Interval features don't need the optional entitlement/remaining fields
              if !converted.in?(INTERVAL_QUOTA_TYPES)
                acc[converted][:entitlement] = quota_detail.entitlement
                acc[converted][:remaining] = quota_detail.remaining
              end

              acc
            end
            GetQuotaRemainingResponse.new(
              token_based_billing: token_based_billing,
              quota_details: quota_detail,
            )
          else
            GitHub.dogstats.increment("copilot_limiter.quota_client.failure", tags: { method: "get_quota_remaining", status: response.status })
            GitHub.logger.info("Failed to get quota remaining, returning unlimited response")
            unlimited_response
          end
        end
      end

      # This method calls the limiter and gets the consumptive user stuff
      sig do
        params(
          copilot_tracking_id: String,
        ).returns(T.any(GetConsumptiveUserResponse, {}))
      end
      def get_consumptive_user(copilot_tracking_id:)
        GitHub.logger.with_named_tags({
          "code.function": "get_consumptive_user",
          "code.namespace": "CopilotLimiter::Twirp::QuotaClient",
          "gh.user.analytics_tracking_id": copilot_tracking_id,
        }) do
          GitHub.logger.info("Getting consumptive user")

          # Call the Limiter service to get the consumptive user
          response = rpc(:GetConsumptiveUser, copilot_tracking_id: copilot_tracking_id)

          GitHub.logger.info(
            "Finished Twirp Call",
            "gh.copilot_limiter.response.status": response&.status,
            "gh.copilot_limiter.response.call_succeeded": response&.call_succeeded,
          )

          if response&.call_succeeded?
            GitHub.dogstats.increment("copilot_limiter.quota_client.success", tags: { method: "get_consumptive_user" })

            # return the values
            payload = {
              access_type: response.value.access_type,
              business_id: response.value.business_id,
              copilot_access_type: response.value.copilot_access_type,
              customer_ids: response.value.customer_ids.to_a,
              id: response.value.id,
              organization_id: response.value.organization_id,
              reset_date: response.value.reset_date,
              copilot_for_business_free: response.value.copilot_for_business_free,
              is_staff: response.value.is_staff,
              use_token_based_billing: response.value.use_token_based_billing,
              cu_cached_at: response.value.cu_cached_at,
              can_proceed_with_usage: nil,
              cpwu_cached_at: nil,
              applicable_budgets: nil,
              billable_owner_trust_tier: nil,
              cpwu_status: nil,
              user_level_budget: nil,
            }

            payload[:can_proceed_with_usage] = response.value.can_proceed_with_usage if response.value.cpwu_cached_at.positive?
            payload[:cpwu_cached_at] = response.value.cpwu_cached_at if response.value.cpwu_cached_at.positive?
            payload[:applicable_budgets] = response.value.applicable_budgets if response.value.applicable_budgets.present?
            payload[:billable_owner_trust_tier] = response.value.billable_owner_trust_tier if response.value.billable_owner_trust_tier != :TRUST_TIER_INVALID
            payload[:cpwu_status] = response.value.cpwu_status if response.value.cpwu_status.present? && response.value.cpwu_status != :CAN_PROCEED_WITH_USAGE_STATUS_INVALID
            payload[:user_level_budget] = response.value.user_level_budget if response.value.user_level_budget.present?

            payload
          else
            GitHub.dogstats.increment("copilot_limiter.quota_client.failure", tags: { method: "get_consumptive_user", status: response.status })
            GitHub.logger.info("Failed to get consumptive user")
            {}
          end
        end
      end

      # This method calls the limiter and gets the consumptive user stuff
      sig do
        params(
          copilot_tracking_id: String,
        ).returns(T::Boolean)
      end
      def delete_consumptive_user(copilot_tracking_id:)
        GitHub.logger.with_named_tags({
          "code.function": "delete_consumptive_user",
          "code.namespace": "CopilotLimiter::Twirp::QuotaClient",
          "gh.user.analytics_tracking_id": copilot_tracking_id,
        }) do
          GitHub.logger.info("Deleting consumptive user")

          if emergency_stop_enabled?
            return false # can't do anything now
          end

          if copilot_tracking_id.blank?
            GitHub.dogstats.increment("copilot_limiter.set_quota.copilot_tracking_id.blank")
            GitHub.logger.info("Copilot tracking ID is blank, returning false")
            return false
          end

          # Call the Limiter service to get the consumptive user
          response = rpc(:DeleteConsumptiveUser, copilot_tracking_id: copilot_tracking_id)

          GitHub.logger.info(
            "Finished Twirp Call",
            "gh.copilot_limiter.response.status": response&.status,
            "gh.copilot_limiter.response.call_succeeded": response&.call_succeeded,
          )

          if response&.call_succeeded? && response.value.success
            GitHub.dogstats.increment("copilot_limiter.quota_client.success", tags: { method: "delete_consumptive_user" })

            return true
          else
            GitHub.dogstats.increment("copilot_limiter.quota_client.failure", tags: { method: "delete_consumptive_user", status: response.status })
            GitHub.logger.info("Failed to delete consumptive user")
            return false
          end
        end
      end

      # NOTE: rpc method HasQuota is not implemented in this client as it is intended for CAPI use

      # This method will call the Limiter service to set the quota for a given fre user.
      sig do
        params(
          copilot_tracking_id: String,
          feature: String,
          quota: Integer,
          twirp_access_type: Integer,
        ).returns(T::Boolean)
      end
      def set_free_user_quota(copilot_tracking_id:, feature:, quota:, twirp_access_type:)
        GitHub.logger.with_named_tags({
          "code.function": "set_free_user_quota",
          "code.namespace": "CopilotLimiter::Twirp::QuotaClient",
          "gh.user.analytics_tracking_id": copilot_tracking_id,
          "gh.copilot_limiter.feature": feature,
          "gh.copilot_limiter.quota": quota,
          "gh.copilot_limiter.twirp_access_type": twirp_access_type,
        }) do
          GitHub.logger.info("Setting free user quota")

          if emergency_stop_enabled?
            return false # can't do anything now
          end

          if copilot_tracking_id.blank?
            GitHub.dogstats.increment("copilot_limiter.quota_client.error", tags: { method: "set_free_user_quota", error: "blank_copilot_tracking_id" })
            GitHub.logger.info("Copilot tracking ID is blank, returning false")
            return false
          end

          if twirp_access_type < 1
            GitHub.dogstats.increment("copilot_limiter.quota_client.error", tags: { method: "set_free_user_quota", error: "invalid_sku", sku: twirp_access_type })
            GitHub.logger.info("Copilot access type is invalid, returning false", "gh.copilot_limiter.twirp_access_type": twirp_access_type)
            return false
          end

          # Call the Limiter service to set the quota for a given user
          # NOTE: The model and interaction_type are not used in this case, so we can pass empty strings
          # to the rpc method
          response = rpc(
            :SetQuota,
            copilot_tracking_id: copilot_tracking_id,
            feature: feature,
            model: "",
            interaction_type: "",
            quota: quota,
            copilot_access_type: twirp_access_type,
            quota_value: quota.to_f,
          )
          GitHub.logger.info(
            "Finished Twirp Call",
            "gh.copilot_limiter.response.status": response&.status,
            "gh.copilot_limiter.response.call_succeeded": response&.call_succeeded,
          )

          if response.call_succeeded? && response.value.success
            GitHub.dogstats.increment("copilot_limiter.quota_client.success", tags: { method: "set_free_user_quota" })
            return true
          else
            GitHub.dogstats.increment("copilot_limiter.quota_client.failure", tags: { method: "set_free_user_quota", status: response.status })
            GitHub.logger.info("Failed to set free user quota")
            return false
          end
        end
      end

      # This method will call the Limiter service to set the quota for a given user.
      sig do
        params(
          copilot_tracking_id: String,
          feature: String,
          quota: Float,
          twirp_access_type: Integer,
        ).returns(T::Boolean)
      end
      def set_quota(copilot_tracking_id:, feature:, quota:, twirp_access_type:)
        GitHub.logger.with_named_tags({
          "code.function": "set_quota",
          "code.namespace": "CopilotLimiter::Twirp::QuotaClient",
          "gh.user.analytics_tracking_id": copilot_tracking_id,
          "gh.copilot_limiter.feature": feature,
          "gh.copilot_limiter.quota": quota,
          "gh.copilot_limiter.twirp_access_type": twirp_access_type,
        }) do
          GitHub.logger.info("Setting quota")

          if emergency_stop_enabled?
            return false # can't do anything now
          end

          if copilot_tracking_id.blank?
            GitHub.dogstats.increment("copilot_limiter.set_quota.copilot_tracking_id.blank")
            GitHub.logger.info("Copilot tracking ID is blank, returning false")
            return false
          end

          if twirp_access_type < 1
            GitHub.dogstats.increment("copilot_limiter.quota_client.error", tags: { method: "set_quota", error: "invalid_sku", sku: twirp_access_type })
            GitHub.logger.info("Copilot access type is invalid, returning false", "gh.copilot_limiter.twirp_access_type": twirp_access_type)
            return false
          end

          # Call the Limiter service to set the quota for a given user
          response = rpc(
            :SetQuota,
            copilot_tracking_id: copilot_tracking_id,
            feature: feature,
            quota: quota.to_i,
            copilot_access_type: twirp_access_type,
            quota_value: quota,
          )
          GitHub.logger.info(
            "Finished Twirp Call",
            "gh.copilot_limiter.response.status": response&.status,
            "gh.copilot_limiter.response.call_succeeded": response&.call_succeeded,
          )

          if response.call_succeeded? && response.value.success
            GitHub.dogstats.increment("copilot_limiter.quota_client.success", tags: { method: "set_quota" })
            return true
          else
            GitHub.dogstats.increment("copilot_limiter.quota_client.failure", tags: { method: "set_quota", status: response.status })
            GitHub.logger.info("Failed to set quota")
            return false
          end
        end
      end

      # This method will call the Limiter service to reset usage interval counters (immediate + extended).
      sig do
        params(
          copilot_tracking_id: String,
          twirp_access_type: Integer,
        ).returns(T::Boolean)
      end
      def reset_usage_intervals(copilot_tracking_id:, twirp_access_type:)
        GitHub.logger.with_named_tags({
          "code.function": "reset_usage_intervals",
          "code.namespace": "CopilotLimiter::Twirp::QuotaClient",
          "gh.user.analytics_tracking_id": copilot_tracking_id,
          "gh.copilot_limiter.twirp_access_type": twirp_access_type,
        }) do
          GitHub.logger.info("Resetting usage intervals")

          if emergency_stop_enabled?
            return false
          end

          if copilot_tracking_id.blank?
            GitHub.dogstats.increment("copilot_limiter.reset_usage_intervals.copilot_tracking_id.blank")
            GitHub.logger.info("Copilot tracking ID is blank, returning false")
            return false
          end

          if twirp_access_type < 1
            GitHub.dogstats.increment("copilot_limiter.quota_client.error", tags: { method: "reset_usage_intervals", error: "invalid_access_type", sku: twirp_access_type })
            GitHub.logger.info("Copilot access type is invalid, returning false", "gh.copilot_limiter.twirp_access_type": twirp_access_type)
            return false
          end

          response = rpc(
            :ResetUsageIntervals,
            copilot_tracking_id: copilot_tracking_id,
            copilot_access_type: twirp_access_type,
          )
          GitHub.logger.info(
            "Finished Twirp Call",
            "gh.copilot_limiter.response.status": response&.status,
            "gh.copilot_limiter.response.call_succeeded": response&.call_succeeded,
          )

          if response.call_succeeded? && response.value.success
            GitHub.dogstats.increment("copilot_limiter.quota_client.success", tags: { method: "reset_usage_intervals" })
            return true
          else
            GitHub.dogstats.increment("copilot_limiter.quota_client.failure", tags: { method: "reset_usage_intervals", status: response.status })
            GitHub.logger.info("Failed to reset usage intervals")
            return false
          end
        end
      end

      # This method calls the limiter to get eligibility for direct org billing
      sig do
        params(
          copilot_tracking_id: String,
        ).returns(ValidateOrgEventEligibilityResponse)
      end
      def validate_org_event_eligibility(copilot_tracking_id:)
        GitHub.logger.with_named_tags({
          "code.function": "validate_org_event_eligibility",
          "code.namespace": "CopilotLimiter::Twirp::QuotaClient",
          "gh.user.analytics_tracking_id": copilot_tracking_id,
        }) do
          GitHub.logger.info("Validating org event eligibility")

          if emergency_stop_enabled?
            return {
              is_eligible: false,
              denial_reason: "emergency stop enabled",
             }
          end

          if copilot_tracking_id.blank?
            GitHub.dogstats.increment("copilot_limiter.validate_org_event_eligibility.copilot_tracking_id.blank")
            GitHub.logger.info("Copilot tracking ID is blank, returning false")
            return {
              is_eligible: false,
              denial_reason: "copilot tracking id blank",
             }
          end

          # Call the Limiter service to validate org event eligibility
          response = rpc(:ValidateOrgEventEligibility, copilot_tracking_id: copilot_tracking_id)

          GitHub.logger.info(
            "Finished Twirp Call",
            "gh.copilot_limiter.response.status": response&.status,
            "gh.copilot_limiter.response.call_succeeded": response&.call_succeeded,
          )

          if response&.call_succeeded?
            GitHub.dogstats.increment("copilot_limiter.quota_client.success", tags: { method: "validate_org_event_eligibility" })

            return {
              is_eligible: response.value.is_eligible,
              denial_reason: response.value.denial_reason,
            }
          else
            GitHub.dogstats.increment("copilot_limiter.quota_client.failure", tags: { method: "validate_org_event_eligibility", status: response&.status })
            GitHub.logger.info("Failed to validate org event eligibility")
            return {
              is_eligible: true,
              denial_reason: "",
            }
          end
        end
      end

      sig do
        params(
          org_tracking_id: String,
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def get_cached_organization(org_tracking_id:)
        response = rpc(:GetCachedOrganization, org_tracking_id: org_tracking_id)

        if response&.call_succeeded?
          GitHub.dogstats.increment("copilot_limiter.quota_client.success", tags: { method: "get_cached_organization" })

          {
            id: response.value.id,
            tracking_id: response.value.tracking_id,
            customer_id: response.value.customer_id,
            can_proceed: response.value.can_proceed,
            can_proceed_message: response.value.can_proceed_message,
            can_proceed_denial_reason: response.value.can_proceed_denial_reason,
          }
        else
          GitHub.dogstats.increment("copilot_limiter.quota_client.failure", tags: { method: "get_cached_organization", status: response.status })
          {}
        end
      end

      private

      memoize def emergency_stop_enabled?
        if FeatureFlag.vexi.enabled?(:copilot_limiter_emergency_stop, default: false)
          GitHub.logger.info("Copilot limiter emergency stop enabled")
          return true
        end
        false
      end

      def twirp_class
        ::MonolithTwirp::Copilot::Limiter::V1::CopilotLimiterAPIClient
      end

      sig { params(quota_type: T.any(Integer, Symbol)).returns(Symbol) }
      def load_quota_type(quota_type)
        case quota_type
        when :QUOTA_TYPE_CHAT
          :chat
        when :QUOTA_TYPE_COMPLETIONS
          :completions
        when :QUOTA_TYPE_PREMIUM_INTERACTIONS
          :premium_interactions
        when :QUOTA_TYPE_IMMEDIATE_USAGE_INTERVAL
          :immediate_usage_interval
        when :QUOTA_TYPE_EXTENDED_USAGE_INTERVAL
          :extended_usage_interval
        else
          GitHub.dogstats.increment("copilot_limiter.quota_client.failure", tags: { method: "load_quota_type", quota_type: quota_type.to_s })
          :unknown
        end
      end

      def empty_response
        GetQuotaRemainingResponse.new(
          token_based_billing: false,
          quota_details:
            {
              chat: {
                entitlement: 0,
                remaining: 0,
                unlimited: false,
                overage_count: 0,
                overage_permitted: false,
                percent_remaining: 0.0,
                has_quota: nil,
                quota_reset_at: nil,
              },
              completions: {
                entitlement: 0,
                remaining: 0,
                unlimited: false,
                overage_count: 0,
                overage_permitted: false,
                percent_remaining: 0.0,
                has_quota: nil,
                quota_reset_at: nil,
              },
              premium_interactions: {
                entitlement: 0,
                remaining: 0,
                unlimited: false,
                overage_count: 0,
                overage_permitted: false,
                percent_remaining: 0.0,
                has_quota: nil,
                quota_reset_at: nil,
              },
            }
          )
      end

      # This is the "failing open" response
      def unlimited_response
        GetQuotaRemainingResponse.new(
          token_based_billing: false,
          quota_details:
            {
              chat: {
                entitlement: 1,
                remaining: 1,
                unlimited: true,
                overage_count: 0,
                overage_permitted: false,
                percent_remaining: 100.0,
                has_quota: nil,
                quota_reset_at: nil,
              },
              completions: {
                entitlement: 1,
                remaining: 1,
                unlimited: true,
                overage_count: 0,
                overage_permitted: false,
                percent_remaining: 100.0,
                has_quota: nil,
                quota_reset_at: nil,
              },
              premium_interactions: {
                entitlement: 1,
                remaining: 1,
                unlimited: true,
                overage_count: 0,
                overage_permitted: false,
                percent_remaining: 100.0,
                has_quota: nil,
                quota_reset_at: nil,
              },
            }
        )
      end
    end
  end
end
