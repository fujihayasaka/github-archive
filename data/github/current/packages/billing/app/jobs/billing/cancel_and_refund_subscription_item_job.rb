# typed: strict
# frozen_string_literal: true

module Billing
  class CancelAndRefundSubscriptionItemJob < BillingJob

    include GitHub::Billing::ZuoraRateLimitHandler

    queue_as :cancel_subscription_items

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    Billing::PlanSubscription::SynchronizationEvents::RETRYABLE_ERRORS.each do |error|
      retry_on(error, wait: :polynomially_longer, attempts: ::Billing::PlanSubscription::SynchronizationEvents::RETRYABLE_ATTEMPTS)
    end

    Billing::PlanSubscription::SynchronizationEvents::EXTRA_RETRYABLE_ERRORS.each do |error|
      retry_on(error, wait: :polynomially_longer, attempts: ::Billing::PlanSubscription::SynchronizationEvents::EXTRA_RETRYABLE_ATTEMPTS)
    end

    Billing::PlanSubscription::SynchronizationEvents::DELAYED_RETRYABLE_ERRORS.each do |error|
      retry_on(error, wait: 2.hours, attempts: ::Billing::PlanSubscription::SynchronizationEvents::DELAYED_RETRYABLE_ATTEMPTS)
    end

    rescue_from(Zuorest::TooManyRequestsError) do |error|
      T.bind(self, CancelAndRefundSubscriptionItemJob)

      zuora_rate_limit_handler(self, error)
    end

    # This error is raised when we the subscription item being attempted to cancel is an in-app purchase and
    # the allow_cancelling_iap flag is not set to true. This is to prevent accidental cancellations of in-app
    # purchased items without acknowledging the source-of-truth risk: Apple/Google should be the source-of-truth for
    # cancelling in-app purchases.
    class InAppPurchaseCancellationError < StandardError; end

    # This error is returned from Zuora when attempting to adjust an item on an invoice that is in a draft state.
    # This can happen when the job is run while we are in the process of creating an invoice for the subscription
    # item being cancelled. The invoice generation process in Zuora can take up to 3 hours so we expect subsequent
    # retries of this job to eventually succeed.
    INVOICE_DRAFT_STATUS_ERROR = "Invoice Item Adjustments cannot be created for invoices with Draft status"
    class InvoiceDraftStatusError < StandardError; end
    retry_on(InvoiceDraftStatusError, wait: 1.hour, attempts: 3)

    # This error is raised when we've exhausted all retries on the refund method. This error is raised instead of
    # the original error to avoid retrying the job. Retrying the job will not work due to the `preview_result`
    # being lost on the retry.
    class RefundAttemptsExhaustedError < StandardError; end
    MAX_REFUND_ATTEMPTS = 3

    sig { returns(T.nilable(Integer)) }
    attr_reader :organization_id

    # This is a flag to indicate whether the subscription item should be fully refunded.
    # Note, we have to make this nilable because Sorbet wants non-nilable instance vars to be defined in the
    # initialize  method, but according to https://github.com/rails/rails/issues/40862#issuecomment-747073841, that's
    # not supported in the ActiveJob API.
    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :full_refund

    sig do
      params(
        subscription_item: ::Billing::SubscriptionItem,
        organization_id: T.nilable(Integer),
        full_refund: T.nilable(T::Boolean),
        allow_cancelling_iap: T.nilable(T::Boolean)
      ).returns(GitHub::Billing::Result)
    end
    def perform(subscription_item, organization_id: nil, full_refund: false, allow_cancelling_iap: false)
      @organization_id = T.let(organization_id, T.nilable(Integer))
      @full_refund = T.let(full_refund, T.nilable(T::Boolean))

      account = subscription_item.account
      plan_subscription = T.must(subscription_item.plan_subscription)

      # Cancel without a refund if the subscription item isn't eligible for a refund
      if subscription_item.on_free_trial?
        log_on_free_trial(subscription_item)
        with_write { subscription_item.cancel!(actor: User.staff_user, force: true) }
        instrument_cancel_and_refund(subscription_item: subscription_item, trial_user: true)
        return GitHub::Billing::Result.success
      end

      # If the subscription was an in-app purchase then we do not want to issue a refund and simply cancel
      # the subscription.
      if subscription_item.in_app_purchase?
        with_write do
          result = subscription_item.cancel!(
            actor: User.staff_user,
            force: true,
            allow_cancelling_iap: allow_cancelling_iap || false
          )

          raise InAppPurchaseCancellationError unless result.result.success
        end

        instrument_cancel_and_refund(subscription_item: subscription_item, iap_cancellation: true)

        return GitHub::Billing::Result.success
      end

      # Use plan_subscription.lock_key to prevent other synchronizations while we cancel and refund
      restraint.lock!(plan_subscription.lock_key, 1, 5.minutes) do
        preview_result = T.let(nil, T.nilable(GitHub::Billing::Result))
        update_result = T.let(nil, T.nilable(GitHub::Billing::Result))

        with_write do
          # Synchronize before the cancellation to ensure that the post-cancellation synchronization
          # only cancels the subscription item and doesn't do anything else.
          plan_subscription.synchronize(attempts_per_exception: exception_executions,
            synchronization_id: sync_id(account, "before-cancellation"))

          subscription_item.cancel!(actor: User.staff_user, force: true, skip_sync: true)
          plan_subscription.reload

          # We need to run preview before sync otherwise we will not see what the the prorated invoice will look like
          preview_result = Billing::PlanSubscription::Synchronizer.preview(plan_subscription)
          update_result = plan_subscription.synchronize(attempts_per_exception: exception_executions, create_credit_balance: false,
            synchronization_id: sync_id(account, "after-cancellation"))
        end

        preview_result = T.must(preview_result)
        update_result = T.must(update_result)

        # Reload the subscription item so that our metrics and logging correctly reflect the state of the item.
        # Specifically, so the call to `subscription_item.cancelled?` is correct.
        subscription_item.reload

        # Zero out or issue a refund for the subscription item
        open_invoices = open_invoices_for_subscription_item(plan_subscription, subscription_item)
        result = if open_invoices.present?
          # It's possible, particularly during the invoice/payment run window for the user to have an open invoice
          # for the subscription item. This means they have not yet paid for the most recent billing cycle and no
          # refund would be available. In this case, the user is not entitled to a refund and we should not attempt
          # to refund them. Instead we zero out the invoice item to ensure they do not get charged an extra term.
          zero_out_subscription_item(open_invoices, subscription_item)
        else
          refund_subscription_item(preview_result, subscription_item)
        end

        # Raise an error if we encounter a known error that we should retry on
        if result.failed?
          if result.error_message.include?(INVOICE_DRAFT_STATUS_ERROR)
            raise InvoiceDraftStatusError
          end
        end

        result
      end
    rescue => error # rubocop:todo Lint/RescueException
      raise if error.class.in?(retryable_errors)

      GitHub.dogstats.increment(
        "billing.cancel_and_refund_subscription_item_job.failed",
        tags: ["error:#{error.class.name}"]
      )

      GitHub.logger.error(
        exception: error,
        "code.namespace": self.class.name,
        "gh.billing.subscription_item.id": subscription_item.id,
        "gh.billing.plan_subscription.id": plan_subscription&.id,
        "gh.org.id": organization_id
      )

      Failbot.report(error, { "gh.job.name" => CancelAndRefundSubscriptionItemJob.name })

      GitHub::Billing::Result.failure(error.message)
    end

    private

    sig do
      params(
        invoice_items: T::Array[Billing::Zuora::InvoiceItem],
        subscription_item: ::Billing::SubscriptionItem
      ).returns(T::Array[Billing::Zuora::InvoiceItem])
    end
    def invoice_items_for_subscription_item(invoice_items, subscription_item)
      invoice_items.select do |item|
        subscription_item.subscribable.matches_invoice_item?(item) && item.charge_amount.positive?
      end
    end

    sig do
      params(
        plan_subscription: ::Billing::PlanSubscription,
        subscription_item: ::Billing::SubscriptionItem
      ).returns(T::Array[Billing::Zuora::Invoice])
    end
    def open_invoices_for_subscription_item(plan_subscription, subscription_item)
      invoices = Billing::Zuora::Invoice.open_invoices_for_account(plan_subscription.zuora_account_id)
      invoices.select do |invoice|
        invoice_items_for_subscription_item(invoice.invoice_items, subscription_item).any?
      end
    end

    sig do
      params(
        invoices: T::Array[Billing::Zuora::Invoice],
        subscription_item: ::Billing::SubscriptionItem
      ).returns(GitHub::Billing::Result)
    end
    def zero_out_subscription_item(invoices, subscription_item)
      # Keep track of how much we're zeroing out
      zero_out_amount = Billing::Money.zero

      # Create the invoice adjustments to zero them out
      adjustments = invoices.flat_map do |invoice|
        # The invoice balance represents our maximum possible adjustment amount
        remaining_balance = Billing::Money.parse(invoice.balance)
        next unless remaining_balance.positive?

        # Find the invoice and taxation items
        invoice_items = invoice_items_for_subscription_item(invoice.invoice_items, subscription_item)
        taxation_items = invoice_items.flat_map(&:taxation_items).select { |item| item.tax_amount.positive? }
        items_to_zero_out = invoice_items + taxation_items

        # Create adjustments for each invoice and taxation item
        invoice_item_adjustments = []
        items_to_zero_out.each do |item|
          break if remaining_balance.zero?

          adjustment_amount = [item.amount, remaining_balance].min
          remaining_balance -= adjustment_amount
          zero_out_amount += adjustment_amount

          invoice_item_adjustments << Billing::Zuora::InvoiceItemAdjustmentBuilder.adjustment_for(
            amount: -adjustment_amount.dollars,
            invoice_id: invoice.id,
            item_id: item.id,
            is_tax_item: item.is_a?(Billing::Zuora::TaxationItem)
          )
        end

        invoice_item_adjustments
      end

      zero_out_result = if adjustments.empty?
        # This should never happen since prior to calling this method, we should have already determined that
        # there are invoice items that need to be adjusted and those invoice items should be cached. Just to
        # be safe and to make our logging and instrumentation clearer, we return a failure immediately.
        GitHub::Billing::Result.failure("No matching invoice items to zero out")
      else
        response = GitHub.zuorest_client.create_action(objects: adjustments, type: "InvoiceItemAdjustment")
        results = response.map { |r| GitHub::Billing::Result.from_zuora(r) }

        # Combine the results into a single result
        result = if results.all?(&:success?)
          GitHub::Billing::Result.success
        else
          error = results.select(&:failed?).map(&:error_message).join(";")
          GitHub::Billing::Result.failure(error)
        end
        result.batch_zuora_results = response
        result
      end
    rescue => error # rubocop:todo Lint/RescueException
      zero_out_result = GitHub::Billing::Result.failure(error.message)
      raise
    ensure
      instrument_cancel_and_refund(
        subscription_item: subscription_item,
        zero_out_amount_in_cents: zero_out_amount.cents,
        zero_out_result: zero_out_result
      )

      log_zero_out(
        subscription_item: subscription_item,
        invoices: invoices,
        adjustments: adjustments,
        zero_out_amount_in_cents: zero_out_amount.cents,
        zero_out_result: zero_out_result
      )
    end

    sig do
      params(
        preview_result: GitHub::Billing::Result,
        subscription_item: ::Billing::SubscriptionItem,
        attempts: Integer
      ).returns(GitHub::Billing::Result)
    end
    def refund_subscription_item(preview_result, subscription_item, attempts: 0)
      attempts += 1

      # Get the refund invoice item
      refund_invoice_item = matching_invoice_item_from_preview(preview_result, subscription_item)

      # Find the matching billing transaction
      service_start = refund_invoice_item.present? ? Date.parse(refund_invoice_item.service_start_date) : GitHub::Billing.today
      billing_transaction = subscription_item.active_billing_transaction(start_date: service_start)
      refund_invoice = matching_invoice_from_transaction(billing_transaction, subscription_item)

      # Determine the refund amount
      if full_refund && billing_transaction.present?
        line_item = billing_transaction.paid_line_items.find { |line_item| line_item.subscribable_id == subscription_item.subscribable_id }
        refund_amount = line_item.total_amount if line_item
      else
        refund_amount = (refund_invoice_item.charge_amount + refund_invoice_item.tax_amount).abs if refund_invoice_item
      end

      # Adjust the refund amount as needed to ensure we don't try to refund more than the invoice payment amount.
      # This can happen if the invoice was partially paid off with adjustments or a credit balance.
      if refund_amount.present? && refund_invoice.present?
        max_refund_amount = Billing::Money.parse(refund_invoice.payment_amount)
        refund_amount = [refund_amount, max_refund_amount].min
      end

      refund_result = if billing_transaction.blank?
        GitHub::Billing::Result.failure("No billing transaction available to refund, skipping")
      elsif !billing_transaction.refundable?
        GitHub::Billing::Result.failure("Billing transaction is not refundable, skipping")
      elsif refund_amount.blank?
        GitHub::Billing::Result.failure("No prorated refund amount. Perhaps failed preview or no matching invoice item")
      else
        refund_data = { refund_invoice.invoice_id => refund_amount } if refund_invoice.present?
        with_write { billing_transaction.refund!(refund_amount.cents, skip_email: true, refund_invoice_payment_data: refund_data) }
      end
    rescue => error # rubocop:todo Lint/RescueException
      # When issuing a refund, we extract the refund data from the `preview_result`. If the refund fails and we retry
      # the job, the new `preview_result` will no longer contain the refund data. To avoid losing the refund data, we
      # attempt retries on the refund method itself instead of at the job level.
      if error.class.in?(retryable_errors) && attempts < MAX_REFUND_ATTEMPTS
        # When we retry here, the `ensure` block is not called, so we have explicit metrics to track the retries
        GitHub.dogstats.increment(
          "billing.cancel_and_refund_subscription_item_job.refund.retry",
          tags: dogstats_tags(subscription_item) + ["error:#{error.class.name}"]
        )
        sleep(2**attempts)
        retry
      elsif attempts == MAX_REFUND_ATTEMPTS
        refund_result = GitHub::Billing::Result.failure("Exhausted refund attempts")
        raise RefundAttemptsExhaustedError
      else
        refund_result = GitHub::Billing::Result.failure(error.message)
        raise
      end
    ensure
      instrument_cancel_and_refund(
        subscription_item: subscription_item,
        billing_transaction: billing_transaction,
        refund_amount_in_cents: refund_amount&.cents,
        refund_result: refund_result
      )

      log_refund(
        preview_result: preview_result,
        subscription_item: subscription_item,
        billing_transaction: billing_transaction,
        refund_amount_in_cents: refund_amount&.cents,
        refund_invoice: refund_invoice,
        refund_result: refund_result,
        attempts: attempts,
      )
    end

    sig do
      params(
        preview_result: GitHub::Billing::Result,
        subscription_item: ::Billing::SubscriptionItem
      ).returns(T.nilable(Billing::Zuora::InvoiceItem))
    end
    def matching_invoice_item_from_preview(preview_result, subscription_item)
      return if preview_result.failed? || preview_result.batch_zuora_results.nil?

      invoice_items = T.let(
        preview_result.batch_zuora_results
          .select { |result| result["totalDeltaMrr"].negative? }
          .flat_map { |result| result["invoice"]["invoiceItems"] }
          .map { |item| Billing::Zuora::InvoiceItem.new(item) },
        T::Array[Billing::Zuora::InvoiceItem]
      )

      negative_matching_invoice_items = invoice_items
        .select { |item| item.charge_amount.negative? }
        # Ensure subscribable for item matches the negative invoice item
        .select { |item| item.product_name.include?(subscription_item.subscribable.name) }
        .sort_by(&:service_start_date)

      report_invalid_negative_invoice_items(
        negative_matching_invoice_items,
        product_key: subscription_item.subscribable.product_key,
        product_type: subscription_item.subscribable.product_type
      )

      negative_matching_invoice_items.last
    end

    sig do
      params(
        billing_transaction: T.nilable(Billing::BillingTransaction),
        subscription_item: ::Billing::SubscriptionItem
      ).returns(T.nilable(Billing::Zuora::Invoice))
    end
    def matching_invoice_from_transaction(billing_transaction, subscription_item)
      return if billing_transaction.nil?
      platform_transaction_id = billing_transaction.platform_transaction_id
      return if platform_transaction_id.blank?

      zuora_invoices = Billing::Zuora::Invoice.invoices_for_transaction(platform_transaction_id)
      return if zuora_invoices.empty?
      return T.must(zuora_invoices.first) if zuora_invoices.size == 1

      subscription_item_invoice = zuora_invoices.find do |invoice|
        invoice.invoice_items.any? do |item|
          subscription_item.subscribable.matches_invoice_item?(item)
        end
      end

      subscription_item_invoice
    end

    sig { params(subscription_item: ::Billing::SubscriptionItem).void }
    def log_on_free_trial(subscription_item)
      GitHub.dogstats.increment(
        "billing.cancel_and_refund_subscription_item_job.on_free_trial",
        tags: dogstats_tags(subscription_item)
      )

      GitHub.logger.info(
        logger_fields(subscription_item).merge(
          "code.function" => "log_on_free_trial",
        )
      )
    end

    sig do
      params(
        subscription_item: ::Billing::SubscriptionItem,
        invoices: T::Array[Billing::Zuora::Invoice],
        adjustments: T.nilable(T::Array[T.untyped]),
        zero_out_amount_in_cents: T.nilable(Integer),
        zero_out_result: GitHub::Billing::Result
      ).void
    end
    def log_zero_out(subscription_item:, invoices:, adjustments:, zero_out_amount_in_cents:, zero_out_result:)
      GitHub.dogstats.increment(
        "billing.cancel_and_refund_subscription_item_job.zero_out",
        tags: dogstats_tags(subscription_item) + ["zero_out_result_success:#{zero_out_result.success?}"]
      )

      GitHub.logger.info(
        logger_fields(subscription_item).merge(
          "code.function" => "log_zero_out",
          "gh.billing.zuora.invoice.ids" => invoices.map(&:id).join(","),
          "gh.billing.zuora.invoice.balances" => invoices.map(&:balance).join(","),
          "gh.billing.zuora.invoice_item_adjustments.inspect" => adjustments.inspect,
          "gh.billing.zero_out_amount_in_cents" => zero_out_amount_in_cents,
          "gh.billing.zero_out_result.success" => zero_out_result.success?,
          "gh.billing.zero_out_result.inspect" => zero_out_result.inspect,
        )
      )
    end

    sig do
      params(
        preview_result: GitHub::Billing::Result,
        subscription_item: ::Billing::SubscriptionItem,
        billing_transaction: T.nilable(Billing::BillingTransaction),
        refund_amount_in_cents: T.nilable(Integer),
        refund_invoice: T.nilable(Billing::Zuora::Invoice),
        refund_result: GitHub::Billing::Result,
        attempts: Integer,
      ).void
    end
    def log_refund(preview_result:, subscription_item:, billing_transaction:, refund_amount_in_cents:, refund_invoice:, refund_result:, attempts:)
      GitHub.dogstats.increment(
        "billing.cancel_and_refund_subscription_item_job.refund",
        tags: dogstats_tags(subscription_item) + [
          "full_refund:#{full_refund.present?}",
          "preview_result_success:#{preview_result.success?}",
          "refund_result_success:#{refund_result.success?}",
          "refund_amount_present:#{refund_amount_in_cents.present?}",
          "refund_invoice_present:#{refund_invoice.present?}"
        ]
      )

      GitHub.logger.info(
        logger_fields(subscription_item).merge(
          "code.function" => "log_refund",
          "gh.billing.preview_result.success" => preview_result.success?,
          "gh.billing.preview_result.inspect" => preview_result.inspect,
          "gh.billing.refund_result.success" => refund_result.success?,
          "gh.billing.refund_result.inspect" => refund_result.inspect,
          "gh.billing.billing_transaction.present" => billing_transaction.present?,
          "gh.billing.billing_transaction.inspect" => billing_transaction.inspect,
          "gh.billing.full_refund" => full_refund.present?,
          "gh.billing.refund_amount_in_cents" => refund_amount_in_cents,
          "gh.billing.refund_invoice.id" => refund_invoice&.invoice_id,
          "gh.billing.refund_invoice.amount" => refund_invoice&.amount,
          "gh.billing.refund_attempts" => attempts,
        )
      )
    end

    sig { params(subscription_item: ::Billing::SubscriptionItem).returns(T::Array[String]) }
    def dogstats_tags(subscription_item)
      [
        "product_key:#{subscription_item.subscribable.product_key}",
        "product_type:#{subscription_item.subscribable.product_type}",
      ]
    end

    sig { params(subscription_item: ::Billing::SubscriptionItem).returns(T::Hash[String, T.untyped]) }
    def logger_fields(subscription_item)
      plan_subscription = T.must(subscription_item.plan_subscription)
      {
        "code.namespace" => self.class.name,
        "gh.catalog_service" => "github/account_management",
        "gh.billing.product_uuid.product_key" => subscription_item.subscribable.product_key,
        "gh.billing.product_uuid.product_type" => subscription_item.subscribable.product_type,
        "gh.billing.subscription_item.id" => subscription_item.id,
        "gh.billing.subscription_item.cancelled" => subscription_item.cancelled?,
        "gh.billing.plan_subscription.id" => plan_subscription.id,
        "gh.user.id" => plan_subscription.user_id,
        "gh.billing.customer.id" => plan_subscription.customer_id,
      }
    end

    sig { params(negative_invoice_items: T::Array[Billing::Zuora::InvoiceItem], product_key: String, product_type: String).void }
    def report_invalid_negative_invoice_items(negative_invoice_items, product_key:, product_type:)
      return if negative_invoice_items.count == 1

      if negative_invoice_items.size > 1
        GitHub.dogstats.count(
          "billing.cancel_and_refund_subscription_item_job.multiple_negative_invoice_items",
          negative_invoice_items.size,
          tags: [
            "product_key:#{product_key}",
            "product_type:#{product_type}"
          ]
        )
      elsif negative_invoice_items.size == 0
        GitHub.dogstats.increment(
          "billing.cancel_and_refund_subscription_item_job.no_negative_invoice_items",
          tags: [
            "product_key:#{product_key}",
            "product_type:#{product_type}"
          ]
        )
      end
    end

    sig do
      params(
        subscription_item: ::Billing::SubscriptionItem,
        billing_transaction: T.nilable(Billing::BillingTransaction),
        refund_amount_in_cents: T.nilable(Integer),
        refund_result: T.nilable(GitHub::Billing::Result),
        zero_out_amount_in_cents: T.nilable(Integer),
        zero_out_result: T.nilable(GitHub::Billing::Result),
        trial_user: T::Boolean,
        iap_cancellation: T::Boolean
      ).void
    end
    def instrument_cancel_and_refund(subscription_item:, billing_transaction: nil, refund_amount_in_cents: nil, refund_result: nil, zero_out_amount_in_cents: nil, zero_out_result: nil, trial_user: false, iap_cancellation: false)
      plan_subscription = T.must(subscription_item.plan_subscription)
      GitHub.instrument "billing.subscription_item_cancel_and_refund", {
        user_id: plan_subscription.user_id,
        customer_id: plan_subscription.customer_id,
        organization_id: organization_id,
        subscription_item_id: subscription_item.id,
        product_key: subscription_item.subscribable.product_key,
        product_type: subscription_item.subscribable.product_type,
        cancelled: subscription_item.cancelled?,
        payment_type: billing_transaction&.payment_type,
        sale_transaction_id: billing_transaction&.sale_transaction_id,
        sale_date: billing_transaction&.date,
        full_refund: full_refund.present?,
        refund_amount_in_cents: refund_amount_in_cents,
        refunded_at: refund_result.present? ? Time.zone.now : nil,
        refund_success: refund_result&.success?,
        refund_result: refund_result.to_s,
        zero_out_amount_in_cents: zero_out_amount_in_cents,
        zero_out_success: zero_out_result&.success?,
        zero_out_result: zero_out_result.to_s,
        trial_user: trial_user,
        iap_cancellation: iap_cancellation
      }
    end

    sig { returns(GitHub::Restraint) }
    def restraint
      @restraint ||= T.let(GitHub::Restraint.new, T.nilable(GitHub::Restraint))
    end

    sig { returns(T::Array[T.class_of(StandardError)]) }
    def retryable_errors
      ::Billing::PlanSubscription::SynchronizationEvents::RETRYABLE_ERRORS +
        ::Billing::PlanSubscription::SynchronizationEvents::EXTRA_RETRYABLE_ERRORS +
        ::Billing::PlanSubscription::SynchronizationEvents::DELAYED_RETRYABLE_ERRORS +
        [Zuorest::TooManyRequestsError, InvoiceDraftStatusError]
    end

    sig { params(account: T.nilable(::Billing::Types::Account), label: String).returns(String) }
    def sync_id(account, label = "")
      if account.is_a?(Business)
        "#{account.slug}-cancel-and-refund-#{label}-#{Time.now.to_i}"
      else
        "#{account&.display_login}-cancel-and-refund-#{label}-#{Time.now.to_i}"
      end
    end
  end
end
