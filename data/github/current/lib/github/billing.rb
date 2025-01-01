# typed: strict
# frozen_string_literal: true

module GitHub
  module Billing

    autoload :CreditCard, "github/billing/credit_card"
    autoload :Currency, "github/billing/currency"
    autoload :ErrorMessage, "github/billing/error_message"
    autoload :Result, "github/billing/result"
    autoload :ZuoraRateLimitHandler, "github/billing/zuora_rate_limit_handler"
    autoload :ZuorestTokenStorage, "github/billing/zuorest_token_storage"

    class Error < StandardError
    end

    class CustomerAlreadyExistsError < StandardError; end

    class BraintreeTokenGenerationError < Error; end

    class << self

    end

    # Defines the timezone in which our daily billing cycle runs
    #
    # Our customer's plans start at 00:00:00 Pacific Time (US & Canada)
    # and end at 23:59:59 Pacific Time (US & Canada).
    sig { returns(ActiveSupport::TimeZone) }
    def self.timezone
      @timezone ||= T.let(ActiveSupport::TimeZone["America/Los_Angeles"], T.nilable(ActiveSupport::TimeZone))
    end

    # Returns yesterday's date in the billing timezone
    sig { returns(Date) }
    def self.yesterday
      today - 1.day
    end

    # Returns today's date in the billing timezone
    sig { returns(Date) }
    def self.today
      timezone.today
    end

    # Whether the given date is today in the billing timezone
    sig { params(date: T.nilable(Date)).returns(T::Boolean) }
    def self.today?(date)
      today == date
    end

    # Whether the given date is in the past in the billing timezone (not including today)
    sig { params(date: T.any(Date, ActiveSupport::TimeWithZone)).returns(T::Boolean) }
    def self.past?(date)
      date.in_time_zone(timezone).to_date < today
    end

    # Whether the given date is in the future in the billing timezone (not including today)
    sig { params(date: T.any(Date, ActiveSupport::TimeWithZone)).returns(T::Boolean) }
    def self.future?(date)
      date.in_time_zone(timezone).to_date > today
    end

    # Returns the current time in the billing timezone
    sig { returns(ActiveSupport::TimeWithZone) }
    def self.now
      timezone.now
    end

    sig { params(date: Date, hours: Integer, minutes: Integer, seconds: Integer).returns(ActiveSupport::TimeWithZone) }
    def self.date_in_timezone(date, hours: 0, minutes: 0, seconds: 0)
      timezone.local(
        date.year,
        date.month,
        date.day,
        hours,
        minutes,
        seconds,
      )
    end

    # Public: Generate a Braintree client token for accepting PayPal.
    sig { params(timeout_value: T.nilable(Integer)).returns(T.nilable(String)) }
    def self.generate_braintree_client_token(timeout_value: 2)
      token = Timeout.timeout(timeout_value) do
        Braintree::ClientToken.generate if GitHub.braintree_client_token_enabled?
      end

      if token.blank?
        Failbot.report(BraintreeTokenGenerationError.new("braintree environment not enabled"), "gh.billing.config.braintree_client_token_enabled": GitHub.braintree_client_token_enabled?)
      end

      token
    rescue Errno::ECONNREFUSED, Timeout::Error => e
      Failbot.report(BraintreeTokenGenerationError.new(e.message), "gh.billing.config.braintree_client_token_enabled": GitHub.braintree_client_token_enabled?)

      nil
    end

    # Attempts to signup a user or business for a paying plan subscription.
    #
    # This atomically charges the given credit card and creates a customer
    # record with the given card details given the transaction is successful.
    #
    # user            - Saved and valid User record.
    # plan_name       - Name of the plan as a String the user is signing up for.
    # actor           - User initiating the upgrade, defaults to target.
    # payment_details - A Hash of payment details:
    #   :zuora_payment_method_id - The payment method ID returned by Zuora's Hosted Payment Page
    #   :billing_extra           - String extra billing information.
    #   :paypal_nonce            - String nonce representing a paypal account (optional).
    #   :billing_address         - The billing address as a Hash of optionally encrypted CC info
    #     * :country_name    - Country as a String
    #     * :region          - Region as a String
    #     * :postal_code     - Postal code as a String
    #
    # Returns a Billing::Result object indicating success or failure with an
    #   error message.
    sig do
      params(
        user: User,
        plan_name: String,
        actor: User,
        payment_details: T::Hash[Symbol, T.untyped],
      ).returns(GitHub::Billing::Result)
    end
    def self.signup(user, plan_name, actor:, payment_details:)
      Failbot.push("gh.user.id" => user.id)

      signup = ::Billing::Signup.new(user: user, plan_name: plan_name, actor: actor)
      unless signup.valid?
        if signup.customer_already_exists?
          raise CustomerAlreadyExistsError, "user has already signed up"
        end

        return Result.failure(signup.errors.full_messages.first)
      end

      unless has_payment_details?(payment_details)
        return Result.failure("A valid payment method is required to sign up for a paid plan")
      end

      plan =
        if user.coupon.try(:trial?)
          T.must(user.coupon).plan
        else
          GitHub::Plan.find!(plan_name)
        end

      user.update(plan: plan.name, billed_on: today)

      begin
        result = create_customer(user, payment_details, actor: actor)
      rescue StandardError => boom # rubocop:todo Lint/RescueException
        Failbot.report boom
        message = "We were unable to process your payment information. Please try again."
        result = Result.failure message
      end

      if result.success?
        # Update user's signup transaction to correct paid plan
        tx = user.transactions.where(action: "signed-up").last \
          or raise Error, "Expected a transaction to exist"
        tx.update(current_plan: plan.name)
        GitHub.dogstats.increment("user.create.paid")
      else
        user.update(plan: GitHub::Plan.free, billed_on: nil)

        user.instrument :billing_signup_error,
          email: user.billing_email,
          plan: plan.name,
          error: result.error_message.to_s,
          actor: actor
      end

      result
    end

    # Charge a user for a paid upgrade when there's no card on file.
    #
    # target          - User or Organization that is upgrading
    # plan_name       - Name of Plan to upgrade to
    # payment_details - A Hash of payment details:
    #   :actor        - User initiating the upgrade, defaults to target, required if target is an Organization.
    #   :zuora_payment_method_id - The payment method ID returned by Zuora's Hosted Payment Page
    #   :billing_extra           - String extra billing information.
    #   :paypal_nonce            - String nonce representing a paypal account (optional).
    #   :billing_address         - The billing address as a Hash of optionally encrypted CC info
    #     * :country_name    - Country as a String
    #     * :region          - Region as a String
    #     * :postal_code     - Postal code as a String
    sig do
      params(
        target: User,
        plan_name: String,
        payment_details: T::Hash[Symbol, T.untyped],
        plan_duration: T.nilable(String),
        actor: T.nilable(User),
      ).returns(GitHub::Billing::Result)
    end
    def self.paid_upgrade(target, plan_name, payment_details, plan_duration: nil, actor: nil)
      actor ||= target
      payment_details.reverse_merge! actor: actor
      Failbot.push "gh.user.id" => target.id

      unless payment_details.fetch(:actor).user?
        raise ArgumentError, "The actor must be a human user"
      end

      validate_paid_upgrade(target, plan_name)

      if target.needs_valid_payment_method_to_switch_to_plan?(plan_name) && !has_payment_details?(payment_details)
        return Result.failure "A credit card or other payment method is required to upgrade to that plan."
      end

      plan     = GitHub::Plan.find!(plan_name)
      old_plan = target.plan

      target.plan          = plan.name
      target.plan_duration = plan_duration if plan_duration
      target.billing_extra = payment_details[:billing_extra] if payment_details.has_key?(:billing_extra)

      if target.payment_amount > 0
        target.billed_on = today
        result = create_customer(target, payment_details, actor: actor)
        if result.success?
          target.enable!
          target.track_plan_change(payment_details[:actor], old_plan)
        else
          target.plan      = old_plan
          target.billed_on = today
          target.save
        end
      else
        create_customer_service(target, actor: actor).perform

        result = target.process_zero_charge_transaction("first-time-paid-upgrade")
      end

      result
    end

    # Public: Redeems a coupon and processes a payment, if necessary.
    #
    # target          - User or Organization to apply the coupon to
    # coupon          - Dat Coupon
    # payment_details - Hash of payment details:
    #   :actor         - User initiating the redemption, defaults to target, required if target is an Organization.
    #   :plan          - Plan to change to with this redemption
    #   :zuora_payment_method_id - The payment method ID returned by Zuora's Hosted Payment Page
    #   :billing_extra           - String extra billing information.
    #   :paypal_nonce            - String nonce representing a paypal account (optional).
    #   :billing_address         - The billing address as a Hash of optionally encrypted CC info
    #     * :country_name    - Country as a String
    #     * :region          - Region as a String
    #     * :postal_code     - Postal code as a String
    #
    # Either :zuora_payment_method_id of :paypal_nonce is required if the redemption
    # needs a charge and account has no billing record.
    sig do
      params(
        target: User,
        coupon: Coupon,
        payment_details: T.nilable(T::Hash[Symbol, T.untyped]),
      ).returns(GitHub::Billing::Result)
    end
    def self.redeem_coupon_and_charge(target, coupon, payment_details = nil)
      payment_details ||= {}
      payment_details.reverse_merge!({
        actor: target,
        plan: nil,
        credit_card: nil,
      })
      Failbot.push "gh.user.id" => target.id

      if payment_details.fetch(:actor).organization?
        raise ArgumentError, "An Organization cannot be the actor"
      end

      old_plan             = target.plan
      target.billing_extra = payment_details[:billing_extra] if payment_details.has_key?(:billing_extra)

      # Don't set the plan if the coupon is only meant to be used for a specific
      # plan; redeem_coupon will choose the right one.
      if payment_details[:plan].present? && !coupon.trial?
        target.plan = payment_details[:plan]
      end

      result = Result.failure("transaction block never ran")

      target.transaction do
        if target.redeem_coupon(coupon, actor: payment_details[:actor], instrument: false)
          if target.payment_amount == 0
            result = target.process_zero_charge_transaction
          else
            result = process_payment_for_redemption(target, payment_details)
            raise ActiveRecord::Rollback if result.failed?
          end

          if result.success?
            target.track_plan_change(payment_details[:actor], old_plan, coupon: coupon)
          end
        else
          result = Result.failure(target.errors.full_messages.first ||
            raise(Error, "expected target to have errors if redeem_coupon returns falsy"))
        end
      end

      result
    end

    # Public: Updates payment method details of an existing customer.
    # This also tries to charge the new card (or paypal account) if the user
    # account is disabled or its billed_on is in the past.
    #
    # target          - A User object who's credit card data we're updating.
    # payment_details - A Hash of payment details:
    #   :charge        - Boolean whether to attempt a recurring charge with this update. Default: true
    #   :zuora_payment_method_id - The payment method ID returned by Zuora's Hosted Payment Page
    #   :billing_extra           - String extra billing information.
    #   :paypal_nonce            - String nonce representing a paypal account (optional).
    #   :billing_address         - The billing address as a Hash of optionally encrypted CC info
    #     * :country_name    - Country as a String
    #     * :region          - Region as a String
    #     * :postal_code     - Postal code as a String
    # purpose         - Symbol indicating the purpose of the customer whose payment method should be updated,
    #                   :general or :sponsors
    #
    # Returns a GitHub::Billing::Result object, indicating
    # success or failure, the user that was updated and an error message if the
    # customer's credit card could not be updated.
    sig do
      params(
        target: ::Billing::Types::Account,
        payment_details: T::Hash[Symbol, T.untyped],
        purpose: Symbol,
        skip_synchronization: T::Boolean,
      ).returns(GitHub::Billing::Result)
    end
    def self.update_payment_method(target, payment_details, purpose: Customer::DEFAULT_PURPOSE, skip_synchronization: false)
      service = ::Billing::UpdatePaymentMethod.perform(target, payment_details, purpose: purpose,
        skip_synchronization: skip_synchronization)
      T.must(service.response)
    end

    # Creates a new customer and credit card records.
    #
    # target          - A User-like object who's credit card we're creating
    # payment_details - A Hash of payment details:
    #   :zuora_payment_method_id - The payment method ID returned by Zuora's Hosted Payment Page
    #   :billing_extra           - String extra billing information.
    #   :paypal_nonce            - String nonce representing a paypal account (optional).
    #   :billing_address         - The billing address as a Hash of optionally encrypted CC info
    #     * :country_name    - Country as a String
    #     * :region          - Region as a String
    #     * :postal_code     - Postal code as a String
    # actor           - the User who took this action
    # purpose         - Symbol indicating the purpose of the customer to create, :general or :sponsors
    #
    sig do
      params(
        target: ::Billing::Types::Account,
        payment_details: T::Hash[Symbol, T.untyped],
        actor: User,
        purpose: Symbol,
      ).returns(GitHub::Billing::Result)
    end
    def self.create_customer(target, payment_details, actor:, purpose: Customer::DEFAULT_PURPOSE)
      service = create_customer_service(target, actor: actor, details: payment_details, purpose: purpose).perform
      service.response
    end

    # Instantiates a CreateCustomer service object.
    # This object can be used to create a customer for a new user by calling perform
    sig { params(target: ::Billing::Types::Account, actor: T.nilable(User), details: T::Hash[Symbol, T.untyped], purpose: Symbol).returns(::Billing::CreateCustomer) }
    def self.create_customer_service(target, actor: nil, details: {}, purpose: Customer::DEFAULT_PURPOSE)
      ::Billing::CreateCustomer.new(target, actor: actor, details: details, purpose: purpose)
    end

    sig do
      params(
        target: User,
        payment_details: T::Hash[Symbol, T.untyped],
        actor: User,
        purpose: Symbol,
        skip_synchronization: T::Boolean,
      ).returns(GitHub::Billing::Result)
    end
    def self.create_or_update_customer(target, payment_details, actor:, purpose: Customer::DEFAULT_PURPOSE, skip_synchronization: false)
      if target.has_billing_record?
        self.update_payment_method(target, payment_details, purpose: purpose, skip_synchronization: skip_synchronization)
      else
        self.create_customer(target, payment_details, purpose: purpose, actor: actor)
      end
    end

    # Changes the plan subscription of the given user and possibly apply a
    # coupon. Records upgrades and downgrades in graphite and creates new
    # Transaction record.
    #
    # user          - A saved User or Organization record.
    # plan          - String name of the new plan.
    # actor         - Actor making the change
    # payment_details - A Hash of payment details:
    #   :coupon_code      - String coupon code (optional).
    #   :zuora_payment_method_id - The payment method ID returned by Zuora's Hosted Payment Page
    #   :billing_extra           - String extra billing information.
    #   :paypal_nonce            - String nonce representing a paypal account (optional).
    #   :billing_address         - The billing address as a Hash of optionally encrypted CC info
    #     * :country_name    - Country as a String
    #     * :region          - Region as a String
    #     * :postal_code     - Postal code as a String
    # plan_duration - String of "month" or "year".
    # job_status_id - JobStatus ID used to track the subscription change progress
    sig do
      params(
        user: User,
        actor: User,
        plan: T.nilable(T.any(String, GitHub::Plan)),
        payment_details: T.nilable(T::Hash[Symbol, T.untyped]),
        plan_duration: T.nilable(String),
        job_status_id: T.nilable(String),
      ).returns(GitHub::Billing::Result)
    end
    def self.change_subscription(user, actor:, plan: nil, payment_details: nil, plan_duration: nil, job_status_id: nil)
      payment_details ||= {}

      ::Billing::ChangeSubscription.perform \
        user,
        plan: plan,
        actor: actor,
        payment_details: payment_details,
        plan_duration: plan_duration,
        job_status_id: job_status_id
    end

    # Public: Change the number of paid seats for an organization. If seats
    # are added or removed, they will be charged/refunded accordingly.
    #
    # organization - Organization whose seats are changing.
    # options      - Hash of additional options.
    #               :seats - Integer number of seats.
    #               :actor - User performing the change.
    #               :collect_payment_job_id - Id of the job that will be performed.
    sig do
      params(
        organization: Organization,
        options: T::Hash[Symbol, T.untyped],
      ).returns(GitHub::Billing::Result)
    end
    def self.change_seats(organization, options)
      ::Billing::ChangeSubscription.perform \
        organization,
        actor:      options[:actor],
        seats:      options[:seats],
        seat_delta: options[:seat_delta],
        plan_duration: options[:plan_duration],
        job_status_id: options[:collect_payment_job_id]
    end

    # Finds and refunds multiple transactions until refund amount has been
    # reached.
    #
    # user            - The User to be refunded.
    # amount_in_cents - Integer amount in cents to be refunded. Can be positive or
    #                   negative. The absolute value will be used.
    #
    # Returns a GitHub::Billing::Result specifying the success or failure of
    # the refunds.
    sig do
      params(
        user: User,
        amount_in_cents: Integer,
      ).returns(T.nilable(GitHub::Billing::Result))
    end
    def self.find_and_refund_transactions_for_amount(user, amount_in_cents)
      amount_in_cents = amount_in_cents.abs
      refunds = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
      refundable_sales = T.unsafe(user.billing_transactions).refundable_sales # scope call to class method has Sorbet confused

      while amount_in_cents > 0
        if transaction = refundable_sales.shift
          refund = {
            amount_in_cents: [transaction.amount_in_cents, amount_in_cents].min,
            transaction: transaction,
          }
          refunds << refund

          amount_in_cents -= refund[:amount_in_cents]
        else
          # This *should* never happen unless we've manually refunded or voided
          # transactions using Braintree. In these cases, we don't want to
          # return an error to the customer. Their money has already been
          # refunded. We'll log the error with Failbot so we can monitor these.
          message = "Not enough transactions to refund full amount"
          error = Error.new(message)
          error.set_backtrace(caller)
          Failbot.report(error)
          return Result.success
        end
      end

      results = refunds.map do |refund|
        result = refund_transaction(refund[:transaction].transaction_id, refund[:amount_in_cents])
        return result if result.failed? # Return early if we fail
        result
      end

      results.last
    end

    # Returns true if old_plan to new_plan is an upgrade or the same price.
    sig { params(old_plan: GitHub::Plan, new_plan: GitHub::Plan).returns(T::Boolean) }
    def self.upgrading?(old_plan, new_plan)
      new_plan.cost >= old_plan.cost
    end

    # Whether today is before the billing day?
    sig { params(billing_date: Date).returns(T::Boolean) }
    def self.before_billing_date?(billing_date)
      today.day < billing_date.day
    end

    # Whether today is after the billing day?
    sig { params(billing_date: Date).returns(T::Boolean) }
    def self.after_billing_date?(billing_date)
      today.day > billing_date.day
    end

    # Refund up to the full amount of the given transaction ID. This works with
    # legacy Braintree (Orange), current Braintree (Blue), and Zuora accounts.
    #
    # txn_id                   - Transaction ID as a String.
    # user_id                  - ID of GitHub user receiving the refund
    # refund_amount_in_cents   - Integer amount in cents to refund. This must be
    #                            equal to or less than the full amount of the
    #                            transaction (optional, default: full transaction
    #                            amount).
    # skip_email               - Boolean to skip sending the refund email
    #                            (optional - defaults to false)
    # email_refund_custom_text - String added to the refund email body
    #                            (optional - defaults to nil)
    sig do
      params(
        txn_id: String,
        refund_amount_in_cents: T.nilable(Integer),
        skip_email: T::Boolean,
        email_refund_custom_text: T.nilable(String),
      ).returns(GitHub::Billing::Result)
    end
    def self.refund_transaction(txn_id, refund_amount_in_cents = nil, skip_email: false, email_refund_custom_text: nil)
      Failbot.push("gh.billing.transaction.id" => txn_id)

      transaction = ::Billing::BillingTransaction.find_by(transaction_id: txn_id)
      if transaction
        if transaction.pending_status_update?
          transaction.update_status_from_processor
        end

        transaction.refund!(
          refund_amount_in_cents,
          skip_email: skip_email,
          email_refund_custom_text: email_refund_custom_text
        )
      else
        Result.failure("Transaction not found: #{txn_id}")
      end
    end

    # Process a payment for a user.  If the user is on monthly billing, return
    # success and let the billing job handle payment. If the user is on yearly
    # billing charge the pro-rated mount.  If the user doesn't have an external
    # account, create one and let the charge happen in the billing run.
    #
    # ¿Is this more generally applicable?
    #
    # target          - User object
    # payment_details - Hash of payment details (optional):
    #                   :actor            - User initiating the request.
    #                   :paypal_nonce     - String nonce representing a paypal account (optional).
    #                   :credit_card      - A Hash of potentially encrypted CC info (optional).
    #                     * :number           - CC number as a String.
    #                     * :expiration_month - Expiration month as a String of form MM
    #                     * :expiration_year  - Expiration year as a String of form YY
    #                     * :cvv              - CVV as a String (e.g. "420")
    #                   :billing_address  - The billing address as a Hash of optionally encrypted CC info
    #                     * :country_code_alpha3 - Country as a String
    #                     * :region              - Region as a String
    #                     * :postal_code         - Postal code as a String
    sig do
      params(
        target: User,
        payment_details: T.nilable(T::Hash[Symbol, T.untyped]),
      ).returns(GitHub::Billing::Result)
    end
    def self.process_payment_for_redemption(target, payment_details = nil)
      payment_details ||= {}
      actor = payment_details[:actor]

      if target.has_valid_payment_method?
        if target.yearly_plan?
          # No proration right now :(
          Result.success
        else
          Result.success
        end
      elsif has_payment_details?(payment_details)
        target.billed_on = today # TODO: Why are we setting this directly?
        target.save
        result = if target.has_billing_record?
          update_payment_method(target, payment_details.merge(charge: false))
        else
          create_customer(target, payment_details, actor: actor)
        end

        result.success? ? Result.success : Result.failure(result.error_message.to_s)
      else
        Result.failure("Credit card or other payment method required")
      end
    end

    # Validates whether a paid upgrade can happen.  Raises GitHub::Billing::Error
    # on any failure.
    sig { params(target: User, plan_name: String).void }
    def self.validate_paid_upgrade(target, plan_name)
      plan = GitHub::Plan.find(plan_name)
      if plan.nil?
        raise Error, "unknown plan: #{plan_name}"
      end

      if target.organization? && !plan.orgs?
        raise Error, "organization can not use a user plan"
      end

      if plan.free?
        raise Error, "can not upgrade to a free plan"
      end
    end

    sig do
      params(
        account: ::Billing::Types::Account,
        force: T::Boolean,
        purpose: T.nilable(Symbol),
        skip_sync: T::Boolean,
      ).returns(T.nilable(::Billing::PlanSubscription))
    end
    def self.transition_to_external_subscription(account, force: false, purpose: :general, skip_sync: false)
      purpose ||= :general
      ::Billing::PlanSubscription::Transition.activate(account, force: force, purpose: purpose, skip_sync: skip_sync)
    end

    sig { params(payment_details: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def self.has_payment_details?(payment_details)
      ::Billing::PaymentDetails.new(payment_details).valid?
    end
  end
end
