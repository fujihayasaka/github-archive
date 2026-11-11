# typed: true
# frozen_string_literal: true

module Billing
  class PackageRegistryPermission
    include GitHub::Memoizer

    class PermissionUnavailableError < ::StandardError; end

    REASON_MESSAGES = {
      disabled: "Account must be enabled to use the GitHub Package Registry",
      plan_ineligible: "Legacy billing plans can't use GitHub Package Registry",
      trade_restricted_organization: TradeControls::Notices.notice_as_plaintext(:org_restricted),
      metered_services_locked: "Metered services have been locked for this account",
      restricted_from_suspension: "Metered services have been locked for this account, as this organization has been restricted",
      trade_screening_restriction: TradeControls::Notices.trade_screening_account_restricted_generic
    }.freeze

    def initialize(owner)
      if owner.try(:delegate_billing_to_business?)
        @owner = owner.business
      else
        @owner = owner
      end
    end

    # Public: Whether package registry billing is enabled
    #
    # Returns Boolean
    def allowed?(public: false)
      return true if owner_is_github? # Skip billing checks for GitHub org
      return true if public

      status[:allowed]
    end

    # Public: Status of GPR for the owner
    #
    # Returns Hash
    memoize def status
      build_status
    end

    # Public: Should download be allowed based on usage
    #
    # Returns Boolean
    def download_allowed?(bytes:, public:)
      return true unless GitHub.billing_enabled? # Skip billing checks if billing is disabled.
      return true if owner_is_github? # Skip billing checks for GitHub org
      return true if FeatureFlag.vexi.enabled_or_raise?(:packages_skip_billing_quotas, owner) # Skip billing checks if skip flag is enabled. # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      return false if !public && owner_plan_is_package_registry_ineligible?
      return false if trade_controls_apply?(public: public)
      return false if @owner.metered_services_locked?
      return false if @owner.is_a?(Business) && @owner.has_commercial_interaction_restriction?(feature_type: :cost_management)
      return false if @owner.is_a?(Business) && @owner.suspended?
      return true if public
      return false if @owner.is_a?(Business) && @owner.downgraded_to_free_plan?
      return true if owner.skip_metered_billing_permission_check_for?(product: :packages)

      gigabytes = bytes.to_f / 1.gigabyte

      usage_allowed = usage_checker.usage_available?(product: "packages", sku: "default", additional_quantity: gigabytes)
      raise PermissionUnavailableError if usage_checker.request_error?

      GitHub.dogstats.increment "billing.package_registry.download_allowed", tags: ["error:false"]
      usage_allowed
    rescue PermissionUnavailableError => e
      GitHub.logger.error({
        exception: e,
        "code.namespace": "PackageRegistryPermission",
        "code.function": "usage_allowed?",
        "gh.billing.billable_entity.id": owner.id,
      })
      GitHub.dogstats.increment "billing.package_registry.download_allowed", tags: ["error:true"]
      # It is an internal error in checking the usage_allowed? status, so we should allow the download
      true
    end

    # Public: Should storage be allowed based on usage
    #
    # Returns Boolean
    def storage_allowed?(bytes:, public:)
      return true unless GitHub.billing_enabled? # Skip billing checks if billing is disabled.
      return true if owner_is_github? # Skip billing checks for GitHub org
      return true if FeatureFlag.vexi.enabled_or_raise?(:packages_skip_billing_quotas, owner) # Skip billing checks if skip flag is enabled. # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      return false if !public && owner_plan_is_package_registry_ineligible?
      return false if @owner.metered_services_locked?
      return false if trade_controls_apply?(public: public)
      return false if @owner.is_a?(Business) && @owner.has_commercial_interaction_restriction?(feature_type: :cost_management)
      return false if @owner.is_a?(Business) && @owner.suspended?
      return true if public
      return false if @owner.is_a?(Business) && @owner.downgraded_to_free_plan?

      # Temporary feature flag to mitigate customer impact in #tmp-li-processing-lag
      return true if FeatureFlag.vexi.enabled_or_raise?(:packages_storage_skip_usage_checks, owner) # Skip billing checks if skip flag is enabled. # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      return true if owner.skip_metered_billing_permission_check_for?(product: :storage)

      additional_quantity = 0

      if !FeatureFlag.vexi.enabled_or_raise?(:billing_large_event_windows) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        megabytes = bytes.to_f / 1.megabyte
        additional_quantity = shared_storage_usage.additional_mb_hours_by_end_of_cycle(additional_megabytes: megabytes)
      end

      usage_allowed = usage_checker.usage_available?(
        product: "shared_storage",
        sku: "default",
        additional_quantity: additional_quantity
      )
      raise PermissionUnavailableError if usage_checker.request_error?

      GitHub.dogstats.increment "billing.package_registry.storage_allowed", tags: ["error:false"]
      usage_allowed
    rescue PermissionUnavailableError => e
      GitHub.logger.error({
        exception: e,
        "code.namespace": "PackageRegistryPermission",
        "code.function": "storage_allowed?",
        "gh.billing.billable_entity.id": owner.id,
      })
      GitHub.dogstats.increment "billing.package_registry.storage_allowed", tags: ["error:true"]
      # It is an internal error in checking the usage_allowed? status, so we should allow the storage
      true
    end

    private

    attr_reader :owner

    def build_status
      return allowed_status unless GitHub.billing_enabled? # Skip billing checks if billing is disabled.
      if fully_trade_restricted_organization_owner?
        not_allowed_status(:trade_restricted_organization)
      elsif @owner.is_a?(Business) && @owner.has_commercial_interaction_restriction?(feature_type: :cost_management)
        not_allowed_status(:trade_screening_restriction)
      elsif @owner.is_a?(Business) && @owner.suspended?
        not_allowed_status(:restricted_from_suspension)
      elsif !owner.plan.package_registry_eligible?
        not_allowed_status(:plan_ineligible)
      elsif owner.disabled?
        not_allowed_status(:disabled)
      elsif @owner.metered_services_locked?
        not_allowed_status(:metered_services_locked)
      else
        allowed_status
      end
    end

    def allowed_status
      { allowed: true, error: {} }
    end

    def not_allowed_status(reason)
      {
        allowed: false,
        error: {
          reason: reason.to_s.upcase,
          message: REASON_MESSAGES[reason],
        },
      }
    end

    def owner_plan_is_package_registry_ineligible?
      !owner.plan.package_registry_eligible?
    end

    def fully_trade_restricted_organization_owner?
      owner.organization? && owner.has_full_trade_restrictions?
    end

    def trade_controls_apply?(public:)
      return false if owner.is_a?(Business) || !owner.has_any_trade_restrictions?
      return true if !public
      fully_trade_restricted_organization_owner?
    end

    memoize def usage_checker
      Billing::UsageChecker.new(account: owner, product_names: %w[packages shared_storage])
    end

    memoize def shared_storage_usage
      Billing::SharedStorageUsage.new(owner)
    end

    def owner_is_github?
      owner.is_a?(Organization) && owner.login == "github"
    end
  end
end
