# typed: strict
# frozen_string_literal: true

module Billing
  class PlanSubscription::ZuoraSynchronizer < PlanSubscription::Synchronizer
    include GitHub::ServiceMapping
    include GitHub::Memoizer

    sig { override.returns(::Billing::PlanSubscription) }
    attr_reader :plan_subscription

    sig { returns(T.nilable(T::Hash[String, T.untyped])) }
    attr_reader :zuora_response

    DECLINED_MESSAGE = "Your payment method has been declined."
    FAILURE_MESSAGE  = "There was an issue processing your payment method."
    ALREADY_CANCELED = /Only activated subscription can be cancelled\./

    ZUORA_VERSION_HEADER = T.let({ "zuora-version" => "211.0" }.freeze, T::Hash[String, String])

    ZUORA_UPDATE_LIMIT = 9

    delegate \
      :plan,
      :user,
      :business,
      :billable_entity,
      :billable_user?,
      :billable_business?,
      :zuora_params,
      :zuora_subscription,
      :zuora_subscription_number,
      to: :plan_subscription

    delegate \
      :cancel_params,
      :create_params,
      :rate_plans,
      :update_params,
      to: :zuora_params

    sig do
      params(
        plan_subscription: Billing::PlanSubscription,
        set_billing_date_today: T::Boolean,
        synchronization_id: T.nilable(String),
        collect: T.nilable(T::Boolean),
        apply_credit_balance: T.nilable(T::Boolean),
        dogstats_tags: T::Array[String],
        run_billing: T::Boolean
      ).void
    end
    def initialize(
      plan_subscription,
      set_billing_date_today = true,
      synchronization_id: nil,
      collect: nil,
      apply_credit_balance: nil,
      dogstats_tags: [],
      run_billing: true
    )
      @plan_subscription = plan_subscription
      @set_billing_date_today = set_billing_date_today
      @synchronization_id = synchronization_id
      @collect = collect
      @apply_credit_balance = apply_credit_balance
      @dogstats_tags = dogstats_tags
      @run_billing = run_billing
      @subscription_sync_status = T.let(track_subscription_sync(plan_subscription), Billing::SubscriptionSyncStatus)
      @zuora_response = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
    end

    # Public: Create a new Zuora subscription
    #
    # Success: Stores the new zuora_subscription_number on the  plan subscription record
    # Failure: Increments billing attempts, enters the user into dunning, and sends failure notification
    sig { override.returns(GitHub::Billing::Result) }
    def create
      return GitHub::Billing::Result.failure("trade restricted user") if billable_entity.has_any_trade_restrictions?
      result = create_zuora_order
      if result.failed? && (result.declined? || subscription_sync_status.on_last_retry?)
        message = error_response_for(result.error_message)
        Billing::Zuora::BillableRollback.perform(plan_subscription, message)
      end

      result
    end

    # This method is used to preview the result of updating a subscription without actually making the changes. This
    # allows us to see what an invoice would look like if we were to make the changes.
    sig { override.returns(GitHub::Billing::Result) }
    def preview
      update_batches = batched_update_params

      update_results = update_batches.each_with_object(T.let([], T::Array[GitHub::Billing::Result])) do |batched_update, results|
        begin
          batched_update.merge!(preview: true, runBilling: false, collect: false)
          start = Time.now.to_f
          @zuora_response = GitHub.zuorest_client.update_subscription \
            plan_subscription.zuora_subscription_number,
            batched_update,
            ZUORA_VERSION_HEADER
          elapsed_ms = (Time.now.to_f - start) * 1_000
          result = GitHub::Billing::Result.from_zuora(@zuora_response)
          results << result
        rescue => error # rubocop:todo Lint/GenericRescue
          GitHub.dogstats.increment("zuora.zuorest.preview_subscription.exception", tags: ["error_class:#{error.class}"])
          raise
        end

        GitHub.dogstats.timing("zuora.zuorest.preview_subscription.timing", elapsed_ms, tags: [
          "success:#{result.success?}",
          "error_code:#{result.error_code}"
        ])
      end

      # rollup zuora results of all batches into a single result
      last_result = T.must(update_results.last)
      last_result.batch_zuora_results = update_results.map(&:zuora_result)
      last_result
    end

    sig { override.returns(GitHub::Billing::Result) }
    def update
      update_subscription
    end

    sig { override.returns(GitHub::Billing::Result) }
    def cancel
      result = cancel_zuora_subscription(zuora_subscription)

      if result.success? || already_canceled?(result)
        plan_subscription.cache_outstanding_balance
        plan_subscription.clear_external_subscription_references
        if plan_subscription.nil? || plan_subscription.general_purpose?
          # Only if we cancelled the user's general-purpose subscription could their plan have been affected.
          # If a Sponsors-specific subscription was cancelled, their GitHub plan would be unchanged, so no need
          # to assess which features their plan controls.
          user&.remove_gated_features
        end
        result = result.success? ? result : GitHub::Billing::Result.success
      end

      result
    end

    private

    sig { returns(::Billing::Zuora::Account) }
    def zuora_object_account
      T.must_because(customer.zuora_object_account) do
        "a customer is required for synchronization"
      end
    end

    sig { returns(T.nilable(String)) }
    attr_reader :synchronization_id

    sig { returns(Billing::SubscriptionSyncStatus) }
    attr_reader :subscription_sync_status

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :collect

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :apply_credit_balance

    sig { returns(T::Array[String]) }
    attr_reader :dogstats_tags

    sig { returns(T::Boolean) }
    attr_reader :run_billing

    sig { params(result: GitHub::Billing::Result).returns(T::Boolean) }
    def already_canceled?(result)
      result.failed? && result.error_message.match(ALREADY_CANCELED).present?
    end

    sig { params(zuora_subscription: T.nilable(::Billing::Zuora::Subscription)).returns(GitHub::Billing::Result) }
    def cancel_zuora_subscription(zuora_subscription)
      return GitHub::Billing::Result.success if zuora_subscription.nil? || zuora_subscription.cancelled?

      start = Time.now.to_f
      @zuora_response = zuora_subscription.cancel
      elapsed_ms = (Time.now.to_f - start) * 1_000

      GitHub.dogstats.timing("zuora.zuorest.cancel_subscription.timing", elapsed_ms, tags: [
        "success:#{@zuora_response["success"]}",
      ] + dogstats_tags)

      GitHub.logger.info(
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.billing.zuora.response" => @zuora_response,
        "gh.billing.zuora.success" => @zuora_response["success"],
        "gh.billing.synchronization_id" => synchronization_id
      )

      GitHub::Billing::Result.from_zuora(@zuora_response)
    end

    # Internal: Create a subscription through the zuora api
    # Stores the new zuora_subscription_number on the plan_subscription record
    sig { returns(GitHub::Billing::Result) }
    def create_zuora_order
      return GitHub::Billing::Result.success if rate_plans.empty?

      update_bill_cycle_day if @set_billing_date_today

      begin
        subscription_number = create_via_subscriptions_endpoint

        result = GitHub::Billing::Result.from_zuora(@zuora_response)
        update_plan_subscription!(subscription_number.to_s) if result.success?
        result
      rescue ::Faraday::TimeoutError
        plan_subscription.attach_orphaned_zuora_subscription
        raise
      end
    end

    # Internal: Add the zuora information to the plan_subscription
    sig { params(subscription_number: String).returns(T::Boolean) }
    def update_plan_subscription!(subscription_number)
      plan_subscription.zuora_subscription_number = subscription_number
      plan_subscription.save!
      plan_subscription.update_from_zuora_subscription
    end

    # Internal: create a subscription on zuora with the subscriptions endpoint
    sig { returns(T.nilable(String)) }
    def create_via_subscriptions_endpoint
      start = Time.now.to_f
      params = create_params
      params[:collect] = collect unless collect.nil?
      params[:applyCreditBalance] = apply_credit_balance unless apply_credit_balance.nil?
      params[:termStartDate] = term_start_date if term_start_date.present?

      @zuora_response = GitHub.zuorest_client.create_subscription params, ZUORA_VERSION_HEADER

      elapsed_ms = (Time.now.to_f - start) * 1_000
      GitHub.dogstats.timing("zuora.zuorest.create_subscription.timing", elapsed_ms, tags: [
        "collect:#{params[:collect]}",
        "success:#{@zuora_response["success"]}",
      ] + dogstats_tags)

      GitHub.logger.info(
        "code.namespace" => self.class.name,
        "code.function" => "create_via_subscriptions_endpoint",
        "gh.billing.zuora.params" => params,
        "gh.billing.zuora.response" => @zuora_response,
        "gh.billing.zuora.success" => @zuora_response["success"],
        "gh.billing.synchronization_id" => synchronization_id
      )

      if has_sponsors_plans?(params[:subscribeToRatePlans])
        GitHub.dogstats.increment("sponsors.zuora_subscription_update")
      end

      @zuora_response["subscriptionNumber"]
    end

    # Internal: whether any of the specified rate plans are sponsorship plans
    sig { params(rate_plans: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Boolean) }
    def has_sponsors_plans?(rate_plans)
      plan_ids = rate_plans.map { |plan| plan[:productRatePlanId] }
      Billing::ProductUUID.sponsors.for_zuora_product_rate_plan(plan_ids).exists?
    end

    sig { returns(::Customer) }
    memoize def customer
      T.must_because(plan_subscription.customer) do
        "A customer is required for synchronization"
      end
    end

    sig { void }
    def update_bill_cycle_day
      return unless customer.zuora?
      # When creating a subscription for a user with lapsed billing (i.e. they were a paying customer in the past)
      # we should set the bill cycle day to today. This allows the customer to pay in full instead of a prorated
      # amount based on their current bill cycle day. If billing hasn't lapsed, we avoid updating their bill cycle
      # day to preserve the expected proration.
      return if customer.plan_subscriptions.any? { |plan_sub| plan_sub.zuora_rate_plan_charges.present? }

      response = zuora_object_account.update!({
        BcdSettingOption: "ManualSet",
        BillCycleDay: GitHub::Billing.today.day,
      }).first
      result = GitHub::Billing::Result.from_zuora(response)
      if result.failed?
        Failbot.report(
          StandardError.new("Updating bill cycle day failed"),
          {
            :catalog_service => :zuora_integration,
            "gh.user.id" => user.id,
            "gh.billing.zuora.result.error_message" => result.error_message,
          }
        )
      else
        customer.update!(bill_cycle_day: GitHub::Billing.today.day) if customer.business
      end
    end

    sig { returns(GitHub::Billing::Result) }
    def update_subscription
      update_batches = batched_update_params
      last_batch = T.must(update_batches.last)
      last_batch[:collect] = collect unless collect.nil?
      last_batch[:applyCreditBalance] = apply_credit_balance unless apply_credit_balance.nil?

      unless run_billing
        last_batch[:runBilling] = false
        last_batch.except!(:applyCreditBalance, :collect)
      end

      # For tax purposes, we need to temporarily flag customers that are making updates to existing product
      # subscriptions outside of their bill cycle day. For example, adding additional seats.
      # See: https://github.com/github/billing-core/issues/599
      if has_updates_to_quantity? && customer.requires_sales_tax_workaround_for_updates? && !customer_bill_cycle_day_is_today?
        response = T.must(customer.zuora_account).update!(UpgradeCustomer__c: true)
        GitHub.logger.info(
          "Set UpgradeCustomer__c to true",
          "code.namespace" => self.class.name,
          "code.function" => "update_subscription",
          "gh.billing.synchronization_id" => synchronization_id,
          "gh.billing.zuora.response" => response,
        )
      end

      update_results = update_batches.each_with_object(T.let([], T::Array[GitHub::Billing::Result])) do |batched_update, results|
        begin
          start = Time.now.to_f
          @zuora_response = GitHub.zuorest_client.update_subscription \
            plan_subscription.zuora_subscription_number,
            batched_update, ZUORA_VERSION_HEADER
          elapsed_ms = (Time.now.to_f - start) * 1_000
          result = GitHub::Billing::Result.from_zuora(@zuora_response)
          results << result
        rescue => error # rubocop:todo Lint/GenericRescue
          report_update_exception(error, params: batched_update)
          raise
        end

        GitHub.dogstats.timing("zuora.zuorest.update_subscription.timing", elapsed_ms, tags: [
          "run_billing:#{batched_update[:runBilling]}",
          "collect:#{batched_update[:collect]}",
          "apply_credit_balance:#{batched_update[:applyCreditBalance]}",
          "success:#{result.success?}",
          "error_code:#{result.error_code}",
          "has_additions:#{batched_update[:add].any?}",
          "has_updates:#{batched_update[:update].any?}",
          "has_removals:#{batched_update[:remove].any?}"
        ] + dogstats_tags)

        GitHub.logger.info(
          "code.namespace" => self.class.name,
          "code.function" => "update_subscription",
          "gh.billing.zuora.params" => batched_update,
          "gh.billing.zuora.response" => @zuora_response,
          "gh.billing.zuora.response.success" => result.success?,
          "gh.billing.synchronization_id" => synchronization_id,
        )

        if result.success?
          plan_subscription.update_from_zuora_subscription
        else
          report_update_failure(result, partial_success: results.size > 1, params: batched_update)
          if result.declined? || subscription_sync_status.on_last_retry?
            Billing::Zuora::BillableRollback.perform(plan_subscription, error_response_for(result.error_message))
          end
          break results
        end
      end

      if update_batches.size > 1
        successful_batch_count = update_results.count(&:success?)
        GitHub.dogstats.increment("zuora.zuorest.update_subscription.batched_update",
          tags: ["batch_count:#{update_batches.size}", "batches_succeeded:#{successful_batch_count}"]
        )
      end

      updated_rate_plans = update_batches.map { |batch| batch[:add] + batch[:update] }.flatten
      if has_sponsors_plans?(updated_rate_plans)
        GitHub.dogstats.increment("sponsors.zuora_subscription_update")
      end

      last_result = T.must(update_results.last)

      # Store all batched updates for future reference
      last_result.batch_zuora_results = update_results.map(&:zuora_result)

      last_result
    end

    # Internal: Split update_params into groups of up to ZUORA_UPDATE_LIMIT changes so they can be
    # processed in batches smaller than the Zuora limit.
    #
    # Params must be ordered with adds first, then updates, then removes.
    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def batched_update_params
      # The original update_params hash includes key/value pairs that we need to batch:
      #   add:    [array of Hash of each new subscription]
      #   update: [array of Hash of each subscription being modified]
      #   remove: [array of Hash of each subscription being removed]
      orig_update_params = update_params

      # First build a flat array of all change Hashes in the correct order: adds, then
      # updates, then removes. Each item in this array is an Array of
      # [change_type, change_hash]
      ordered_changes  = orig_update_params[:add].map    { |change| [:add,    change] }
      ordered_changes += orig_update_params[:update].map { |change| [:update, change] }
      ordered_changes += orig_update_params[:remove].map { |change| [:remove, change] }

      # Shortcut if all the changes will fit in a single update request
      return [orig_update_params] if ordered_changes.size <= ZUORA_UPDATE_LIMIT

      # Params for each batch will be modified copies of the original - we'll be
      # building custom add/update/remove lists for each batch, and holding off
      # on running billing/collecting until the last batch.
      batch_update_params = orig_update_params.merge(
        add: [], update: [], remove: [], runBilling: false
      )

      # :applyCreditBalance and :collect cannot be included since runBilling is false.
      # We will only set these for the last batch.
      batch_update_params.except!(:applyCreditBalance, :collect)

      batched_changes = ordered_changes.each_slice(ZUORA_UPDATE_LIMIT).to_a
      update_batches = batched_changes.each_with_object([]) do |change_batch, batched_params|
        # Group the ordered changes by the change_type
        grouped_changes = change_batch.group_by(&:first)

        # Then set the add/update/remove values for this batch of changes - the
        # values will be the change_hash Hashes we used to build the Array of
        # ordered_changes.
        batched_params << batch_update_params.merge(
          add:    Array(grouped_changes[:add]).map(&:last),
          update: Array(grouped_changes[:update]).map(&:last),
          remove: Array(grouped_changes[:remove]).map(&:last)
        )
      end

      # Collect payment and create an invoice after the last batch of changes are applied,
      # to allow for charges and credits to balance each other out.
      update_batches.last[:applyCreditBalance] = orig_update_params[:applyCreditBalance]
      update_batches.last[:collect] = orig_update_params[:collect]
      update_batches.last[:runBilling] = true

      update_batches
    end

    sig { returns(T::Boolean) }
    memoize def customer_bill_cycle_day_is_today?
      customer.bill_cycle_day == GitHub::Billing.today.day
    end

    sig { returns(T::Boolean) }
    def has_updates_to_quantity?
      return false unless update_params[:update].any?

      update_params[:update].select do |update|
        update[:chargeUpdateDetails].select do |details|
          details[:quantity].present?
        end.any?
      end.any?
    end

    # Internal: Log exceptions that occur while updating subscriptions.
    # This includes exceptions that we may be retrying so we don't want to report them to Failbot.
    sig { params(error: StandardError, params: T::Hash[Symbol, T.untyped]).void }
    def report_update_exception(error, params: {})
      GitHub.dogstats.increment(
        "zuora.zuorest.update_subscription.exception",
        tags: ["error_class:#{error.class}", "on_last_retry:#{subscription_sync_status.on_last_retry?}"]
      )

      GitHub.logger.error(
        exception: error,
        "code.namespace": self.class.name,
        "code.function": "report_update_exception",
        "gh.billing.zuora.params": params,
        "gh.billing.synchronization_id": synchronization_id,
        "gh.billing.synchronization.number_of_retries_remaining": subscription_sync_status.number_of_retries_remaining,
        "gh.billing.synchronization.on_last_retry": subscription_sync_status.on_last_retry?,
        "gh.billing.synchronization.external_sync_status": subscription_sync_status.external_sync_status
      )
    end

    sig { params(result: GitHub::Billing::Result, partial_success: T::Boolean, params: T::Hash[Symbol, T.untyped]).void }
    def report_update_failure(result, partial_success: false, params: {})
      GitHub.dogstats.increment(
        "zuora.zuorest.update_subscription.error",
        tags: ["error_code:#{result.error_code}", "on_last_retry:#{subscription_sync_status.on_last_retry?}"]
      )

      GitHub.logger.warn(
        "code.namespace": self.class.name,
        "code.function": "report_update_failure",
        "gh.billing.zuora.partial_success": partial_success,
        "gh.billing.zuora.params": params,
        "gh.billing.synchronization_id": synchronization_id,
        "gh.billing.synchronization.number_of_retries_remaining": subscription_sync_status.number_of_retries_remaining,
        "gh.billing.synchronization.on_last_retry": subscription_sync_status.on_last_retry?,
        "gh.billing.synchronization.external_sync_status": subscription_sync_status.external_sync_status
      )
    end

    sig { params(message: String).returns(String) }
    def error_response_for(message)
      return DECLINED_MESSAGE if message.to_s.downcase.include?("declined")
      FAILURE_MESSAGE
    end

    sig { params(plan_subscription: ::Billing::PlanSubscription).returns(Billing::SubscriptionSyncStatus) }
    def track_subscription_sync(plan_subscription)
      target = plan_subscription.billable_entity
      subscription_sync_status = Billing::SubscriptionSyncStatus.find_by(target: target)
      # This stale check prevents the previous sync status from being used for the current sync
      # It is however NOT 100% accurate since the previous sync could still be within the recency window
      # for users making multiple syncs in a short period of time.
      return subscription_sync_status if subscription_sync_status.present? && !subscription_sync_status.stale?

      Billing::SubscriptionSyncStatus.new(target: target, plan_subscription: plan_subscription, external_sync_status: :pending)
    end

    # Internal: Get the earliest start date among other subscriptions on the Zuora account.
    #
    # This is used to align billing across subscriptions since our rate plans align to subscription start.
    sig { returns(T.nilable(Date)) }
    def term_start_date
      customer = plan_subscription.customer
      return unless customer

      other_plan_subscriptions = customer.plan_subscriptions.where.not(id: plan_subscription.id)
      zuora_subscriptions = other_plan_subscriptions.map(&:zuora_subscription).compact
      start_dates = zuora_subscriptions.map(&:start_date).compact
      start_dates.min
    end
  end
end
