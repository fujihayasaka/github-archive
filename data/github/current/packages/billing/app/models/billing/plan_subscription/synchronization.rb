# typed: strict
# frozen_string_literal: true

module Billing
  module PlanSubscription::Synchronization
    extend T::Helpers

    include GitHub::Memoizer
    include ::Billing::PlanSubscription::SynchronizationEvents

    requires_ancestor { ::Billing::PlanSubscription }

    # Public: Returns true if this plan subscription has a pending synchronization
    sig { returns(T::Boolean) }
    def has_pending_subscription_sync?
      status = subscription_sync_status
      return false unless status.persisted?
      status.pending?
    end

    # Public: Queues up a SynchronizePlanSubscription job for the owner of this PlanSubscription.
    #
    # collect         - When non-nil, controls whether to collect payment for the subscription changes.
    #                   Subscription changes will not be applied if payment collection fails.
    # wait            - Enqueues the job with the specified delay
    # set_sync_status - When true, updates the SubscriptionSyncStatus to 'pending'.
    #
    sig { params(collect: T.nilable(T::Boolean), wait: T.untyped, set_sync_status: T::Boolean).void }
    def synchronize_later(collect: nil, wait: nil, set_sync_status: true)
      job_options = {
        plan_name: plan_name,
        purpose: purpose,
      }
      job_options[:collect] = collect unless collect.nil?
      job_options[:user_id] = user_id if billable_user?
      job_options[:business_id] = business.id if billable_business?

      job = wait.nil? ? SynchronizePlanSubscriptionJob : SynchronizePlanSubscriptionJob.set(wait: wait)

      GitHub.logger.info(
        "code.namespace" => self.class.name,
        "code.function" => __method__.to_s,
        "gh.billing.billable_entity.id" => billable_entity&.id,
        "gh.billing.billable_entity.type" => billable_entity.class,
        "gh.billing.plan_subscription.id" => self.id,
        "gh.billing.plan_subscription.purpose" => self.purpose,
        "gh.billing.synchronize_plan_subscription_job.collect" => job_options[:collect],
        "gh.billing.synchronize_plan_subscription_job.user_id" => job_options[:user_id],
        "gh.billing.synchronize_plan_subscription_job.business_id" => job_options[:business_id],
        "gh.billing.synchronize_plan_subscription_job.purpose" => job_options[:purpose],
        "gh.billing.synchronize_plan_subscription_job.wait" => wait.to_s,
        "gh.billing.synchronize_plan_subscription_job.caller" => caller_locations(1, 1)&.first&.to_s,
      )

      subscription_sync_pending! if set_sync_status

      if billable_user?
        job.perform_later(job_options, user: user)
      elsif billable_business?
        job.perform_later(job_options, business: business)
      end
    end

    # Internal: Synchronize pending plan changes to the associated external subscription for this PlanSubscription.
    #           Uses a lock to prevent concurrent changes to the subscription.
    #
    # Caution: If you are calling this method directly, you MUST manually handle retries and exceptions.
    #          Prefer using `synchronize_later` instead or call this method from a job.
    sig do
      params(
        set_billing_date_today: T::Boolean,
        attempts_per_exception: T::Hash[T.untyped, Integer],
        synchronization_id: String,
        collect: T.nilable(T::Boolean),
        apply_credit_balance: T.nilable(T::Boolean),
        create_credit_balance: T::Boolean,
        collect_async: T::Boolean,
      ).returns(GitHub::Billing::Result)
    end
    def synchronize_with_lock(set_billing_date_today: true, attempts_per_exception: {}, synchronization_id: sync_id,
      collect: nil, apply_credit_balance: nil, create_credit_balance: true, collect_async: true)
      with_lock do
        reload
        synchronize(
          set_billing_date_today:,
          attempts_per_exception:,
          synchronization_id:,
          collect:,
          apply_credit_balance:,
          create_credit_balance:,
          collect_async:
        )
      end
    end

    sig { params(block: T.proc.params(arg0: T.untyped).void).returns(T.untyped) }
    def with_lock(&block)
      restraint.lock!(lock_key, _n = 1, _ttl = 3.minutes, &block)
    end

    # Internal: Synchronize pending plan changes to the associated external subscription for this PlanSubscription.
    #
    # Caution: If you are calling this method directly, you MUST manually obtain a lock first AND
    #          handle retries and exceptions. Prefer using `synchronize_with_lock` or `synchronize_later` instead.
    #
    # set_billing_date_today - When true, sets the bill date to today if creating a new subscription.
    # attempts_per_exception - The number of past attempts that have been made for each exception occurred.
    #                          Jobs triggering a synchronization should be passing in `exception_executions`.
    # synchronization_id     - A unique identifier for this synchronization, used for tracking purposes.
    # collect                - When non-nil, controls whether to collect payment for the subscription changes.
    #                          Subscription changes will not be applied if payment collection fails.
    # apply_credit_balance   - When non-nil, controls whether to apply the credit balance to the invoice.
    #
    # Post-synchronization actions:
    # create_credit_balance  - Creates a credit balance from any negative invoices that are generated from the sync. Defaults to true.
    # collect_async          - Attempts collection on invoices generated from the synchronization. Defaults to true.
    #                          When `collect` is non-nil, this flag is ignored and treated as false.
    #
    sig do
      params(
        set_billing_date_today: T::Boolean,
        attempts_per_exception: T::Hash[T.untyped, Integer],
        synchronization_id: String,
        collect: T.nilable(T::Boolean),
        apply_credit_balance: T.nilable(T::Boolean),
        create_credit_balance: T::Boolean,
        collect_async: T::Boolean,
      ).returns(GitHub::Billing::Result)
    end
    def synchronize(set_billing_date_today: true, attempts_per_exception: {}, synchronization_id: sync_id,
      collect: nil, apply_credit_balance: nil, create_credit_balance: true, collect_async: true)
      T.bind(self, ::Billing::PlanSubscription)

      # Keep track of what action we're performing on the subscription for logging and metrics
      action = "none"

      # Do not collect asynchronously if the caller has explicitly requested synchronous collection (collect: true)
      # or if the caller has explicitly opted out of collection (collect: false)
      collect_async = false if !collect.nil?

      GitHub.logger.with_named_tags(log_context.merge("gh.billing.synchronization_id": synchronization_id)) do
        begin
          result = should_synchronize
          if result.failed?
            event = SynchronizationSkippedEvent.new(action: action, result: result, attempts_per_exception: attempts_per_exception)
            track_synchronization_event(synchronization_id: synchronization_id, event: event, collect: collect)
            return result
          end

          attach_orphaned_zuora_subscription if !zuora_subscription_number?

          # Extra dogstats tags to include with synchronization metrics
          dogstats_tags = []
          if attempts_per_exception.any? { |k, _| k.include?(Zuorest::GatewayTimeoutError.to_s) }
            dogstats_tags << "previous_error:gateway_timeout_error"
          end

          result =
            if has_external_subscription?
              if should_cancel_subscription?
                action = "cancel"
                PlanSubscription::Synchronizer.cancel(self, synchronization_id: synchronization_id, collect: collect, apply_credit_balance: apply_credit_balance, dogstats_tags: dogstats_tags)
              else
                action = "update"
                collect_async = false unless should_collect_async_on_subscription_update? # todo: should we remove this?

                run_billing = true
                if should_generate_billing_documents?
                  run_billing = false
                  collect_async = true
                end

                PlanSubscription::Synchronizer.update(self, synchronization_id: synchronization_id, collect: collect, apply_credit_balance: apply_credit_balance, dogstats_tags: dogstats_tags, run_billing: run_billing)
              end
            elsif should_create_subscription?
              action = "create"
              create_credit_balance = false # because negative invoices are never generated when creating a subscription
              PlanSubscription::Synchronizer.create(self, set_billing_date_today, synchronization_id: synchronization_id, collect: collect, apply_credit_balance: apply_credit_balance, dogstats_tags: dogstats_tags)
            else
              GitHub::Billing::Result.success
            end
        rescue => error # rubocop:todo Lint/RescueException
          track_synchronization_event(synchronization_id: synchronization_id, event: SynchronizationErrorEvent.new(action: action, error: error, attempts_per_exception: attempts_per_exception), collect: collect)
          raise
        end

        result_event = SynchronizationResultEvent.new(action: action, result: result, attempts_per_exception: attempts_per_exception)
        track_synchronization_event(synchronization_id: synchronization_id, event: result_event, collect: collect)

        # When there's an error associated with the event, raise it to allow the job to retry if possible
        error = result_event.error
        if error
          # Trigger handlers for the error before raising it
          if error.class == Billing::Zuora::SubscriptionCancelledError
            handle_subscription_cancelled
          end
          raise error
        end

        # Post-synchronization actions
        if result_event.success?
          invoice_ids = should_generate_billing_documents? ? generate_billing_documents_invoices : result_event.invoice_ids

          # Process invoices that are generated from the synchronization
          if invoice_ids.any?
            invoice_ids.each do |invoice_id|
              Billing::Zuora::TransferCreditBalanceFromNegativeInvoiceJob.perform_later(
                invoice_id: invoice_id,
                billable_entity: T.must(billable_entity),
              ) if create_credit_balance
              CollectZuoraInvoiceJob.perform_later(
                customer&.zuora_account_id.to_s,
                invoice_id
              ) if collect_async
            end
          elsif action != "none"
            # Note: The TransferCreditBalanceFromNegativeInvoiceJob will update the balance from Zuora
            # if an invoice exists / is generated, but if there is no invoice the update is handled here
            update_balance_from_zuora(origin: "Billing::PlanSubscription::Synchronization")

            # For users and organizations that have reached the end of dunning and do not owe us anything, we
            # reset billing on their account to ensure they can continue to use all features included with the
            # free plan without intervention. Businesses are excluded because they do not have a valid free plan.
            if user&.can_reset_billing?(has_balance: balance_in_cents.positive?)
              T.must(user).reset_billing
            end
          end

          # Only if we changed the user's general-purpose subscription could their plan have been affected.
          # If a Sponsors-specific subscription was changed, their GitHub plan would be unchanged, so no need
          # to assess which features their plan controls, nor would metered line items be impacted.
          if general_purpose?
            user&.remove_gated_features

            if action == "create" || action == "cancel"
              Billing::UpdateCustomerInBillingPlatformJob.perform_later(T.must(customer))
            end
          end
        end

        result
      end
    end

    # Internal: The lock key used to prevent simultaneous updates
    sig { returns(String) }
    memoize def lock_key
      billable_entity_id = billable_user? ? "user-#{user_id}" : "business-#{business.id}"
      "#{billable_entity_id}-synchronization"
    end

    # Internal: Returns the latest SubscriptionSyncStatus for this PlanSubscription or a new one if none exist.
    sig { params(cleanup_duplicates: T::Boolean).returns(Billing::SubscriptionSyncStatus) }
    def subscription_sync_status(cleanup_duplicates: false)
      statuses = Billing::SubscriptionSyncStatus.where(plan_subscription: self).order(updated_at: :desc)

      if statuses.size > 1
        GitHub.dogstats.increment("billing.plan_subscription.duplicate_subscription_sync_status", tags: ["count:#{statuses.size}"])
        if cleanup_duplicates && FeatureFlag.vexi.enabled?(:billing_clean_up_duplicate_subscription_sync_status, default: false)
          statuses.offset(1).destroy_all
        end
      end

      statuses.first || Billing::SubscriptionSyncStatus.new(plan_subscription: self, target: self.billable_entity)
    end

    # Internal: Marks the subscription sync status as pending for the PlanSubscription.
    sig { void }
    def subscription_sync_pending!
      return unless FeatureFlag.vexi.enabled?(:billing_set_subscription_sync_status_to_pending, default: false)
      Billing::SubscriptionSyncStatus.with_write do
        status = subscription_sync_status(cleanup_duplicates: true)
        status.external_sync_status = :pending
        status.number_of_retries_remaining = 0
        status.target = self.billable_entity
        status.save
      end
    end

    private

    # Internal: Determines if we should be synchronizing this plan subscription.
    sig { returns(GitHub::Billing::Result) }
    def should_synchronize
      return GitHub::Billing::Result.failure("billable entity must be present") unless billable_entity = self.billable_entity
      return GitHub::Billing::Result.failure("billable entity is suspended") if billable_entity.suspended?
      return GitHub::Billing::Result.failure("billable entity is invoiced") if billable_entity.invoiced? && general_purpose_customer?
      return GitHub::Billing::Result.failure("billable entity has trade restrictions") if billable_entity.has_any_trade_restrictions?
      return GitHub::Billing::Result.failure("billable entity has commercial interaction restrictions") if billable_entity.has_commercial_interaction_restriction?

      # Billable user/business specific checks
      if billable_user?
        required_user = T.must(user)

        # Organization specific checks
        if required_user.organization?
          org = T.cast(required_user, Organization)

          # Soft-deleted accounts should not be synchronized
          return GitHub::Billing::Result.failure("organization is soft deleted") if org.soft_deleted?

          # Organizations that are a part of an enterprise account are billed through the enterprise
          return GitHub::Billing::Result.failure("organization is part of an enterprise account") if general_purpose_customer? && org.business.present?
        end

        # guards for plan subscription with ghost customer
        customer_for_plan_sub = sponsors_purpose? ? required_user.sponsors_customer : required_user.customer
        return GitHub::Billing::Result.failure("customer does not exist") unless customer || customer_for_plan_sub
        update customer: customer_for_plan_sub unless customer
      end

      return GitHub::Billing::Result.failure("customer does not have a Zuora account") unless zuora_user?
      return GitHub::Billing::Result.failure("customer does not have an active Zuora account") unless customer&.zuora_account_active?

      GitHub::Billing::Result.success
    end

    # Internal: Whether or not we should cancel the subscription if one exists
    #          This is true if the user has no valid payment method and the subscription is cancellable,
    #          or if the subscription is Sponsors-specific and tied to a general-purpose Customer while the billable
    #          entity has a Sponsors-specific Customer.
    sig { returns(T::Boolean) }
    def should_cancel_subscription?
      # Sponsors-invoiced plan subscriptions should only be updated
      return false if sponsors_invoiced?
      # Enterprise plan subscriptions should only be updated
      return false unless billable_user?

      # Billing locked accounts without any subscription-based charges should be cancelled since
      # it implies that their payment method is not valid and they cannot utilize metered services.
      return true if billable_entity&.disabled? && !active_non_metered_charges?

      # Do not cancel the subscription if we the account has products/services we need to bill for
      return false if active_charges?

      !has_valid_payment_method? || sponsors_subscription_on_wrong_customer?
    end

    # Internal: Checks if this subscription is for sponsorships only and it's tied to the general-purpose customer
    # record instead of the account's Sponsors-specific customer record.
    sig { returns(T::Boolean) }
    def sponsors_subscription_on_wrong_customer?
      sponsors_purpose? && # is this subscription for sponsorships only...
        general_purpose_customer? && # and is it tied to the non-sponsorship customer...
        billable_entity&.sponsors_customer.present? # and a sponsorship-specific customer exists
    end

    # Internal: Whether or not we should create a new subscription if one doesn't exist
    sig { returns(T::Boolean) }
    def should_create_subscription?
      # Do not create a new subscription for users that we know will be unable to pay their invoices.
      # Having open invoices that will never be paid is undesired since it affects revenue reporting.
      if billable_entity&.disabled?
        # No payment method means they can't pay
        return false if !has_valid_payment_method?
        # A payment method that has failed too many times means we won't try to charge them anymore
        return false if external_payment_method_consecutive_failures >= billable_entity&.billing_attempts_limit
        # We cancel subscriptions when accounts are billing-locked with no subscription-based charges,
        # so we should not create a new subscription to avoid flip-flopping.
        return false if !active_non_metered_charges?
      end

      # If a valid payment method is present, metered usage can be incurred so we need a subscription.
      # We also assume that a billing address has been saved in Zuora (though not necessarily in dotcom).
      return true if has_valid_payment_method?

      # A subscription is needed for users with an IAP subscription in order to track their billing
      return true if apple_iap_subscription?

      # Do not create new general purpose subscriptions if we don't have billing address.
      # A billing address is required to generate invoices with the correct taxable amounts.
      #
      # Exceptions:
      # - Sponsors purpose: Sponsors is not taxed so a billing address is not required.
      # - Apple IAP subscriptions: These are not billed through Zuora.
      if general_purpose?
        return false unless customer&.contact_for_tax&.persisted?
      end

      # If the account has paid product/services, we need a subscription.
      payment_amount > 0
    end

    # Internal: When updating the plan subscription, an invoice may be generated. Method decides if we should queue a job to
    # attempt to collect this invoice. Currently used by business accounts in any of the "checkout" flows, where a
    # payment success/failure response is needed as soon as possible.
    sig { returns(T::Boolean) }
    def should_collect_async_on_subscription_update?
      return false unless billable_business?
      business.trial_conversion_initiated? || business.organization_upgrade_purchase_initiated? || business.creation_from_coupon_purchase_initiated?
    end

    # Internal: Check to validate if the invoice generation should be created via billing documents instead.
    # This can be removed once we have Zuora subscriptions specific for metered charges (charges can happen separately).
    sig { returns(T::Boolean) }
    memoize def should_generate_billing_documents?
      return false unless billable_business?
      return false unless customer&.present?
      return false unless general_purpose?
      true
    end

    # Internal: Generate billing documents (invoices and credit memos) for the updated subscription excluding
    # metered charges, since they are scheduled to be billed on the customer's bill cycle day.
    # Returns the invoice ids of the billing documents were successfully generated.
    sig { returns(T::Array[String]) }
    def generate_billing_documents_invoices
      zuora_account_number = T.must(customer).zuora_account_number
      billing_documents_result = Billing::Zuora::Account.generate_billing_documents(zuora_account_number,
        zuora_subscription_id, [Billing::Zuora::Account::BILLING_DOCUMENTS_CHARGE_TYPE_TO_EXCLUDE[:usage]])
      return [] unless billing_documents_result

      GitHub.logger.info(
        "code.function" => "generate_billing_documents",
        "gh.billing.zuora.account_number" => zuora_account_number,
        "gh.billing.zuora.subscription_id" => zuora_subscription_id,
        "gh.billing.zuora.response" => billing_documents_result.zuora_result,
        "gh.billing.zuora.response.success" => billing_documents_result.success?,
      )

      if billing_documents_result.success? && billing_documents_result.zuora_result["invoices"].any?
        billing_documents_result.zuora_result["invoices"].map { |invoice| invoice["id"] }
      else
        []
      end
    end

    # Internal: Tracks the given synchronization event by creating an audit log entry,
    #           incrementing dogstats metrics, and logging useful data.
    #
    # synchronization_id - The synchronization id to include in the audit log entry.
    # event              - The SynchronizationEvent used to update the subscription sync status.
    # collect            - Whether or not we attempted to collect payment during the synchronization.
    #
    sig { params(synchronization_id: String, event: SynchronizationEvent, collect: T.nilable(T::Boolean)).void }
    def track_synchronization_event(synchronization_id:, event:, collect:)
      # Add an entry to the audit log
      if billable_entity = self.billable_entity
        event_attrs = event.attributes.merge(
          success: event.success?,
          external_subscription_type: sync_platform_type,
          plan: billable_entity.plan.name,
          seats: billable_entity.seats,
          collect: collect,
          synchronization_id: synchronization_id,
        )
        event_attrs[:zuora_subscription_number] = zuora_subscription_number if zuora_subscription_number?
        instrument(:synchronize, **event_attrs)
      end

      # Increment the some dogstats metrics
      GitHub.dogstats.increment("billing.plan_subscription.synchronize", {
        tags: ["success:#{event.success?}", "action:#{event.action}", "error:#{event.error.class.name}", "slo:#{event.slo?}"],
      })

      # Log the event
      GitHub.logger.info(
        "code.namespace" => self.class.name,
        "code.function" => "synchronize",
        "gh.billing.plan_subscription.balance_in_cents" => balance_in_cents,
        "gh.billing.synchronization.action" => event.action,
        "gh.billing.synchronization.error" => event.error,
        "gh.billing.synchronization.slo" => event.slo?,
        "gh.billing.synchronization.success" => event.success?,
        "gh.billing.synchronization_event" => event.inspect
      )

      # Update the associated SubscriptionSyncStatus
      update_subscription_sync(T.cast(self, ::Billing::PlanSubscription), event)
    end

    # Internal: Updates the subscription sync status for the PlanSubscription.
    #
    # plan_subscription - The plan subscription that the sync status is for
    # event             - The event generated from the synchronization attempt
    #
    sig { params(plan_subscription: ::Billing::PlanSubscription, event: SynchronizationEvent).void }
    def update_subscription_sync(plan_subscription, event)
      status = subscription_sync_status(cleanup_duplicates: true)
      if event.success?
        status.external_sync_status = :success
      elsif event.is_a?(SynchronizationSkippedEvent)
        # If the account should not be synchronized, we can remove the sync status record
        return status.destroy
      elsif event.declined?
        status.external_sync_status = :declined
      elsif event.final_attempt?
        status.external_sync_status = :failure
      else
        status.external_sync_status = :failed_but_retrying
      end
      status.number_of_retries_remaining = event.number_of_attempts_remaining
      status.save
    end

    # Internal: Handle the case where we are trying to amend a cancelled subscription.
    #
    # This usually happens because the past cancellation attempt partially succeeded and so Zuora
    # has cancelled the subscription, but we have not finalized the cancellation on our end. To
    # resolve this, we can run the cancellation again which will finish the cancellation process.
    #
    sig { void }
    def handle_subscription_cancelled
      ::Billing::CloseZuoraSubscription.perform(
        zuora_subscription_number: zuora_subscription_number,
        plan_subscription: T.cast(self, ::Billing::PlanSubscription),
      )
    end

    # Internal: The restraint for locking and preventing simultaneous updates
    #
    sig { returns(GitHub::Restraint) }
    memoize def restraint
      GitHub::Restraint.new
    end

    # Internal: The number of external payment method consecutive failures.
    sig { returns(Integer) }
    memoize def external_payment_method_consecutive_failures
      billable_entity&.payment_method&.external_payment_method_consecutive_failure_count&.to_i || 0
    end

    # Internal: The logging context for all log messages produced by this synchronization.
    sig { returns(T::Hash[String, String]) }
    memoize def log_context
      context = {
        "code.namespace" => self.class.name,
      }

      if billable_entity = self.billable_entity
        context.merge!({
          "gh.billing.billable_entity.billed_on" => billable_entity.billed_on,
          "gh.billing.billable_entity.billing_attempts" => billable_entity.billing_attempts,
          "gh.billing.billable_entity.id" => billable_entity.id,
          "gh.billing.billable_entity.login" => billable_entity.display_login,
          "gh.billing.billable_entity.type" => billable_entity.class.name,
        })
      end

      if customer = self.customer
        context.merge!({
          "gh.billing.customer.disabled_reasons" => customer.disabled_reasons.join(","),
          "gh.billing.customer.id" => customer.id,
          "gh.billing.customer.locked_at" => customer.locked_at,
          "gh.billing.customer.requires_manual_transactions" => customer.requires_manual_transactions?,
        })
      end

      context["gh.user.login"] = user&.login if billable_user?
      context["gh.business.slug"] = business.slug if billable_business?

      context
    end

    # Internal: The default synchronization id to add to log messages for a given synchronization run.
    sig { returns(String) }
    memoize def sync_id
      display_login = billable_entity&.display_login || "unknown"
      "#{display_login}-#{SecureRandom.uuid}"
    end
  end
end
