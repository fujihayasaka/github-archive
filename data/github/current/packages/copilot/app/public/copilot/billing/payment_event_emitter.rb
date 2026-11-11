# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    class PaymentEventEmitter
      COPILOT_PLAN_UPGRADE_HYDRO_SCHEMA = "github.copilot.v2.CopilotPlanUpgradeApplied"
      COPILOT_OVERAGE_CHARGE_HYDRO_SCHEMA = "github.copilot.v2.CopilotOverageChargeApplied"

      # TODO: Replace with copilot-limiter API once available
      PRODUCT_KEY_TO_ENTITLEMENTS_CENTS = T.let({
        Copilot::INDIVIDUAL_PRO_PRODUCT_KEY => 1500,
        Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY => 7000,
        Copilot::INDIVIDUAL_MAX_PRODUCT_KEY => 20000,
        Copilot::EDU_PRODUCT_KEY => 200,
      }.freeze, T::Hash[String, Integer])

      # Maps product keys to CopilotPlan Hydro enum symbols used by CopilotPlanUpgradeApplied schema
      PRODUCT_KEY_TO_HYDRO_ENUM = T.let({
        Copilot::INDIVIDUAL_PRO_PRODUCT_KEY => :INDIVIDUAL,
        Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY => :INDIVIDUAL_PRO_PLUS,
        Copilot::INDIVIDUAL_MAX_PRODUCT_KEY => :INDIVIDUAL_MAX,
        Copilot::EDU_PRODUCT_KEY => :INDIVIDUAL_EDU,
      }.freeze, T::Hash[String, Symbol])

      sig { params(copilot_user: Copilot::User).void }
      def initialize(copilot_user)
        @copilot_user = T.let(copilot_user, Copilot::User)
      end

      sig { params(old_product_key: String, new_product_key: String, payment_processor_transaction_id: String, current_overage_cents: Integer).returns(GitHub::Result) }
      def emit_plan_upgrade(old_product_key:, new_product_key:, payment_processor_transaction_id:, current_overage_cents:)
        user = @copilot_user.user_object
        unless FeatureFlag.vexi.enabled?(:billing_copilot_upgrade_orchestration, user, default: false)
          return GitHub::Result.new
        end

        customer_id = user.customer&.id
        return GitHub::Result.error("Customer doesn't exist") unless customer_id

        old_entitlement = if zero_cost_entitlement?(product_key: old_product_key)
          0
        else
          PRODUCT_KEY_TO_ENTITLEMENTS_CENTS[old_product_key]
        end
        new_entitlement = PRODUCT_KEY_TO_ENTITLEMENTS_CENTS[new_product_key]
        unless old_entitlement && new_entitlement
          return GitHub::Result.error("Unknown product key: old=#{old_product_key} new=#{new_product_key}")
        end

        entitlement_delta_cents = new_entitlement - old_entitlement
        if entitlement_delta_cents < 0
          return GitHub::Result.error("Not an upgrade: #{old_product_key} -> #{new_product_key}")
        end

        clawback_cents = [current_overage_cents, entitlement_delta_cents].min

        Hydro::PublishRetrier.publish(
          {
            customer_id: customer_id,
            user_id: user.id,
            old_plan: PRODUCT_KEY_TO_HYDRO_ENUM[old_product_key],
            new_plan: PRODUCT_KEY_TO_HYDRO_ENUM[new_product_key],
            clawback_cents: clawback_cents,
            payment_processor_transaction_id: payment_processor_transaction_id,
            applied_at: Google::Protobuf::Timestamp.new(seconds: Time.now.utc.to_i),
            copilot_tracking_id: user.analytics_tracking_id,
          },
          schema: COPILOT_PLAN_UPGRADE_HYDRO_SCHEMA,
          publisher: GitHub.hydro_publisher,
          partition_key: customer_id,
        )

        GitHub.dogstats.increment("copilot.plan_upgrade.hydro_event_emitted", tags: ["old_plan:#{old_product_key}", "new_plan:#{new_product_key}"])
        GitHub::Result.new {}
      rescue StandardError => e
        Failbot.report(e,
          "gh.user.id" => @copilot_user.user_object.id,
          "code.namespace" => "Copilot::Billing::PaymentEventEmitter",
          "code.function" => "emit_plan_upgrade",
          "gh.copilot.old_product_key" => old_product_key,
          "gh.copilot.new_product_key" => new_product_key,
          "gh.copilot.entitlement_delta_cents" => defined?(entitlement_delta_cents) ? entitlement_delta_cents : nil,
          "gh.copilot.current_overage_cents" => current_overage_cents,
          "gh.copilot.clawback_cents" => defined?(clawback_cents) ? clawback_cents : nil,
          "gh.billing.payment_processor_transaction_id" => payment_processor_transaction_id,
        )
        GitHub.dogstats.increment("copilot.plan_upgrade.hydro_event_error")
        GitHub::Result.error(e)
      end

      sig { params(payment_amount_cents: Integer, payment_processor_transaction_id: String).returns(GitHub::Result) }
      def emit_overage_charge_applied(payment_amount_cents:, payment_processor_transaction_id:)
        user = @copilot_user.user_object
        unless FeatureFlag.vexi.enabled?(:copilot_cfi_pay_to_continue, user, default: false)
          return GitHub::Result.new
        end

        customer_id = user.customer&.id
        return GitHub::Result.error("Customer doesn't exist") unless customer_id

        Hydro::PublishRetrier.publish(
          {
            customer_id: customer_id,
            user_id: user.id,
            payment_amount_cents: payment_amount_cents,
            payment_processor_transaction_id: payment_processor_transaction_id,
            applied_at: Google::Protobuf::Timestamp.new(seconds: Time.now.utc.to_i),
          },
          schema: COPILOT_OVERAGE_CHARGE_HYDRO_SCHEMA,
          publisher: GitHub.hydro_publisher,
          partition_key: customer_id,
        )

        GitHub.dogstats.increment("copilot.overage_charge.hydro_event_emitted")
        GitHub::Result.new {}
      rescue StandardError => e
        Failbot.report(e,
          "gh.user.id" => @copilot_user.user_object.id,
          "code.namespace" => "Copilot::Billing::PaymentEventEmitter",
          "code.function" => "emit_overage_charge_applied",
          "gh.copilot.payment_amount_cents" => payment_amount_cents,
          "gh.billing.payment_processor_transaction_id" => payment_processor_transaction_id,
        )
        GitHub.dogstats.increment("copilot.overage_charge.hydro_event_error")
        GitHub::Result.error(e)
      end

      private

      sig { params(product_key: String).returns(T::Boolean) }
      def zero_cost_entitlement?(product_key:)
        # EDU is a free plan; its entitlement is not counted as paid usage
        product_key == EDU_PRODUCT_KEY
      end
    end
  end
end
