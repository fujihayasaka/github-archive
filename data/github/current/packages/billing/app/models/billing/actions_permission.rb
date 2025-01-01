# typed: strict
# frozen_string_literal: true

module Billing
  class ActionsPermission

    include GitHub::Memoizer

    class PermissionUnavailableError < ::StandardError; end

    REASON_MESSAGES = T.let({
      plan_ineligible: "Legacy billing plans can't use GitHub Actions",
      disabled: "Account must be enabled to use the GitHub Actions",
      trade_restricted_organization: TradeControls::Notices.notice_as_plaintext(:org_restricted),
      metered_services_locked: "Metered services have been locked for this account",
      restricted_from_suspension: "Metered services have been locked for this account, as this organization has been restricted",
      trade_screening_restriction: TradeControls::Notices.trade_screening_account_restricted_generic
    }.freeze, T::Hash[Symbol, String])

    sig { params(owner: Billing::Types::Account).void }
    def initialize(owner)
      @owner = T.let(owner.billable_owner, Billing::Types::Account)
    end

    sig { params(public: T::Boolean).returns(T::Boolean) }
    def allowed?(public: false)
      return true if public && !fully_trade_restricted_organization_owner?
      status[:allowed]
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    memoize def status
      build_status
    end

    sig { params(public: T::Boolean, sku: T.nilable(String)).returns(T::Boolean) }
    def usage_allowed?(public:, sku: nil)
      sku = "linux" if sku.blank?

      return true unless GitHub.billing_enabled? # Skip billing checks if billing is disabled.

      return false if trade_controls_apply?(public: public)

      return false if @owner.is_a?(Business) && @owner.suspended?

      return false if @owner.is_a?(Business) && @owner.has_commercial_interaction_restriction?(feature_type: :cost_management)

      if public && standard_runner?(sku)
        return true
      elsif !owner.plan.actions_eligible?
        return false
      end

      return false if @owner.is_a?(Business) && @owner.downgraded_to_free_plan?

      return true if owner.feature_enabled?(:actions_skip_billing_quotas)

      # Billing Checks
      return true if owner.skip_metered_billing_permission_check_for?(product: :actions)

      usage_info = usage_checker.usage_for(product: "actions", sku: sku, account_specific_lookup: false)
      raise PermissionUnavailableError if usage_checker.request_error?

      # UsageChecker only gives results for known skus, if there is no usage_info for the sku
      # we're probably checking an experimental or beta sku
      #
      # These should be treated the same as a larger runner, so pick a known larger runner sku
      # as a proxy for the usage_available? check
      if usage_info.nil?
        sku = "linux_4_core"
      end

      usage_checker.usage_available?(product: "actions", sku: sku)
    end

    sig { params(public: T::Boolean).returns(T::Boolean) }
    def storage_allowed?(public:)
      return true unless GitHub.billing_enabled? # Skip billing checks if billing is disabled.

      return false if trade_controls_apply?(public: public)

      return false if @owner.is_a?(Business) && @owner.has_commercial_interaction_restriction?(feature_type: :cost_management)

      return false if @owner.is_a?(Business) && @owner.suspended?

      return true if public

      return false if !owner.plan.actions_eligible?

      return false if @owner.is_a?(Business) && @owner.downgraded_to_free_plan?

      return true if owner.feature_enabled?(:actions_skip_billing_quotas)

      # Temporary feature flag to mitigate customer impact in #tmp-li-processing-lag
      return true if owner.feature_enabled?(:actions_storage_skip_usage_checks)

      # Billing Checks
      return true if owner.skip_metered_billing_permission_check_for?(product: :storage)

      additional_quantity = 0

      if !GitHub.flipper[:billing_large_event_windows].enabled?
        additional_quantity = ActiveRecord::Base.connected_to(role: :reading) do
          shared_storage_usage.additional_mb_hours_by_end_of_cycle
        end
      end

      check_result = usage_checker.usage_available?(
        product: "shared_storage",
        sku: "default",
        additional_quantity: additional_quantity
      )
      raise PermissionUnavailableError if usage_checker.request_error?
      check_result
    end

    private

    sig { returns(Billing::Types::Account) }
    attr_reader :owner

    sig { params(sku: String).returns(T::Boolean) }
    def standard_runner?(sku)
      Billing::Actions::MEUSE_STANDARD_RUNNERS.include?(sku)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def build_status
      return allowed_status unless GitHub.billing_enabled? # Skip billing checks if billing is disabled.

      if fully_trade_restricted_organization_owner?
        not_allowed_status(:trade_restricted_organization)
      elsif @owner.is_a?(Business) && @owner.has_commercial_interaction_restriction?(feature_type: :cost_management)
        not_allowed_status(:trade_screening_restriction)
      elsif @owner.is_a?(Business) && @owner.suspended?
        not_allowed_status(:restricted_from_suspension)
      elsif !owner.plan.actions_eligible?
        not_allowed_status(:plan_ineligible)
      elsif owner.disabled?
        not_allowed_status(:disabled)
      elsif @owner.metered_services_locked?
        not_allowed_status(:metered_services_locked)
      else
        allowed_status
      end
    end

    sig { params(reason: Symbol).returns({ allowed: T::Boolean, error: T::Hash[Symbol, T.untyped] }) }
    def not_allowed_status(reason)
      {
        allowed: false,
        error: {
          reason: reason.to_s.upcase,
          message: REASON_MESSAGES[reason],
        },
      }
    end

    sig { returns({ allowed: T::Boolean, error: T::Hash[Symbol, T.untyped] }) }
    def allowed_status
      { allowed: true, error: {} }
    end

    sig { returns(T::Boolean) }
    def fully_trade_restricted_organization_owner?
      !!(owner.organization? && owner.has_full_trade_restrictions?)
    end

    sig { params(public: T::Boolean).returns(T::Boolean) }
    def trade_controls_apply?(public:)
      return false if owner.is_a?(Business) || !owner.has_any_trade_restrictions?
      return true if !public
      fully_trade_restricted_organization_owner?
    end

    sig { returns(Billing::UsageChecker) }
    memoize def usage_checker
      Billing::UsageChecker.new(account: owner, product_names: %w[actions shared_storage])
    end

    sig { returns(Billing::SharedStorageUsage) }
    memoize def shared_storage_usage
      Billing::SharedStorageUsage.new(owner)
    end
  end
end
