# typed: strict
# frozen_string_literal: true

module Billing
  # A denormalized record of monetary transactions (sales or refunds) kept for:
  # - Reporting purposes (reconcile against Braintree/Zuora data).
  # - To show payment history to customers and GitHub staff.
  # - To render customer receipts.
  #
  # BillingTransactions are created:
  # - When purchasing GitHub for the first time
  # - On the automated recurring charge for plan renewal
  # - When refunding another BillingTransaction (self referential)
  # - When making a mid billing cycle, prorated purchase:
  #   - Plan upgrade on yearly accounts
  #   - Seat purchase
  #   - Asset pack purchase
  #
  # NOTES:
  #
  # - transaction_id is the external alphanumeric id for a transaction.
  #
  # - We always record a BillingTransaction, even if the customer has a coupon
  # that fully covers the amount owed. These are called zero charge
  # transactions.
  class BillingTransaction < ApplicationRecord::Domain::Users
    include GitHub::Validations
    include GitHub::Memoizer

    sig { returns(BigDecimal) }
    def self.marketplace_revenue_cut
      0.05.to_d
    end

    include GitHub::Billing::CreditCard,
            GitHub::Relay::GlobalIdentification,
            Billing::BillingTransaction::SponsorsDependency

    enum :last_status, Billing::BillingTransactionStatuses::ALL

    # Public: String external alphanumeric transaction identifier.
    #
    # NB: Not used to associate Transactions.
    # column :transaction_id
    validates_presence_of :transaction_id, if: :transaction_id_required?
    validates_uniqueness_of :transaction_id, allow_nil: true, case_sensitive: false

    # Public: User/Org this transaction belongs to.
    # column :user_id
    belongs_to :live_user, class_name: "User", foreign_key: :user_id, inverse_of: :billing_transactions

    belongs_to :plan_subscription, class_name: "Billing::PlanSubscription"

    belongs_to :customer

    # Public: String transaction type. One of the following values:
    #   signed-up                 - New user or business signs up for paid plan
    #   first-time-paid-upgrade   - Existing user or business pays for an upgrade
    #   recurring-charge          - Monthly/Yearly automated charge
    #   prorate-charge            - Prorated charge for yearly upgrade
    #   prorate-seat-charge       - Prorated charge for seat purchase
    #   prorate-asset-pack-charge - Prorated charge for asset pack purchase
    #   refund                    - Refund
    #   authorization             - Payment method authorization
    #
    # column :transaction_type
    validates_presence_of :transaction_type

    PRORATED_CHARGE_TRANSACTION_TYPES = T.let(%w(prorate-charge prorate-seat-charge prorate-asset-pack-charge).freeze, T::Array[String])

    # Public: Integer total amount in cents of this transaction.
    # column :amount_in_cents
    validates_presence_of :amount_in_cents

    # Public: String email address where their receipt was sent. Useful for
    # looking up the receipt in logs@github.com even if the user has been
    # deleted. It may be possible to also use user_login for this purpose.
    # column :billing_email_address
    validates :billing_email_address, unicode3: true

    # Public: String country name (needed for reporting and tax reasons).
    # column :country
    validates :country, unicode3: true

    # Public: String region name  (needed for reporting and tax reasons).
    # column :region
    validates :region, unicode3: true

    # Public: String postal code (needed for reporting and tax reasons).
    # column :postal_code
    validates :postal_code, unicode3: true

    # Public: String whether this transaction is for an "organization" or a "user".
    # column :user_type

    # Public: String login of the user or organization.
    # column :user_login

    # Public: Datetime timestamp the user created their account.
    # column :user_created_at

    # Public: String name of the plan this transaction is for.
    # column :plan_name

    # Public: Integer plan price in cents.
    # column :plan_price_in_cents

    enum :renewal_frequency, { monthly: 0, yearly: 1 }

    # Public: String name of the coupon if one was used.
    # column :coupon_name
    validates :coupon_name, unicode3: true

    # Public: Integer amount of the discount in cents if a coupon was used.
    # column :discount_in_cents

    enum :platform, { legacy_braintree: 0, braintree: 1, zuora: 2 }
    validates :platform, presence: true

    PRODUCTS = T.let(%w(dotcom job_posting).freeze, T::Array[String])

    # Public: string product. "dotcom" for most transactions, "job_posting" for
    # job posting credit purchases. Nil results in "dotcom".
    # column :product
    validates_inclusion_of :product, in: PRODUCTS, allow_nil: true

    # Public: Datetime the service this transaction pays for will end.
    # column :service_ends_at

    # Public: BillingTransaction that refunds this transaction, if any
    has_one :refund,
      -> { where("sale_transaction_id IS NOT NULL") },
      class_name: "Billing::BillingTransaction",
      primary_key: :transaction_id,
      foreign_key: :sale_transaction_id,
      inverse_of: :sale

    # Public: BillingTransaction that this transaction refunds, if any
    belongs_to :sale, class_name: "Billing::BillingTransaction",
      primary_key: :transaction_id,
      foreign_key: :sale_transaction_id,
      inverse_of: :refund

    has_many :line_items, dependent: :destroy
    has_many :tax_items, through: :line_items, disable_joins: true

    has_many :disputes, class_name: "Billing::Dispute"

    # Public String country of issuance of the payment method.
    # column :country_of_issuance

    # Public: The bank identification number for the credit card used.
    # column :bank_identification_number

    # Public: String settlement batch id from external processor.
    # column :settlement_batch_id

    # Public: The last four digits of the credit card used.
    # column :last_four

    # Public: Email of the paypal account, if applicable.
    # column :paypal_email
    validates :paypal_email, unicode3: true

    enum :payment_type, {
      credit_card: 0,
      paypal: 1,
      no_charge: 2, # Log things like 100% coupons that have $0 charges.
    }

    # Public: Integer delta seats this org added/removed as part of this
    # transaction.
    # column :seats_delta

    # Public: Integer total seats this org owns as part of this transaction.
    # column :seats_total

    # Public: Integer delta asset packs this user/org added/removed as part of
    # this transaction.
    # column :asset_packs_delta

    # Public: Integer total asset packs this user/org owns as part of this
    # transaction.
    # column :asset_packs_total

    # Public: Integer unit price in cents of a single asset pack at the time of
    # this transaction.
    # column :asset_pack_unit_price_in_cents

    # Public: Integer number of days this transaction amount was prorated for.
    # column :prorated_days

    # Public: Billing transaction statuses.
    has_many :statuses, class_name: "Billing::BillingTransactionStatus"

    # Public: Billing transaction notes.
    has_many :notes, class_name: "Billing::BillingTransactionNote"

    scope :created_at_or_after, ->(timestamp) { where(created_at: timestamp..) }
    scope :created_before, ->(timestamp) { where(created_at: ...timestamp) }

    scope :for_zuora_transaction_id, ->(zuora_transaction_id) do
      # remove nil transaction ids if we can, there are way too many
      # and callers almost certainly don't want them!
      #
      # See https://github.com/github/github/pull/208463
      zuora_transaction_id.compact! if zuora_transaction_id.respond_to?(:compact!)
      where(platform_transaction_id: zuora_transaction_id)
    end

    # Public: Scope to find transactions needing status updates
    scope :pending_status_updates, -> {
      where(
        "last_status IS NULL OR last_status NOT IN (?) AND transaction_id IS NOT NULL",
        Billing::BillingTransactionStatuses::FINAL.values,
      )
    }

    # Billing transactions that apply to the current period
    scope :current, -> { where("service_ends_at >= ?", GitHub::Billing.today) }

    scope :in_the_past_hour, -> { where("created_at > ?", 1.hour.ago) }
    scope :in_the_past_month, -> { where("created_at > ?", 1.month.ago) }

    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :for_business, ->(business) { where(customer_id: business.customer_id) }
    scope :for_customer, ->(customer_id) { where(customer_id: customer_id) }

    # Billing transactions where the last_status was successful
    scope :successful, -> { where(last_status: Billing::BillingTransactionStatuses::SUCCESS.keys) }

    scope :refunds, -> { where(transaction_type: "refund") }
    scope :non_refunds, -> { where.not(transaction_type: "refund") }

    scope :authorizations, -> { where(transaction_type: "authorization") }
    scope :excluding_authorizations, -> { where.not(transaction_type: "authorization") }
    scope :usage_authorizations, -> { authorizations.where("amount_in_cents > 100") }

    scope :current_authorizations_for_customer, ->(customer_id) {
      authorizations.where(customer_id: customer_id).where("created_at > ?", 1.month.ago)
    }

    scope :excluding_no_charges, -> { where.not(payment_type: Billing::BillingTransaction.payment_types[:no_charge]) }

    # Sales only scope
    scope :sales, -> {
      non_refunds.excluding_no_charges.excluding_authorizations
    }

    # Return in descending order
    scope :descending, -> { order("created_at DESC") }

    # Returns a BillingTransaction or nil
    scope :first_time_charge, -> {
      where(
        transaction_type: "first-time-paid-upgrade",
        last_status: Billing::BillingTransactionStatuses::SUCCESS.values,
      )
    }

    scope :for_transaction, ->(txn_id) { where(transaction_id: txn_id) }
    scope :paid, -> { where.not(amount_in_cents: [nil, 0]) }

    scope :excluding_prorated_charges, -> { where.not(transaction_type: PRORATED_CHARGE_TRANSACTION_TYPES) }

    delegate :business, to: :customer, allow_nil: true

    sig { returns(Billing::Money) }
    def tax_amount
      Billing::Money.new(tax_items.sum(&:amount_in_cents))
    end

    sig do
      params(
        amount_in_cents: Integer,
        refund_reference_id: String,
        platform_transaction_id: T.nilable(String)
      ).returns(Billing::BillingTransaction)
    end
    def build_refund_transaction(amount_in_cents:, refund_reference_id:, platform_transaction_id:)
      refund_transaction = dup
      refund_transaction.assign_attributes(
        amount_in_cents: -1 * amount_in_cents,
        old_plan_name: plan_name,
        plan_name: billable_entity&.plan_name,
        platform_transaction_id: platform_transaction_id,
        sale_transaction_id: transaction_id,
        last_status: :settled,
        transaction_id: refund_reference_id,
        transaction_type: "refund"
      )

      refund_transaction
    end

    # Public: Updates records that are not yet in a "final" status
    sig { void }
    def self.update_transactions_with_pending_status
      GitHub.dogstats.count \
        "billing_transaction.pending_status_updates",
        pending_status_updates.count

      pending_status_updates.find_each do |transaction|
        UpdateBillingTransactionStatusJob.perform_later(transaction)
      end
    end

    # Public: All refundable sales for the current billing cycle
    sig { returns(T::Array[Billing::BillingTransaction]) }
    def self.refundable_sales
      current.sales.descending.select(&:refundable?).to_a
    end

    # Returns either the user or the business
    sig { returns(T.nilable(T.any(::Billing::Types::Account, ::Billing::DeadUser))) }
    def billable_entity
      billable_user? ? user : business
    end

    sig { returns(T::Boolean) }
    def billable_user?
      user_id.present?
    end

    sig { returns(T::Boolean) }
    def billable_business?
      !billable_user? && business.present?
    end

    sig { returns(T.any(T::Array[Billing::BillingTransaction::LineItem], ActiveRecord::Relation)) }
    def paid_line_items
      if association(:line_items).loaded?
        line_items.select { |li| li.paid? }
      else
        line_items.paid
      end
    end

    sig { returns(T.any(T::Array[Billing::BillingTransaction::LineItem], ActiveRecord::Relation)) }
    def subscribable_line_items
      if association(:line_items).loaded?
        line_items.select { |li| li.subscribable? }
      else
        line_items.subscribable
      end
    end

    sig { returns(T.any(T::Array[Billing::BillingTransaction::LineItem], ActiveRecord::Relation)) }
    def marketplace_line_items
      if association(:line_items).loaded?
        line_items.select { |li| li.marketplace? }
      else
        line_items.marketplace
      end
    end

    sig { returns(T::Boolean) }
    def multiple_products?
      unique_subscribables = paid_line_items
        .reject { |line_item| line_item.subscribable_id.nil? }
        .map { |line_item| [line_item.subscribable_id, line_item.subscribable_type] }
        .uniq
      unique_subscribables.size > 1
    end

    sig { returns(T.any(T::Array[Billing::BillingTransaction::LineItem], ActiveRecord::Relation)) }
    def sponsorship_line_items
      if association(:line_items).loaded?
        line_items.select { |li| li.sponsorship? }
      else
        line_items.sponsorships
      end
    end

    sig { returns(T.any(T::Array[Billing::BillingTransaction::LineItem], ActiveRecord::Relation)) }
    def product_uuid_line_items
      if association(:line_items).loaded?
        line_items.select { |li| li.product_uuid? }
      else
        line_items.product_uuids
      end
    end

    sig { returns(T.any(T::Array[Billing::BillingTransaction::LineItem], ActiveRecord::Relation)) }
    def copilot_line_items
      if association(:line_items).loaded?
        line_items.select { |li| li.copilot? }
      else
        line_items.copilot
      end
    end

    sig { returns(T.any(T::Array[Billing::BillingTransaction::LineItem], ActiveRecord::Relation)) }
    def advanced_security_line_items
      if association(:line_items).loaded?
        line_items.select { |li| li.advanced_security? }
      else
        line_items.advanced_security
      end
    end

    sig { returns(T.any(T::Array[Billing::BillingTransaction::LineItem], ActiveRecord::Relation)) }
    def usage_charged_line_items
      if association(:line_items).loaded?
        line_items.select { |li| li.usage_charge? }
      else
        line_items.usage
      end
    end

    # Public: Log a Zuora initiated charge.
    #
    # billable_entity   - The User/Organization/Business to log this transaction for.
    # invoiced_items    - Array[Billing::Zuora::InvoiceItem] that we charged for in this transaction
    # charge_type       - String transaction charge type (optional, default:
    #                     "recurring-charge"). Should be one of:
    #                       "recurring-charge"          - Monthly/Yearly automated charge
    #                       "prorate-seat-charge"       - Prorated charge for seat purchase
    #                       "prorate-asset-pack-charge" - Prorated charge for asset pack purchase
    sig do
      params(
        billable_entity: ::Billing::Types::Account,
        invoiced_items: T::Array[Billing::Zuora::InvoiceItem],
        charge_type: T.nilable(String)
      ).returns(T.self_type)
    end
    def log_recurring_charge(billable_entity:, invoiced_items: [], charge_type: nil)
      copy_billable_details(billable_entity, charge_type: charge_type)
      update_prorated_days(invoiced_items: invoiced_items)
      save!
      create_recurring_line_items(invoiced_items: invoiced_items)
      self
    end

    sig { returns(T::Boolean) }
    def zero_charge?
      amount.zero?
    end

    sig { returns(T.nilable(String)) }
    def short_transaction_id
      transaction_id&.last(8)&.upcase
    end

    sig { returns(Integer) }
    def refund_amount_in_cents
      if refund = self.refund
        -(refund.amount_in_cents)
      else
        0
      end
    end

    # Public: Log a $0 billing transaction
    #
    # billable_entity   - The User/Organization/Business to log this transaction for.
    # created_at        - DateTime when this transaction happened (defaults to now)
    # dry_run           - If true, does not save the transaction (defaults to false)
    #
    sig do
      params(
        billable_entity: ::Billing::Types::Account,
        created_at: T.nilable(DateTime),
        dry_run: T::Boolean
      ).returns(T.self_type)
    end
    def log_zero_charge(billable_entity:, created_at: nil, dry_run: false)
      copy_billable_details(billable_entity)
      copy_historical_information(created_at) if created_at

      unless dry_run
        save!
        # NB - Save and then update b/c we need to generate transaction_id from id
        # for uniqueness (see #our_transaction_id).
        update!(
          transaction_id: our_transaction_id,
          last_status: :settled,
        )
      end

      self
    end

    sig { params(dry_run: T::Boolean).returns(T.self_type) }
    def recalculate_historical_information(dry_run: false)
      raise ArgumentError, "must be a $0 transation" unless self.amount_in_cents.zero?

      self.copy_historical_information(self.created_at)

      unless dry_run
        save!
      end

      self
    end

    # Deprecated: Log a new BillingTransaction.
    #
    # attrs - Hash of attributes to initialize BillingTransaction with.
    #
    sig { params(attrs: T::Hash[Symbol, T.untyped]).returns(Billing::BillingTransaction) }
    def self.log(attrs)
      billing_transaction = new(attrs)

      billable_entity = if billing_transaction.user_id.present?
        user = T.cast(billing_transaction.user, ::User)
      elsif billing_transaction.customer&.business.present?
        business = T.cast(billing_transaction.customer&.business, ::Business)
      else
        nil
      end

      if billable_entity.present?
        billing_transaction.plan_name = billable_entity.plan.try(:name)
        billing_transaction.plan_price_in_cents = billable_entity.plan.try(:cost_in_cents)
        billing_transaction.arr_in_cents = billing_transaction.calculated_arr_in_cents
        billing_transaction.seats_total = billable_entity.seats
        billing_transaction.renewal_frequency = billable_entity.yearly_plan? ? :yearly : :monthly

        if billable_entity.coupon
          billing_transaction.coupon_name = billable_entity.coupon&.code
          billing_transaction.discount_in_cents ||= (billable_entity.discount * 100).to_i
        end

        billing_transaction.billing_email_address = billable_entity.billing_email
        billing_transaction.user_type = billable_entity.is_a?(User) ? billable_entity.type.downcase : "business"
        billing_transaction.user_login = billable_entity.is_a?(User) ? billable_entity.login : billable_entity.slug
        billing_transaction.user_created_at = billable_entity.created_at || Time.current

        if payment_method = billable_entity.payment_method
          if billing_transaction.payment_type.blank?
            billing_transaction.payment_type = payment_method.paypal? ? :paypal : :credit_card
          end
          billing_transaction.region = payment_method.region
          billing_transaction.country = payment_method.country
          billing_transaction.postal_code = payment_method.postal_code
        end
      end

      billing_transaction.save!

      billing_transaction
    end

    # Public: Set transaction details into this billing transaction
    #
    # DEPRECATION WARNING:
    # This method is deprecated with the transition to Zuora. It should not be
    # used for new integrations and may be removed in the near future. See the
    # method Billing::Zuora::Payment#decorate_billing_transaction.
    #
    # braintree_transaction - A Braintree::Transaction
    #
    sig { params(braintree_transaction: T.nilable(::Braintree::Transaction)).void }
    def transaction=(braintree_transaction)
      return if braintree_transaction.nil?

      braintree_transaction = Billing::BraintreeTransaction.new(braintree_transaction)

      self.transaction_id = braintree_transaction.id
      self.platform_transaction_id = braintree_transaction.id

      if braintree_transaction.refund?
        self.sale_transaction_id = braintree_transaction.original_transaction_id
      end

      if braintree_transaction.paypal?
        self.payment_type = :paypal
        self.paypal_email = braintree_transaction.paypal_email
      else
        self.payment_type = :credit_card
        self.bank_identification_number = braintree_transaction.bank_identification_number
        self.country_of_issuance = braintree_transaction.country_of_issuance
        self.last_four = braintree_transaction.last_four
      end

      if braintree_transaction.status_history.present?
        braintree_transaction.status_history.each do |status_detail|
          next if find_status(status_detail.status)
          self.statuses.build(status_detail: status_detail)
        end
        self.last_status = braintree_transaction.status
        self.settlement_batch_id ||= braintree_transaction.settlement_batch_id
      end
    end

    sig { returns(T::Boolean) }
    def incomplete?
      transaction_id.blank?
    end

    sig { returns(T::Boolean) }
    def job_posting?
      product == "job_posting"
    end

    # Public: Generate transaction_id based on our id. Primarily for use by
    #         zero-charge transactions that don't have a corresponding
    #         transaction on an external processor.
    #
    # Returns a String containing a base-36 encoded id preceeded by "0-"
    sig { returns(T.nilable(String)) }
    def our_transaction_id
      "0-#{id.to_i.to_s(36).rjust(6, "0")}" if id
    end

    # Internal: Finds the BillingTransactionStatus for the status
    sig { params(status: String).returns(T.nilable(Billing::BillingTransactionStatus)) }
    def find_status(status)
      statuses.all.find { |s| s.status == status }
    end

    # Public: The total discount of this transaction as a Money object,
    #         adjusted for billing frequency
    sig { returns(Billing::Money) }
    def total_discount
      discount = discount_in_cents.to_s
      discount *= 12 if yearly?
      Billing::Money.new(discount)
    end

    # Public: Refund this transaction (or partial).
    #
    # refund_amount_in_cents   - Integer amount in cents to refund if less than
    #                            transaction.amount (optional - defaults to
    #                            transaction.amount).
    # skip_email               - Boolean to skip sending the refund email
    #                            (optional - defaults to false)
    # email_refund_custom_text - String added to the refund email body
    #                            (optional - defaults to nil)
    #
    sig do
      params(
        refund_amount_in_cents: T.nilable(Integer),
        skip_email: T::Boolean,
        email_refund_custom_text: T.nilable(String),
        refund_invoice_payment_data: T.nilable(T::Hash[Symbol, T.untyped])
      ).returns(GitHub::Billing::Result)
    end
    def refund!(refund_amount_in_cents = nil, skip_email: false, email_refund_custom_text: nil, refund_invoice_payment_data: nil)
      refund_amount_in_cents = if refund_amount_in_cents.nil?
        amount_in_cents
      else
        [refund_amount_in_cents, amount_in_cents].min
      end

      result = Billing::Refund.new(self, refund_invoice_payment_data: refund_invoice_payment_data).process(refund_amount_in_cents)

      if result.success?
        cache_refunded_transaction

        if !skip_email && !zuora_refund_processed_in_webhook?(result)
          create_refund_email(
            refund_transaction: result.billing_transaction,
            refund_amount_in_cents: refund_amount_in_cents.to_i,
            email_refund_custom_text: email_refund_custom_text
          ).deliver_later
        end
      end

      result
    end

    sig { params(result: GitHub::Billing::Result).returns(T::Boolean) }
    def zuora_refund_processed_in_webhook?(result)
      result.zuora_result.present? && live_user.present?
    end

    # Public: Send a refund email for this transaction.
    #
    # refund_transaction       - The refund transaction
    # refund_amount_in_cents   - Integer amount in cents that was refunded
    # email_refund_custom_text - String added to the refund email body
    #
    sig do
      params(
        refund_transaction: Billing::BillingTransaction,
        refund_amount_in_cents: Integer,
        email_refund_custom_text: T.nilable(String)
      ).returns(ActionMailer::MessageDelivery)
    end
    def create_refund_email(refund_transaction:, refund_amount_in_cents: refund_transaction.amount_in_cents.to_i, email_refund_custom_text: nil)
      instrument = paypal? ? "PayPal account" : "credit card"

      BillingNotificationsMailer.refund(
        user,
        created_at&.to_date,
        refund_amount_in_cents,
        instrument,
        refund_transaction.created_at,
        email_refund_custom_text,
        refund_transaction: refund_transaction,
      )
    end

    # Public: Money sum total amount of this transaction.
    sig { returns(Billing::Money) }
    def amount
      Billing::Money.new(amount_in_cents)
    end

    # Public: Returns true if this billing transaction is not in a "final"
    # state.
    sig { returns(T::Boolean) }
    def pending_status_update?
      Billing::BillingTransactionStatuses::FINAL.exclude?(last_status)
    end

    # Internal: Retrieves transaction from processor and updates status
    sig { returns(T.nilable(T::Boolean)) }
    def update_status_from_processor
      return if transaction_id.blank?

      if zuora?
        platform_payment.decorate_billing_transaction(self)
      else
        update_braintree_transaction_status
      end

      save!
    end

    # Public: Whether or not this transaction failed at the processor
    sig { returns(T::Boolean) }
    def failed?
      !success?
    end

    # Public: Whether or not this transaction is an authorization
    sig { returns(T::Boolean) }
    def is_authorization?
      self.transaction_type == "authorization"
    end

    # Public: Whether or not this transaction is a refund
    sig { returns(T::Boolean) }
    def is_refund?
      sale_transaction_id.present?
    end

    # Public: Whether or not this transaction has been refunded
    sig { returns(T::Boolean) }
    def was_refunded?
      refund.present?
    end

    # Public : Whether this transaction is within a year old
    sig { returns(T::Boolean) }
    def is_within_a_year_ago?
      created_at >= 1.year.ago
    end

    # Public: Whether or not this transaction is refundable
    sig { returns(T::Boolean) }
    def refundable?
      return false if !billable_business? && !live_user.present?
      return false if credit_balance_adjustment_transaction?
      return false if failed?
      return false if amount_in_cents == 0
      return false if voided? || charged_back?
      return false if is_refund? || was_refunded?
      return false if legacy_braintree?
      return false if is_authorization?
      true
    end

    # Public: Whether or not this transaction is "successful" - defined
    #         as having a status in the set [submitted_for_settlement, settled]
    #         Note that historically this also included "settling", but
    #         this status is no longer supported.
    sig { returns(T::Boolean) }
    def success?
      Billing::BillingTransactionStatuses::SUCCESS.include?(last_status) || credit_balance_adjustment_transaction?
    end

    # Public: Is this a prorated charge?
    sig { returns(T::Boolean) }
    def prorated_charge?
      PRORATED_CHARGE_TRANSACTION_TYPES.include? transaction_type
    end

    # Public: Record a chargeback
    #
    # dispute - A Braintree::Dispute from the braintree API linked to this
    #           billing transaction
    sig { params(dispute: ::Braintree::Dispute).returns(T.nilable(T::Boolean)) }
    def chargeback!(dispute)
      details = "Chargeback\n" \
                "Date received: #{dispute.received_date}\n" \
                "Reason: #{dispute.reason}"
      notes.create(note: details)
      statuses.create(
        amount_in_cents: (dispute.amount.to_i * 100),
        status: :charged_back,
      )
      self.last_status = :charged_back

      save!
    end

    # Public: The unmasked card number used in this transaction
    sig { returns(String) }
    def truncated_number
      "#{bank_identification_number}#{"*" * 6}#{last_four}"
    end

    # Public: The formatted, masked card number used in this transaction
    sig { returns(String) }
    def card_number
      format_card_number(truncated_number)
    end

    # Public: The card type used in this transaction
    sig { returns(T.nilable(String)) }
    def card_type
      detect_card_type(truncated_number)
    end

    sig { returns(T.nilable(Date)) }
    def date
      @date ||= T.let(created_at&.to_billing_date, T.nilable(Date))
    end

    sig { returns(T::Boolean) }
    def in_progress?
      created_at = self.created_at
      !!created_at && created_at > 10.minutes.ago
    end

    # Public: String user friendly physical address. Ex: "San Francisco, CA, 94107"
    sig { returns(String) }
    def location
      [region, country, postal_code].compact.join ", "
    end

    # Public: User, if user is still around, otherwise DeadUser
    sig { returns(T.any(::User, ::Billing::DeadUser)) }
    def user
      @user ||= T.let(live_user || dead_user, T.nilable(T.any(::User, ::Billing::DeadUser)))
    end

    # Public: Sets live_user (so it acts like a belongs_to)
    sig { params(user: T.nilable(::User)).returns(T.nilable(::User)) }
    def user=(user)
      self.live_user = @user = user
    end

    # Internal: Quacks like a User, if the user isn't around anymore
    sig { returns(Billing::DeadUser) }
    memoize def dead_user
      Billing::DeadUser.new do |user|
        user.id                    = user_id
        user.login                 = user_login
        user.billing_email         = billing_email_address
        user.created_at            = user_created_at
        user.user_type             = user_type
      end
    end

    sig { returns(T::Boolean) }
    def transaction_id_required?
      exempted_statuses = %w(failed processor_declined authorized)
      has_status? && !exempted_statuses.include?(last_status)
    end

    sig { returns(T::Boolean) }
    def has_status?
      last_status.present?
    end

    sig { returns(Integer) }
    def calculated_arr_in_cents
      pricing.annual_recurring_revenue.cents
    end

    # Public: Returns the base URL for our merchant account at Braintree
    sig { returns(String) }
    def self.braintree_merchant_url
      @braintree_base_url ||= T.let(
        "#{GitHub.braintree_host}#{::Braintree::Configuration.instantiate.base_merchant_path}",
        T.nilable(String)
      )
    end

    # Public: Returns the base URL for our account at Zuora
    sig { returns(String) }
    def self.zuora_url
      GitHub.zuora_host
    end

    # Public: Returns a URL to view this transaction on the processor's website
    # (e.g. Braintree or Zuora)
    sig { returns(T.nilable(String)) }
    def platform_url
      case platform
      when "braintree"
        "#{self.class.braintree_merchant_url}/transactions/#{platform_transaction_id}"
      when "zuora"
        if is_authorization?
          "#{GitHub.stripe_payments_base_url}/#{transaction_id}"
        elsif credit_balance_adjustment_transaction?
          "#{self.class.zuora_url}/apps/CreditBalanceAdjustment.do?method=view&id=#{platform_transaction_id}"
        else
          "#{self.class.zuora_url}/apps/NewPayment.do?method=view&id=#{platform_transaction_id}"
        end
      end
    end

    # Public: Returns the name of the processor's website
    # (e.g. Braintree or Zuora)
    #
    sig { returns(String) }
    def platform_name
      if is_authorization? && platform == "zuora"
        "Stripe"
      else
        platform.to_s.titlecase
      end
    end

    sig { returns(T::Boolean) }
    def credit_balance_adjustment_transaction?
      return false if transaction_id.nil?
      transaction_id.to_s.start_with?("CBA-")
    end

    # Public: Get our best guess at the plan subscription used for this billing transaction. Will either be the
    # plan subscription explicitly recorded on the transaction, or the transaction's user's current general-purpose
    # plan subscription.
    sig { returns(T.nilable(Billing::PlanSubscription)) }
    def plan_subscription
      # Safe to fall back to the general-purpose plan subscription on the billable entity if one was not
      # recorded explicitly on this transaction, because by the time we introduced the concept of plan subscriptions
      # with a different `purpose`, we were consistently specifying `plan_subscription_id` on billing transactions:
      super || billable_entity&.plan_subscription
    end

    sig { returns(T.nilable(String)) }
    def zuora_payment_gateway
      return unless payment_type = self.payment_type
      Billing::Zuora::PaymentGateway.for(user, type: payment_type.to_sym, purpose: plan_subscription&.purpose&.to_sym)
    end

    sig { returns(T.nilable(String)) }
    def stafftools_url
      return unless live_user
      UrlHelpers.stafftools_user_billing_history_url(
        live_user,
        host: GitHub.host_name,
      )
    end

    sig { params(billable_entity: ::Billing::Types::Account).returns(String) }
    def self.recent_refunded_transaction_key(billable_entity)
      "billing_transaction_refunded_#{billable_entity.class}_#{billable_entity.id}"
    end

    sig { params(billable_entity: ::Billing::Types::Account).returns(T.nilable(Billing::BillingTransaction)) }
    def self.recent_refunded_transaction(billable_entity)
      transaction_id = Billing::Kv.store.get(self.recent_refunded_transaction_key(billable_entity)).value!
      transaction_id.present? ? Billing::BillingTransaction.find(transaction_id) : nil
    end

    private

    sig { returns(T.any(Billing::Zuora::Payment, Billing::Zuora::CreditBalanceAdjustment)) }
    def platform_payment
      if credit_balance_adjustment_transaction?
        Billing::Zuora::CreditBalanceAdjustment
      else
        Billing::Zuora::Payment
      end.find(platform_transaction_id)
    end

    # Private: Copies user/business details and plan information to this billing
    # transaction.
    #
    # billable_entity    - A User/Organization/Business to copy details from.
    # charge_type        - String charge type (optional, defaults to
    #                      User#recurring_charge_type).
    #
    sig do
      params(
        billable_entity: ::Billing::Types::Account,
        charge_type: T.nilable(String)
      ).void
    end
    def copy_billable_details(billable_entity, charge_type: nil)
      if billable_entity.is_a?(Business)
        self.customer = billable_entity.customer
      else
        self.user = billable_entity
      end

      self.asset_packs_total              = billable_entity.data_packs
      self.asset_pack_unit_price_in_cents = Asset::Status.data_pack_unit_price.cents
      self.billing_email_address          = billable_entity.billing_email
      self.plan_name                      = billable_entity.plan.name
      self.plan_price_in_cents            = base_price_in_cents
      self.renewal_frequency              = billable_entity.yearly_plan? ? :yearly : :monthly
      self.seats_total                    = billable_entity.seats
      self.transaction_type               = charge_type || billable_entity.recurring_charge_type
      self.user_created_at                = billable_entity.created_at || Time.current
      self.user_login                     = billable_entity.is_a?(Business) ? nil : billable_entity.login
      self.user_type                      = billable_entity.is_a?(Business) ? nil : billable_entity.type.downcase
      self.arr_in_cents                   = calculated_arr_in_cents

      if payment_method = billable_entity.payment_method
        self.region      = payment_method.region
        self.country     = payment_method.country
        self.postal_code = payment_method.postal_code
      end

      if coupon = billable_entity.coupon
        self.coupon_name       = coupon.code
        self.discount_in_cents = billable_entity.discount * 100
      end
    end

    # Private: Copies historical plan information to this billing transaction.
    #
    # created_at - a DateTime representing when this transaction orginally took place
    sig { params(created_at: T.any(DateTime, ActiveSupport::TimeWithZone)).void }
    def copy_historical_information(created_at)
      user = T.cast(self.user, ::User)

      transaction = user.transactions.
        where(["timestamp <= ?", created_at]).
        order(:timestamp).
        last!

      coupon_redemption = user.coupon_redemptions.
        where(["created_at <= ?", created_at]).
        where(["expires_at > ?", created_at]).
        last
      coupon = coupon_redemption.try(:coupon)

      plan = transaction.current_plan
      self.plan_name = T.must(plan).name

      self.plan_price_in_cents = base_price_in_cents

      if transaction.plan_duration == User::BillingDependency::YEARLY_PLAN
        self.renewal_frequency = :yearly
      else
        self.renewal_frequency = :monthly
      end

      self.asset_packs_total = transaction.asset_packs_total
      self.seats_total = transaction.current_seats

      # NB: Since this needs to allow old coupons, we manually pass in the `discount`
      # so we don't apply normal coupon expiration rules
      # See https://github.com/github/github/blob/9da19220517/test/models/billing/billing_transaction_test.rb#L379
      pricing = Billing::Pricing.new \
        account: user,
        plan: plan,
        seats: seats_total,
        data_packs: asset_packs_total,
        plan_duration: user.plan_duration,
        discount: coupon&.discount

      pricing_attributes = {
        discount_in_cents: pricing.discount.cents,
        arr_in_cents: pricing.annual_recurring_revenue.cents,
      }

      assign_attributes(pricing_attributes)
    end

    sig { params(invoiced_items: T::Array[Billing::Zuora::InvoiceItem]).void }
    def create_recurring_line_items(invoiced_items: [])
      created_line_items = T.let([], T::Array[Billing::BillingTransaction::LineItem])
      billable_items = invoiced_billable_items(invoiced_items)
      if billable_items.any?
        created_line_items += create_billable_line_items(billable_items: billable_items)
      end
      created_line_items += create_usage_line_items(invoiced_items)

      created_line_items_product_charge_ids = created_line_items.map(&:zuora_product_rate_plan_charge_id)
      remaining_invoice_items = invoiced_items.reject do |invoice_item|
        invoice_item.product_rate_plan_charge_id.in?(created_line_items_product_charge_ids)
      end

      create_github_line_item(invoice_items: remaining_invoice_items)
    end

    sig { params(invoiced_items: T::Array[Billing::Zuora::InvoiceItem]).void }
    def update_prorated_days(invoiced_items: [])
      return unless invoiced_items.any?
      return unless prorated_charge?

      # For prorated charges, the first invoice item is enough to know the service period
      service_period = invoiced_items.filter_map do |item|
        if item.service_start_date.present? && item.service_end_date.present?
          [item.service_start_date, item.service_end_date]
        end
      end.first
      return if service_period.nil?

      # Doing an inclusive difference between the start and end dates to get the number of days
      self.prorated_days = (service_period[0].to_date..service_period[1].to_date).count
    end

    # Private: Creates line items on the transaction from usage products from the invoiced items.
    sig do
      params(invoiced_items: T::Array[Billing::Zuora::InvoiceItem])
        .returns(T::Array[Billing::BillingTransaction::LineItem])
    end
    def create_usage_line_items(invoiced_items)
      invoiced_usage_items_by_product_rate_plan_charge_id(invoiced_items).map do |item|
        line_item = line_items.create \
          description: item.charge_name,
          quantity: item.quantity,
          amount_in_cents: item.charge_amount.cents,
          service_start_date: Date.parse(item.service_start_date),
          service_end_date: Date.parse(item.service_end_date),
          extras: line_item_extras(item),
          zuora_product_rate_plan_charge_id: item.product_rate_plan_charge_id

        if line_item.errors.any?
          log_line_item_creation_error(line_item, line_item_type: "usage")
        else
          create_tax_items_for_line_item(line_item, item.taxation_items)
        end

        line_item
      end
    end

    # Private: Returns the line items from usage products.
    sig do
      params(invoiced_items: T::Array[Billing::Zuora::InvoiceItem])
        .returns(T::Array[Billing::Zuora::InvoiceItem])
    end
    def invoiced_usage_items_by_product_rate_plan_charge_id(invoiced_items)
      uuid_product_rate_plan_charge_ids = Billing::ProductUUID.metered.flat_map(&:zuora_product_rate_plan_charge_ids).flat_map(&:values)
      invoiced_items.select do |item|
        uuid_product_rate_plan_charge_ids.include?(item.product_rate_plan_charge_id)
      end
    end

    # Private: Returns the "extra" hash for a line item.
    # item - the invoiced item of type Billing::Zuora::InvoiceItem or Zuora::Billing::SubscribableInvoiceItem
    sig { params(item: T.any(Billing::Zuora::InvoiceItem, Billing::Zuora::SubscribableInvoiceItem)).returns(T.nilable(T::Hash[T.any(Symbol, String), T.untyped])) }
    def line_item_extras(item)
      if BillingTransaction::LineItem::COPILOT_FOR_BUSINESS_USAGE_DESCRIPTION == item.charge_name
        copilot_seat_history(item)
      elsif item.subscribable?
        T.cast(item, Billing::Zuora::SubscribableInvoiceItem).line_item_extras
      end
    end

    # Private: Returns the "extra" hash for a line item.
    # item - the invoiced item of type Billing::Zuora::InvoiceItem or Zuora::Billing::SubscribableInvoiceItem
    sig { params(item: T.any(Billing::Zuora::InvoiceItem, Billing::Zuora::SubscribableInvoiceItem)).returns(T::Hash[T.any(Symbol, String), T.untyped]) }
    def copilot_seat_history(item)
      seats_history = ::Copilot::SeatHistoryDetail.new(
        billable_owner: T.cast(self.billable_entity, ::Billing::Types::Account),
        start_date: Date.parse(item.service_start_date),
        end_date: Date.parse(item.service_end_date)
      ).to_h

      seats_history[:unit_price] = Billing::ProductUUID.copilot.with_product_key("business.v0").last&.base_price&.dollars || "19"
      seats_history
    end

    # billable_items - an Array of Billing::Zuora::SubscribableInvoiceItem
    sig do
      params(billable_items: T::Array[Billing::Zuora::SubscribableInvoiceItem])
        .returns(T::Array[Billing::BillingTransaction::LineItem])
    end
    def create_billable_line_items(billable_items: [])
      billing_cycle = T.cast(self.billable_entity, ::Billing::Types::Account).plan_duration # "month", "year", or nil (which should mean monthly)
      billable_items = billable_items.reject { |item| item.charge_amount.zero? } # e.g., $0 sponsorship fee

      persisted_line_items = billable_items.filter_map do |item|
        subscribable = item.subscribable
        quantity = item.quantity

        line_item = line_items.create \
          description: subscribable.line_item_description(invoice_item: item),
          quantity: quantity,
          amount_in_cents: item.charge_amount.cents,
          listing: subscribable.listing,
          subscribable: subscribable,
          arr_in_cents: subscribable.github_arr(cycle: billing_cycle, quantity: quantity),
          service_start_date: Date.parse(item.service_start_date),
          service_end_date: Date.parse(item.service_end_date),
          extras: line_item_extras(item),
          zuora_product_rate_plan_charge_id: item.product_rate_plan_charge_id

        if line_item.persisted?
          create_tax_items_for_line_item(line_item, item.taxation_items)

          line_item
        else
          log_line_item_creation_error(line_item, line_item_type: "subscription_items")
          nil
        end
      end

      after_sponsorship_billable_line_items_created(sponsors_line_items: persisted_line_items.select(&:sponsorship?))

      persisted_line_items
    end

    # Private: Returns the line items from billable products.
    #
    # invoiced_items - an Array of Billing::Zuora::InvoiceItem
    #
    # Returns an Array of Billing::Zuora::SubscribableInvoiceItem.
    sig { params(invoiced_items: T::Array[Billing::Zuora::InvoiceItem]).returns(T::Array[Billing::Zuora::SubscribableInvoiceItem]) }
    def invoiced_billable_items(invoiced_items)
      billable_items, possible_billable_items = invoiced_items.partition(&:subscribable?)
      billable_items = T.cast(billable_items, T::Array[Billing::Zuora::SubscribableInvoiceItem])

      # Track counts of tracked vs untracked sponsorship items until all
      # subscriptions have been converted.
      tracked_sponsorship_count = billable_items.count(&:sponsors_item?)

      # Until we backfill the subscribable on all Zuora subscriptions, we need to
      # check the user's active billable subscription items for matches.
      #
      # Currently, subscriptions with SponsorsTier subscribables should all be
      # tracked, but subscriptions with Marketplace::ListingPlan subscribables
      # have not yet been transitioned.
      if possible_billable_items.any?
        billable_items += matches_from_subscription_items(possible_billable_items)
      end

      total_sponsorship_count = billable_items.count(&:sponsors_item?)
      untracked_sponsorship_count = total_sponsorship_count - tracked_sponsorship_count

      # If this subscription still has untracked invoice items, schedule a plan
      # subscription sync to convert it.
      if untracked_sponsorship_count > 0
        stats_tags = ["action:resync", "source:untracked_invoice_item"]
        GitHub.dogstats.increment("sponsors.zpm_transition", tags: stats_tags)
        plan_subscription&.synchronize_later
      end

      GitHub.dogstats.count(
        "zuora.sponsors_invoice_item",
        tracked_sponsorship_count,
        tags: ["tracked:true", "transaction_type:#{transaction_type}"]
      )
      GitHub.dogstats.count(
        "zuora.sponsors_invoice_item",
        untracked_sponsorship_count,
        tags: ["tracked:false", "transaction_type:#{transaction_type}"]
      )

      combined_billable_items(billable_items)
    end

    # Private: check for subscription item matches in invoice items without subscribables.
    # This is necessary for cases where subscrible tracking in Zuora is not yet enabled.
    #
    # Example
    #
    #   # The current user has active sponsorships for "jayne" at the $5 tier and
    #   # "groot" at the $9 tier.
    #
    #   billable_items
    #   # => [
    #       #<Billing::Zuora::InvoiceItem @charge_name="sponsors-jayne - $5 per month"}>,
    #       #<Billing::Zuora::InvoiceItem @charge_name="sponsors-groot - $9 per month"}>,
    #       #<Billing::Zuora::InvoiceItem @charge_name="GitHub"}>,
    #     ]
    #
    #   matches_from_subscription_items(billable_items)
    #   # => [
    #       #<SubscribableInvoiceItem @charge_amount=500}, @subscribable=#<SponsorsTier id: 16>>,
    #       #<SubscribableInvoiceItem @charge_amount=900}, @subscribable=#<SponsorsTier id: 42>>,
    #     ]
    sig { params(possible_billable_items: T::Array[Billing::Zuora::InvoiceItem]).returns(T::Array[Billing::Zuora::SubscribableInvoiceItem]) }
    def matches_from_subscription_items(possible_billable_items)
      # Use all subscription items with the invoiced items as the source of truth
      billable_entity = T.cast(self.billable_entity, ::Billing::Types::Account)
      billable_subscription_items = billable_entity.subscription_items.includes(:subscribable)

      possible_billable_items.each_with_object([]) do |invoice_item, matched_items|
        matching_subscription_item = billable_subscription_items.detect do |subscription_item|
          subscription_item.matches_invoice_item?(invoice_item, match_copilot_cycle: true)
        end

        if matching_subscription_item
          subscribable_invoice_item = invoice_item.as_subscribable_invoice_item(
            subscribable: matching_subscription_item.subscribable
          )
          matched_items << subscribable_invoice_item
        end
      end
    end

    # Private: combine billable invoice items by subscribable.
    #
    # billable_items - Array of Billing::Zuora::SubscribableInvoiceItem
    #
    # Example
    #
    #   billable_items
    #   # => [
    #       #<SubscribableItem @charge_amount=1000}, @subscribable=#<Tier id: 16, price: 1000>>,
    #       #<SubscribableItem @charge_amount=5000}, @subscribable=#<Tier id: 42, price: 5000>>,
    #       #<SubscribableItem @charge_amount=1000}, @subscribable=#<Tier id: 16, price: 1000>>,
    #     ]
    #
    #   combined_billable_items(billable_items)
    #   # => [
    #       #<SubscribableItem @charge_amount=2000}, @subscribable=#<Tier id: 16, price: 1000>>,
    #       #<SubscribableItem @charge_amount=5000}, @subscribable=#<Tier id: 42, price: 5000>>,
    #     ]
    #
    sig { params(billable_items: T::Array[Billing::Zuora::SubscribableInvoiceItem]).returns(T::Array[Billing::Zuora::SubscribableInvoiceItem]) }
    def combined_billable_items(billable_items)
      grouped_items = if billable_entity.present?
        billable_items.group_by do |item|
          [item.subscribable, item.product_rate_plan_charge_id, item.managing_entity]
        end.values
      else
        billable_items.group_by { |item| [item.subscribable, item.product_rate_plan_charge_id] }.values
      end
      grouped_items.inject([]) do |combined, items|
        item = T.must(items.max_by(&:quantity))
        item.charge_amount = items.sum(Billing::Money.zero) { |item| item.charge_amount }
        combined << item
      end
    end

    sig do
      params(
        subscription_item: ::Billing::SubscriptionItem,
        service_percent_remaining: Float,
        plan_change: T.nilable(Billing::PlanChange)
      ).returns(::Billing::Money)
    end
    def subscription_item_cost(subscription_item, service_percent_remaining:, plan_change: nil)
      if plan_change
        plan_change.prorated_mp_price_for \
          subscription_item: subscription_item,
          service_percent_remaining: service_percent_remaining
      else
        subscription_item.price(service_remaining: service_percent_remaining)
      end
    end

    sig do
      params(
        invoice_items: T::Array[Billing::Zuora::InvoiceItem]
      ).returns(T::Array[Billing::BillingTransaction::LineItem])
    end
    def create_github_line_item(invoice_items: [])
      # Fetch all of the invoice items that are related to a GitHub Plan and build up the UUID
      # to product charge id mapping
      # Group all non zero charge amount invoice items by product charge id
      github_invoice_items_by_product_charge_id = invoice_items.select do |item|
        !item.charge_amount.zero?
      end.group_by(&:product_rate_plan_charge_id)

      return [] if github_invoice_items_by_product_charge_id.empty?

      # Create a line item for each product charge group and their corresponding tax items
      github_invoice_items_by_product_charge_id.filter_map do |product_rate_plan_charge_id, invoice_items|

        invoice_item = T.must(invoice_items.first)
        quantity = invoice_items.inject(0) do |sum, item|
          if item.charge_amount.negative?
            sum - item.quantity
          else
            sum + item.quantity
          end
        end

        line_item = line_items.create \
          description: invoice_item.charge_name,
          quantity: quantity,
          amount_in_cents: invoice_items.sum { |item| item.charge_amount.cents },
          service_start_date: Date.parse(invoice_item.service_start_date),
          service_end_date: Date.parse(invoice_item.service_end_date),
          zuora_product_rate_plan_charge_id: product_rate_plan_charge_id

        if line_item.persisted?
          create_tax_items_for_line_item(line_item, invoice_items.flat_map(&:taxation_items))

          line_item
        else
          log_line_item_creation_error(line_item, line_item_type: "github")

          nil
        end
      end
    end

    sig { returns(Integer) }
    def github_arr
      pricing.annual_recurring_revenue_details.github_total.cents
    end

    sig { returns(Integer) }
    def base_price_in_cents
      billable_entity = T.cast(self.billable_entity, ::Billing::Types::Account)

      self.plan_price_in_cents = Billing::Pricing.new(
        plan: billable_entity.plan,
        plan_duration: billable_entity.plan_duration,
      ).discounted.cents
    end

    sig { returns(Billing::Pricing) }
    def pricing
      billable_entity = T.cast(self.billable_entity, ::Billing::Types::Account)
      Billing::Pricing.new \
        account: billable_entity,
        plan: billable_entity.plan,
        seats: billable_entity.seats,
        plan_duration: billable_entity.plan_duration
    end

    sig { returns(Integer) }
    def arr_multiplier
      user = T.cast(self.user, ::User)
      user.monthly_plan? ? 12 : 1
    end

    sig { params(plan_change: Billing::PlanChange).returns(Float) }
    def service_percent_remaining(plan_change)
      if plan_change.upgrading_from_free?
        1
      else
        plan_change.service_percent_remaining
      end
    end

    #Private: Updates the transaction status of braintree transactions
    sig { void }
    def update_braintree_transaction_status
      braintree_transaction = ::Braintree::Transaction.find(transaction_id)
      if braintree_transaction.status_history.present?
        braintree_transaction.status_history.each do |status_detail|
          next if find_status(status_detail.status)
          self.statuses.build(status_detail: status_detail)
        end
        self.last_status = braintree_transaction.status
        self.settlement_batch_id ||= braintree_transaction.settlement_batch_id
      end
    end

    # Private: Calculate the recurring transaction amount in cents applied to GitHub specific expenses
    sig { returns(Integer) }
    def recurring_github_amount_in_cents
      return calculate_github_amount_with_credit if amount_in_cents
      pricing.discounted.cents + plan_subscription&.balance_in_cents.to_i
    end

    # Private: Calculates the amount spent on GitHub line items by subtracting the sum of non-github line
    # items from the transaction amount - this allows us to account for any credit that would have been
    # applied when generating the transaction
    sig { returns(Integer) }
    def calculate_github_amount_with_credit
      amount_in_cents - marketplace_line_item_amount - sponsors_line_item_amount
    end

    sig { returns(Integer) }
    def marketplace_line_item_amount
      Integer(line_items.marketplace.sum(:amount_in_cents))
    end

    sig { params(line_item: Billing::BillingTransaction::LineItem, line_item_type: String).void }
    def log_line_item_creation_error(line_item, line_item_type:)
      GitHub.logger.error(
        "Failed to create billing transaction line item",
        "gh.billing.billing_transaction.id": id,
        "gh.billing.billing_transaction.line_item.errors": line_item.errors.full_messages.join(", "),
        "gh.billing.billing_transaction.line_item.description": line_item.description,
        "gh.billing.billing_transaction.line_item.amount_in_cents": line_item.amount_in_cents,
        "gh.billing.billing_transaction.line_item.quantity": line_item.quantity,
        "gh.billing.billing_transaction.line_item.service_start_date": line_item.service_start_date,
        "gh.billing.billing_transaction.line_item.service_end_date": line_item.service_end_date,
        "gh.billing.billing_transaction.line_item.extras": line_item.extras,
        "gh.billing.billing_transaction.line_item.for": line_item_type,
        "gh.user.id": user_id,
        "gh.billing.customer.id": customer_id,
      )
      GitHub.dogstats.increment("billing.billing_transaction.line_item_creation_error")
    end

    sig { params(tax_item: Billing::BillingTransaction::TaxItem).void }
    def log_tax_item_creation_error(tax_item)
      GitHub.logger.error(
        "Failed to create billing transaction tax item",
        "gh.billing.billing_transaction.id": id,
        "gh.billing.billing_transaction.tax_item.errors": tax_item.errors.full_messages.join(", "),
        "gh.billing.billing_transaction.tax_item.amount_in_cents": tax_item.amount_in_cents,
        "gh.billing.billing_transaction.tax_item.exempt_amount_in_cents": tax_item.exempt_amount_in_cents,
        "gh.billing.billing_transaction.tax_item.country": tax_item.country,
        "gh.billing.billing_transaction.tax_item.name": tax_item.name,
        "gh.billing.billing_transaction.tax_item.jurisdiction": tax_item.jurisdiction,
        "gh.billing.billing_transaction.tax_item.location_code": tax_item.location_code,
        "gh.billing.billing_transaction.tax_item.tax_code": tax_item.tax_code,
        "gh.billing.billing_transaction.tax_item.tax_code_description": tax_item.tax_code_description,
        "gh.billing.billing_transaction.tax_item.tax_date": tax_item.tax_date,
        "gh.billing.billing_transaction.tax_item.tax_rate": tax_item.tax_rate,
        "gh.billing.billing_transaction.tax_item.tax_rate_description": tax_item.tax_rate_description,
        "gh.billing.billing_transaction.tax_item.tax_rate_type": tax_item.tax_rate_type,
        "gh.billing.billing_transaction.tax_item.source_id": tax_item.id,
        "gh.billing.billing_transaction.tax_item.source_name": tax_item.source_name,
        "gh.billing.billing_transaction.tax_item.line_item_id": tax_item.billing_transaction_line_item_id,
        "gh.user.id": user_id,
        "gh.billing.customer.id": customer_id,
      )
      GitHub.dogstats.increment("billing.billing_transaction.tax_item_creation_error")
    end

    sig do
      params(
        line_item: Billing::BillingTransaction::LineItem,
        taxation_items: T::Array[Billing::Zuora::TaxationItem]
      ).void
    end
    def create_tax_items_for_line_item(line_item, taxation_items)
      tax_items_created = 0
      success = true

      # The max retry count is arbitrary and can be adjusted as needed
      Billing::BillingTransaction::TaxItem.throttle_writes_with_retry(max_retry_count: 3) do
        taxation_items.each do |zuora_tax_item|
          tax_item = line_item.create_tax_item_from_source(zuora_tax_item)
          if tax_item.errors.any?
            log_tax_item_creation_error(tax_item)
          end

          tax_items_created += 1
        end
      end
    rescue Freno::Throttler::Error => e
      # Rescue and log the error if the write was throttled but don't fail rest of recording
      GitHub.dogstats.increment("billing.billing_transaction.tax_item_creation_throttled")
      GitHub.logger.error(
        "Failed to create billing transaction tax items due to throttling",
        error: e,
        "gh.billing.billing_transaction.id": id,
        "gh.billing.billing_transaction.line_item.id": line_item.id
      )
      success = false
    ensure
      cream = taxation_items.sum { |item| item.tax_amount.cents }
      tags = ["success:#{success}"]
      GitHub.dogstats.count("billing.billing_transaction.tax_item.diff", taxation_items.size - tax_items_created.to_i, tags: tags)
      GitHub.dogstats.count("billing.billing_transaction.tax_item.created", tax_items_created.to_i, tags: tags)
      GitHub.dogstats.count("billing.billing_transaction.tax_item.cream", cream, tags: tags)
    end

    sig { void }
    def cache_refunded_transaction
      account = billable_entity
      return if account.nil? || account.is_a?(Billing::DeadUser)
      Billing::Kv.store.set(self.class.recent_refunded_transaction_key(account), self.id.to_s, expires: 15.minutes.from_now)
    end
  end
end
