# typed: strict
# frozen_string_literal: true

module Codespaces
  module Access
    class VNextBillingChecker < Codespaces::Command
      FAST_TIMEOUT_SECONDS = 5

      sig { returns(T.any(::Business, ::User, NilClass)) }
      attr_reader :billable_owner

      sig { returns(T::nilable(Integer)) }
      attr_reader :user_id

      sig { returns(T::nilable(Repository)) }
      attr_reader :repository

      sig { returns(T::Boolean) }
      attr_reader :fast_timeout

      sig { params(billable_owner: T.nilable(::User), user_id: T::nilable(Integer), repository: T::nilable(Repository), fast_timeout: T.untyped).void }
      def initialize(billable_owner, user_id: nil, repository: nil, fast_timeout: true)
        @billable_owner = billable_owner
        @user_id = user_id
        @repository = repository
        @fast_timeout = fast_timeout
      end

      sig { override.params(prebuild: T::Boolean).returns(Codespaces::Access::AllowedResult) }
      def perform(prebuild: false)

        return allowed_result(allowed: false) unless billable_owner
        return allowed_result(allowed: true) if billable_owner&.free_codespace_use_enabled?
        return allowed_result(allowed: true) unless Codespaces::BillingPolicy.owner_billing_check_required?(billable_owner)

        if prebuild
          allowed_result(allowed: can_bill_for_prebuild_usage?)
        else
          allowed_result(allowed: can_bill_for_codespace_usage?)
        end
      end

      private

      sig { params(allowed: T::Boolean).returns(Codespaces::Access::AllowedResult) }
      def allowed_result(allowed:)
        result = if allowed
          AllowedResult::ALLOWED
        else
          # As of writing this, billing v next doesn't have a way to tell us _why_
          # billing isn't allowed, only that it's not
          AllowedResult::DISALLOW_BILLING
        end
        AllowedResult.new(result)
      end

      sig { returns(T::Boolean) }
      def can_bill_for_codespace_usage?
        # any compute sku will work for this check, we just need to ask about the right bucket of usage
        can_bill_for_usage?(Codespaces::Billing::BillingPlatform::STORAGE_SKU) && can_bill_for_usage?(T.must(Codespaces::Billing::BillingPlatform::COMPUTE_SKUS.first))
      end

      sig { returns(T::Boolean) }
      def can_bill_for_prebuild_usage?
        can_bill_for_usage?(Codespaces::Billing::BillingPlatform::PREBUILD_STORAGE_SKU)
      end

      sig { returns(::BillingPlatform::Base::EntityDetail) }
      memoize def entity_detail
        ::BillingPlatform::Base::EntityDetail.new(
          customerId: billable_owner&.feature_flag_enabled_or_raise?(:use_find_or_create_customer) ? billable_owner&.find_or_create_customer&.id.to_s : billable_owner&.billing_customer&.id.to_s, # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          repoId: repository&.id,
          ownerId: repository&.owner_id,
          actorId: user_id,
        )
      end

      sig { returns(::Billing::Platform::Api::Client) }
      memoize def billing_client
        timeout = fast_timeout ? FAST_TIMEOUT_SECONDS : nil
        ::Billing::Platform::Api::Client.new(timeout:)
      end

      sig { params(sku_name: String).returns(T::Boolean) }
      def can_bill_for_usage?(sku_name)
        usage_key = ::BillingPlatform::Api::V1::UsageKey.new(
          product: "codespaces",
          sku: sku_name,
          entityDetail: entity_detail,
        )

        response = billing_client.can_proceed_with_usage(usage_key: usage_key)
        if response.is_a?(Hash) && response.has_key?(:canProceed)
          response[:canProceed]
        else
          # Fail open when billing service is down
          response.is_a?(::Billing::Platform::Api::Error)
        end
      end
    end
  end
end
