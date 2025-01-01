# typed: strict
# frozen_string_literal: true

module Billing
  class CancelPastDueProductsJob < BillingJob
    include GitHub::Billing::ZuoraRateLimitHandler
    include GitHub::Memoizer

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
      retry_on(error, wait: :polynomially_longer) do |_job, error|
        Failbot.report(error)
      end
    end

    rescue_from(Zuorest::TooManyRequestsError) do |error|
      T.bind(self, CancelPastDueProductsJob)

      zuora_rate_limit_handler(self, error)
    end

    class CancelledProduct < T::Struct
      prop :name, T.nilable(String)
      prop :type, T.nilable(String)
    end

    sig do
      params(
        billable_entity: T.nilable(Billing::Types::Account),
        send_email: T::Boolean,
        caller: T.nilable(String)
      ).void
    end
    def perform(billable_entity:, send_email: false, caller: "unknown")
      return unless billable_entity.present?
      @caller = T.let(caller, T.nilable(String))
      cancelled_products = []
      past_due_ids = past_due_product_rate_plan_charge_ids(billable_entity)

      with_write do
        # GitHub plan
        if billable_entity.is_a?(User) && should_downgrade_github_plan?(billable_entity, past_due_ids)
          cancelled_products << CancelledProduct.new(name: billable_entity.plan.zuora_product_name, type: GitHub::Plan::ZuoraDependency::ZUORA_PRODUCT_TYPE)
          downgrade_to_free(billable_entity)
        elsif billable_entity.is_a?(Business) && should_downgrade_business_github_plan?(past_due_ids)
          # A business that isn't on a free plan must be on the business plus plan
          cancelled_products << CancelledProduct.new(name: GitHub::Plan.business_plus.zuora_product_name, type: GitHub::Plan::ZuoraDependency::ZUORA_PRODUCT_TYPE)
          billable_entity.downgrade_to_free_plan
        end

        # Data packs
        if billable_entity.is_a?(User) && should_cancel_data_packs?(billable_entity, past_due_ids)
          cancelled_products << CancelledProduct.new(name: Asset::Status.zuora_product_name, type: Asset::Status::ZuoraDependency::ZUORA_PRODUCT_TYPE)
          billable_entity.reset_data_packs
        end

        # Subscription items
        cancel_subscription_items_past_due!(billable_entity, past_due_product_rate_plan_charge_ids: past_due_ids.to_a, force: true, skip_sync: true).each do |result|
          sub_item = result.subscription_item
          next if !sub_item.present? || !result.result.success
          cancelled_products << cancelled_product_for_subscription_item(sub_item)
        end
      end

      # Send billing lock email with names of the products that have been cancelled
      # TODO: Should we send these same emails for EAs?
      if send_email && billable_entity.disabled? && billable_entity.is_a?(User)
        cancelled_product_names = cancelled_products.map(&:name)
        billable_entity.send_billing_lock_email(cancelled_product_names)
      end

      # Instrument and update the Zuora subscription for cancelled products
      if cancelled_products.any?
        cancelled_products.each { |product| instrument_cancelled_product(billable_entity, product) }
        billable_entity.plan_subscriptions.select(&:has_external_subscription?).each(&:synchronize_later)
      end
    end

    private

    sig { params(user: User).void }
    def downgrade_to_free(user)
      old_plan = user.plan
      user.update_column(:plan, GitHub::Plan::FREE)
      user.invalidate_cache("update_plan")
      user.update_plan_if_addons_changed
      user.track_plan_change(user, old_plan, reason: "account disabled")
    end

    # The plan on the business entity might be set to "Free" if it has been disabled / downgraded already, which is why
    # the plan itself can't be depended on to determine if the business should be downgraded.
    sig { params(billable_entity: Billing::Types::Account, past_due_product_rate_plan_charge_ids: T::Set[String]).returns(T::Boolean) }
    def should_downgrade_github_plan?(billable_entity, past_due_product_rate_plan_charge_ids)
      plan = billable_entity.plan
      return false unless plan.cost.positive?
      # We exclude plans that don't have unlimited private repositories to avoid downgrading accounts that won't
      # be able upgrade back to the same plan. At the time of writing, the `legacy?` check does not include all
      # off-market plans so the check for private repositories is used instead.
      return false if billable_entity.is_a?(User) && !billable_entity.has_unlimited_private_repositories?
      return T.must(billable_entity.next_billing_date) <= GitHub::Billing.today unless billable_entity.external_subscription?
      product_rate_plan_charge_ids = plan.zuora_charge_ids(cycle: billable_entity.plan_duration)&.values || []
      product_rate_plan_charge_ids.any? { |id| past_due_product_rate_plan_charge_ids.include?(id) }
    end

    sig { params(past_due_product_rate_plan_charge_ids: T::Set[String]).returns(T::Boolean) }
    def should_downgrade_business_github_plan?(past_due_product_rate_plan_charge_ids)
      past_due_product_rate_plan_charge_ids.intersect?(business_plus_product_rate_plan_charge_ids)
    end

    sig { params(billable_entity: Billing::Types::Account, past_due_product_rate_plan_charge_ids: T::Set[String]).returns(T::Boolean) }
    def should_cancel_data_packs?(billable_entity, past_due_product_rate_plan_charge_ids)
      return false unless billable_entity.data_packs.positive?
      return T.must(billable_entity.next_billing_date) <= GitHub::Billing.today unless billable_entity.external_subscription?
      product_rate_plan_charge_ids = Asset::Status.zuora_charge_ids(cycle: billable_entity.plan_duration).values
      product_rate_plan_charge_ids.any? { |id| past_due_product_rate_plan_charge_ids.include?(id) }
    end

    sig { params(billable_entity: Billing::Types::Account).returns(T::Set[String]) }
    def past_due_product_rate_plan_charge_ids(billable_entity)
      zuora_account_id = billable_entity.customer&.zuora_account_id
      return Set[] unless zuora_account_id.present?

      start = Time.now.to_f
      open_invoices = Billing::Zuora::Invoice.open_invoices_for_account(zuora_account_id)
      product_rate_plan_charge_ids = open_invoices.flat_map do |invoice|
        # Some invoice items (like discounts) are applied to other invoice items so we need to
        # combine them in order to determine which items actually have a positive charge amount
        item_id_to_product_rate_plan_charge_id = {}
        item_id_to_charge_amount = Hash.new(0)
        invoice.invoice_items.each do |item|
          if item.applied_to_item_id.present?
            item_id_to_charge_amount[item.applied_to_item_id] += item.charge_amount
          else
            item_id_to_charge_amount[item.id] += item.charge_amount
            item_id_to_product_rate_plan_charge_id[item.id] = item.product_rate_plan_charge_id
          end
        end
        # Return only the product rate plan charge ids with a positive charge amount
        item_id_to_charge_amount.filter_map do |item_id, charge_amount|
          item_id_to_product_rate_plan_charge_id[item_id] if charge_amount.positive?
        end
      end.to_set

      elapsed_ms = (Time.now.to_f - start) * 1_000
      GitHub.dogstats.timing("billing.past_due_products", elapsed_ms, tags: ["billable_entity_type:#{billable_entity.class.name}",
        "found:#{product_rate_plan_charge_ids.any?}", "open_invoice_count:#{open_invoices.size}"])

      GitHub.logger.info(
        logger_fields(billable_entity).merge!({
          "code.function": "past_due_products",
          "gh.billing.zuora.open_invoices.ids": open_invoices.map { |i| i.instance_variable_get(:@invoice_id) }.to_s,
          "gh.billing.zuora.open_invoices.product_rate_plan_charge_ids": product_rate_plan_charge_ids.to_s,
          "gh.billing.zuora.open_invoices.product_rate_plan_charge_ids.count": product_rate_plan_charge_ids.size
        })
      )

      product_rate_plan_charge_ids
    rescue Zuorest::HttpError => error
      GitHub.dogstats.increment("billing.past_due_products.error", tags: ["billable_entity_type:#{self.class.name}",
        "error:#{error.class.name}"])
      GitHub.logger.error(error, logger_fields(billable_entity).merge!({ "code.function": "past_due_products" }))
      Set[]
    end

    sig do
      params(
        billable_entity: Billing::Types::Account,
        past_due_product_rate_plan_charge_ids: T::Array[String],
        force: T::Boolean,
        skip_sync: T::Boolean,
        subscribable_type: T.nilable(String)
      ).returns(T::Array[Billing::Public::SubscriptionItems::ResultStruct])
    end
    def cancel_subscription_items_past_due!(billable_entity, past_due_product_rate_plan_charge_ids:, force: false, skip_sync: false, subscribable_type: nil)
      subscription_items_past_due(billable_entity, past_due_product_rate_plan_charge_ids:).filter_map do |item|
        next if subscribable_type && item.subscribable_type != subscribable_type
        next if item.in_app_purchase?

        item.cancel!(force: force, skip_sync: skip_sync)
      end
    end

    sig do
      params(
        billable_entity: Billing::Types::Account,
        past_due_product_rate_plan_charge_ids: T::Array[String]
      ).returns(T::Array[Billing::SubscriptionItem])
    end
    def subscription_items_past_due(billable_entity, past_due_product_rate_plan_charge_ids:)
      no_zuora_subscription = !billable_entity.external_subscription?

      billable_entity.active_subscription_items.select(&:subscribable_paid?).filter_map do |item|
        next item if no_zuora_subscription && item.past_service_period?

        item_present_in_an_open_invoice = past_due_product_rate_plan_charge_ids.include?(item.active_product_rate_plan_charge_id)
        next item if item_present_in_an_open_invoice
      end
    end

    sig { returns(T::Array[String]) }
    memoize def business_plus_product_rate_plan_charge_ids
      (GitHub::Plan.business_plus.zuora_charge_ids(cycle: "month")&.values || []) +
        (GitHub::Plan.business_plus.zuora_charge_ids(cycle: "year")&.values || [])
    end

    sig { params(item: Billing::SubscriptionItem).returns(CancelledProduct) }
    def cancelled_product_for_subscription_item(item)
      if item.subscribable_Billing_ProductUUID?
        subscribable = item.subscribable
        CancelledProduct.new(name: subscribable.name, type: subscribable.product_type)
      elsif item.subscribable_SponsorsTier?
        CancelledProduct.new(name: item.listing_name, type: SponsorsListing::ZuoraDependency::ZUORA_PRODUCT_TYPE)
      else # Must be a Marketplace Listing Plan
        CancelledProduct.new(name: item.listing_name, type: Marketplace::ListingPlan::ZuoraDependency::ZUORA_PRODUCT_TYPE)
      end
    end

    sig { params(billable_entity: Billing::Types::Account, product: CancelledProduct).void }
    def instrument_cancelled_product(billable_entity, product)
      GitHub.dogstats.increment("billing.cancel_past_due_products_job.cancelled_product", tags: ["billable_entity_type:#{billable_entity.class.name}",
        "product_type:#{product.type}"])

      GitHub.logger.info(
        logger_fields(billable_entity).merge({
          "code.function" => "instrument_cancelled_product",
          "gh.billing.product_name" => product.name,
          "gh.billing.product_type" => product.type,
        })
      )
    end

    sig { params(billable_entity: Billing::Types::Account).returns(T::Hash[String, T.untyped]) }
    def logger_fields(billable_entity)
      fields = {
        "code.namespace": self.class.name,
        "gh.billing.billable_entity.billing_attempts": billable_entity.billing_attempts,
        "gh.billing.billable_entity.next_billing_date": billable_entity.next_billing_date,
        "gh.billing.billable_entity.id": billable_entity.id,
        "gh.billing.billable_entity.login": billable_entity.display_login,
        "gh.billing.billable_entity.plan": billable_entity.plan.name,
        "gh.billing.billable_entity.should_disable": billable_entity.should_disable?,
        "gh.billing.billable_entity.type": billable_entity.class.name,
        "gh.caller": @caller,
      }

      if plan_subscription = billable_entity.plan_subscription
        fields.merge!({
          "gh.billing.plan_subscription.id": plan_subscription.id,
          "gh.billing.plan_subscription.zuora_subscription_id": plan_subscription.zuora_subscription_id,
          "gh.billing.plan_subscription.zuora_subscription_number": plan_subscription.zuora_subscription_number,
        })
      end

      if customer = billable_entity.customer
        fields.merge!({
          "gh.billing.customer.disabled_reasons": customer.disabled_reasons&.join(","),
          "gh.billing.customer.id": customer.id,
          "gh.billing.customer.requires_manual_transactions": customer.requires_manual_transactions?,
          "gh.billing.customer.zuora_account_id": customer.zuora_account_id,
        })
      end

      fields
    end
  end
end
