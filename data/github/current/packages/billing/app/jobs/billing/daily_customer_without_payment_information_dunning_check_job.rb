# typed: strict
# frozen_string_literal: true

module Billing
  class DailyCustomerWithoutPaymentInformationDunningCheckJob < BillingJob
    # Use a dedicated queue for this job
    queue_as :billing_dunning_without_payment_info

    BATCH_SIZE = 100

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    sig { void }
    def perform
      return unless GitHub.billing_enabled?

      now = GitHub::Billing.now

      # The job runs hourly but we only run dunning if the current hour = 3
      return unless now.hour == 3

      azure_customers_without_payment_method.find_each(batch_size: BATCH_SIZE) do |customer|
        next unless customer.metered_ghe?
        # This check is here since it requires cross-domain query
        next unless customer.requires_azure_subscription?
        next if customer.valid_metered_azure_payment_method?

        next unless business = customer.business
        next if business.downgraded_to_free_plan?
        # Trialed and did not convert (meaning they are still in trial or abandoned trial)
        next if business.trial? && !business.trial_converted?

        GitHub.logger.info("customer_without_payment_information_detected", customer_context(customer))

        next unless business.feature_enabled?(:billing_cpwu_daily_customer_check_enabled)
        next if business.feature_enabled?(:billing_cpwu_daily_customer_check_exclusion_list)

        notification_type = notification_type(customer)

        case
        when never_notified?(customer)
          initial_notification(customer)
        when should_remind?(customer) && business.feature_enabled?(:billing_cpwu_account_downgrade)
          with_urgency?(customer) ? attention_required_notification(customer) : reminder_notification(customer)
        when should_disable?(customer) && business.feature_enabled?(:billing_cpwu_account_downgrade)
          # Disable the account
          with_write do
            customer.update_disabled_reasons(Billing::Public::BillingDisabledReasons::MissingPaymentMethod)
            business.enable_or_disable!
          end

          disabled_notification(customer)
        else
          # We are not notifying, return here so we are not making noises below
          next
        end

        instrument_notification(customer, notification_type)
        GitHub.logger.info("customer_without_payment_information_notified", customer_context(customer))
      end
    end

    sig { returns(ActiveRecord::Relation) }
    def azure_customers_without_payment_method
      Customer
        .joins(:business)
        .where(metered_ghe: true)
        .where(azure_subscription_id: nil)
        .where(business: { downgraded_at: nil })
        .where(business: { trial_expires_at: nil })
        .includes(:business)
    end

    sig { params(customer: Customer).returns(Date) }
    def target_disable_date(customer)
      initial_notification = customer.missing_payment_initial_notification || Date.today
      initial_notification.to_date + 30.days
    end

    sig { params(customer: Customer).returns(T::Boolean) }
    def never_notified?(customer)
      customer.missing_payment_initial_notification.nil?
    end

    sig { params(customer: Customer).returns(T::Boolean) }
    def should_disable?(customer)
      customer.days_since_missing_payment_initial_notification > 30
    end

    sig { params(customer: Customer).returns(T::Boolean) }
    def should_remind?(customer)
      [7, 14, 21, 28].include?(customer.days_since_missing_payment_initial_notification)
    end

    sig { params(customer: Customer).returns(T::Boolean) }
    def with_urgency?(customer)
      customer.days_since_missing_payment_initial_notification > 20
    end

    sig { params(customer: Customer).returns(String) }
    def notification_type(customer)
      return "initial" if never_notified?(customer)
      return "disable" if should_disable?(customer)
      return "attention" if with_urgency?(customer)
      "reminder"
    end

    private

    sig { params(customer: Customer).void }
    def initial_notification(customer)
      if T.must(customer.business).feature_enabled?(:billing_cpwu_account_downgrade)
        reminder_notification(customer)
      else
        BillingNotificationsMailer.no_payment_failure(T.must(customer.business)).deliver_later
      end

      with_write do
        customer.set_missing_payment_initial_notification
      end
    end

    sig { params(customer: Customer).void }
    def reminder_notification(customer)
      BillingNotificationsMailer.missing_payment_notice(T.must(customer.business), target_disable_date(customer)).deliver_later
    end

    sig { params(customer: Customer).void }
    def attention_required_notification(customer)
      BillingNotificationsMailer.missing_payment_notice(T.must(customer.business), target_disable_date(customer), attention_required: true).deliver_later
    end

    sig { params(customer: Customer).void }
    def disabled_notification(customer)
      BillingNotificationsMailer.downgrade_for_missing_payment_notice(T.must(customer.business), target_disable_date(customer)).deliver_later
    end

    sig { params(customer: Customer, type: String).void }
    def instrument_notification(customer, type)
      billing_target = "azure"
      GitHub.dogstats.increment("billing.missing_payment.notify", tags: ["target:#{billing_target}", "type:#{type}"])

      analytics_label = {
        ref_business_id: customer.business&.id,
        ref_billing_target: billing_target,
        ref_notification_type: type,
        ref_days_since: customer.days_since_missing_payment_initial_notification
      }.compact.map { |k, v| "#{k}:#{v}" }.join(";")

      # Track the notification event for analytics
      GlobalInstrumenter.instrument("analytics.event", {
        category: "missing_payment",
        action: "notified",
        label: analytics_label
      })
    end

    sig { params(customer: Customer).returns(T::Hash[String, T.untyped]) }
    def customer_context(customer)
      {
        "gh.billing.customer.id" => customer.id,
        "gh.billing.customer.business.id" => customer.business&.id,
        "gh.billing.customer.business.login" => customer.business&.display_login,
        "gh.billing.days_since_initial_notification" => customer.days_since_missing_payment_initial_notification,
      }
    end
  end
end
