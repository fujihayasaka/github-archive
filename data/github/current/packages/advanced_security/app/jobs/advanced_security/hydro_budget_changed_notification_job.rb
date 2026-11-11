# typed: strict
# frozen_string_literal: true

# Consumes billingplatform.v1.BudgetChangedNotification hydro events for GHAS SKUs.
# Immediately locks or unlocks metered usage in response to budget changes,
# rather than waiting for the scheduled lock/unlock jobs to run.
module AdvancedSecurity
  class HydroBudgetChangedNotificationJob < ::HydroMessageJob
    queue_as :hydro_advanced_security_budget_changed

    GHAS_PRICING_TARGETS = T.let({
      "ghas_licenses" => GitHub::Turboghas::SKU::Bundled,
      "ghas_code_security_licenses" => GitHub::Turboghas::SKU::CodeSecurity,
      "ghas_secret_protection_licenses" => GitHub::Turboghas::SKU::SecretSecurity,
    }.freeze, T::Hash[String, GitHub::Turboghas::SKU])

    LOCK_IMMEDIATELY_REASONS = T.let(%w[BUDGET_EXHAUSTED].freeze, T::Array[String])
    CHECK_CPWU_REASONS = T.let(%w[BUDGET_UPDATED_HARD_LIMIT BUDGET_DELETED BUDGET_SET_ZERO_HARD_LIMIT].freeze, T::Array[String])

    discard_on(StandardError) { |error| Failbot.report(error, app: "advanced_security", context: "hydro_budget_changed_notification_job") }
    retry_on_dirty_exit
    retry_on AdvancedSecurity::ServiceError, delay: :polynomially_longer, max_retries: 5

    sig { void }
    def perform
      msg = message.with_indifferent_access
      sku = GHAS_PRICING_TARGETS[msg.dig(:pricing_target, :pricing_target_id)]
      return unless sku

      customer = Customer.find_by(id: msg[:customer_id])
      return unless customer

      entity = customer.billable_owner
      return unless entity.is_a?(Business) || entity.is_a?(Organization)
      return unless entity.feature_flag_enabled?("ghas_cpwu_budget_notification_consumer", default: false)
      return unless entity.advanced_security_billable_entity?
      return unless entity.advanced_security_metered_for_entity?

      service = AdvancedSecurity::MeteredUsageService.new
      reason_type = msg[:reason_type].to_s

      if LOCK_IMMEDIATELY_REASONS.include?(reason_type)
        lock_if_unlocked(service, entity, sku, "BudgetExhausted")
      elsif CHECK_CPWU_REASONS.include?(reason_type)
        sync_lock_state(service, entity, sku, customer.id)
      end
    end

    private

    sig { params(service: MeteredUsageService, entity: T.any(Business, Organization), sku: GitHub::Turboghas::SKU, reason: String).void }
    def lock_if_unlocked(service, entity, sku, reason)
      return if service.sku_locked_for_entity?(entity, sku)

      with_write { service.lock_sku_for_entity(entity, sku, reason) }
      instrument(:locked, sku, entity:, reason:)
    end

    sig { params(service: MeteredUsageService, entity: T.any(Business, Organization), sku: GitHub::Turboghas::SKU, customer_id: Integer).void }
    def sync_lock_state(service, entity, sku, customer_id)
      can_proceed, reason = service.can_proceed_with_usage?(customer_id, sku)
      locked = service.sku_locked_for_entity?(entity, sku)

      if can_proceed && locked
        with_write { service.unlock_sku_for_entity(entity, sku) }
        instrument(:unlocked, sku, entity:)
      elsif !can_proceed && !locked
        with_write { service.lock_sku_for_entity(entity, sku, reason) }
        instrument(:locked, sku, entity:, reason:)
      end
    end

    sig { params(action: Symbol, sku: GitHub::Turboghas::SKU, entity: T.any(Business, Organization), reason: T.nilable(String)).void }
    def instrument(action, sku, entity:, reason: nil)
      entity_type = entity.is_a?(Business) ? "business" : "organization"
      tags = ["sku:#{sku.to_param}", "entity_type:#{entity_type}"]
      tags << "reason:#{reason}" if reason
      GitHub.dogstats.increment("advanced_security.metered_usage.budget_changed.#{action}", tags:)
    end
  end
end
