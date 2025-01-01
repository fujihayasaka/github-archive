# typed: strict
# frozen_string_literal: true

module Codespaces
  module Access
    class MeuseBillingChecker < Codespaces::Command
      include GitHub::Memoizer

      sig { returns(T.untyped) }
      attr_reader :billable_owner

      # Meuse being overloaded can lead to timeouts when making requests for usage checks.
      # We should timeout relatively quickly on any request made that is time senstive, like not a background job.
      sig { params(billable_owner: T.untyped, fast_timeout: T.untyped).void }
      def initialize(billable_owner, fast_timeout: true)
        @billable_owner = billable_owner

        if @billable_owner
          @usage = T.let(::Billing::CodespacesUsage.new(account: @billable_owner, fast_timeout: fast_timeout), ::Billing::CodespacesUsage)
        end
      end

      # Typically we don't pass any arguments to perform in a command. This is an exception because
      # the same @usage could be used for either prebuilds or codespaces.
      sig { override.params(prebuild: T::Boolean).returns(Codespaces::Access::AllowedResult) }
      def perform(prebuild: false)
        if prebuild
          calculate_prebuild_allowed
        else
          calculate_allowed
        end
      end

      private

      sig { returns(Codespaces::Access::AllowedResult) }
      def calculate_allowed
        if exceeds_billing_attempts_limit_for_user?
          return AllowedResult.new(AllowedResult::DISALLOW_PAYMENT_METHOD)
        end

        # Allow users to create/use codespaces by default if the billing system errored
        if !usage_allowed_for_user? && !request_error?
          if exhausted_all_entitlements?
            return AllowedResult.new(AllowedResult::DISALLOW_ENTITLEMENTS)
          else
            return AllowedResult.new(AllowedResult::DISALLOW_SPENDING_LIMIT)
          end
        end

        if request_error?
          GitHub.dogstats.increment("codespaces.usage_checker.calculate_allowed.request_error_bypass")
        end

        Codespaces::Access::AllowedResult.allowed
      end

      sig { returns(Codespaces::Access::AllowedResult) }
      def calculate_prebuild_allowed
        if exceeds_billing_attempts_limit_for_user?
          return Codespaces::Access::AllowedResult.new(Codespaces::Access::AllowedResult::DISALLOW_PAYMENT_METHOD)
        end

        # Don't allow prebuild creation if billing system errored
        if !prebuild_usage_allowed_for_user?
          if exhausted_storage_entitlements?
            return Codespaces::Access::AllowedResult.new(Codespaces::Access::AllowedResult::DISALLOW_ENTITLEMENTS)
          else
            return Codespaces::Access::AllowedResult.new(Codespaces::Access::AllowedResult::DISALLOW_SPENDING_LIMIT)
          end
        end

        Codespaces::Access::AllowedResult.allowed
      end

      # Was there an error fetching meuse?
      sig { returns(T::Boolean) }
      def request_error?
        @usage.request_error?
      end

      # Did the billable owner use all entitlements included and doesn't have a spending limit set up
      sig { returns(T::Boolean) }
      memoize def exhausted_all_entitlements?
        @usage.no_spending_limit_and_exhausted_entitlements?
      end

      # Did the billable owner use all storage entitlements included and doesn't have a spending limit set up
      sig { returns(T::Boolean) }
      memoize def exhausted_storage_entitlements?
        @usage.no_spending_limit_and_exhausted_storage_entitlements?
      end

      sig { returns(T::Boolean) }
      memoize def usage_allowed_for_user?
        return false if billable_owner.nil?
        return false if GitHub.flipper[:codespaces_offboarding_force_limit].enabled?(billable_owner)
        return true if billable_owner.free_codespace_use_enabled?
        return true unless Codespaces::BillingPolicy.owner_billing_check_required?(billable_owner)

        @usage.usage_allowed?
      end

      sig { returns(T::Boolean) }
      memoize def prebuild_usage_allowed_for_user?
        return false if billable_owner.nil?
        return true if billable_owner.free_codespace_use_enabled?
        return true unless Codespaces::BillingPolicy.owner_billing_check_required?(billable_owner)

        @usage.prebuild_usage_allowed?
      end

      sig { returns(T::Boolean) }
      memoize def exceeds_billing_attempts_limit_for_user?
        return true if billable_owner.nil?
        return false if billable_owner.free_codespace_use_enabled?

        return false unless Codespaces::BillingPolicy.owner_billing_check_required?(billable_owner)

        @usage.paid_overages_restricted_by_owner_payment_issue?
      end
    end
  end
end
