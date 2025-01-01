# typed: strict
# frozen_string_literal: true

# Public: Allows creating an invoice on Stripe for a particular Stripe customer so that they can add to their
# sponsorship balance. Used for Sponsors-invoiced organizations to pay for their sponsorships.
class Sponsors::CreateStripeInvoice
  extend T::Sig
  include GitHub::Memoizer

  # Public: Get the URL to view a Stripe invoice on the Stripe dashboard.
  #
  # stripe_invoice_id - String ID of a Stripe::Invoice
  #
  # Returns a String.
  sig { params(stripe_invoice_id: String).returns(String) }
  def self.stripe_invoice_url_for(stripe_invoice_id)
    "#{GitHub.stripe_invoices_base_url}/#{stripe_invoice_id}"
  end

  class Result
    extend T::Sig

    sig { params(error: String).returns(Result) }
    def self.failure(error)
      new(error: error)
    end

    sig { params(invoice: Stripe::Invoice, total_cents: T.any(Integer, BigDecimal)).returns(Result) }
    def self.success(invoice, total_cents)
      new(invoice: invoice, total_cents: total_cents)
    end

    sig do
      params(
        invoice: T.nilable(Stripe::Invoice),
        error: T.nilable(String),
        total_cents: T.any(Integer, BigDecimal)
      ).void
    end
    def initialize(invoice: nil, error: nil, total_cents: 0)
      @invoice = invoice
      @error = error
      @total_money = T.let(Billing::Money.new(total_cents), Billing::Money)
    end

    sig { returns(T.nilable(Stripe::Invoice)) }
    attr_reader :invoice

    sig { returns(T.nilable(String)) }
    attr_reader :error

    sig { returns(Billing::Money) }
    attr_reader :total_money

    sig { returns(T::Boolean) }
    def success?
      error.blank? && invoice.present?
    end

    sig { returns(T.nilable(String)) }
    def invoice_url
      return unless invoice
      Sponsors::CreateStripeInvoice.stripe_invoice_url_for(T.unsafe(T.must(invoice)).id)
    end
  end

  # Public: Create an invoice on Stripe to get an organization to increase their available sponsorship balance.
  #
  # inputs - a Hash with the following keys:
  #   :actor - the User who is creating the invoice
  #   :org - the Organization the invoice is for
  #   :stripe_customer_id - String ID of a Stripe customer, e.g., "cus_NWHTE7nqw3aEcZ"
  #   :amount_in_dollars - String representing the invoice amount in US dollars, e.g., "5000.00" for $5,000.00 USD
  #   :should_finalize - a Boolean indicating if the invoice should be finalized after creation and sent to the user.
  #   :purchase_order_number - a String with the purchase order number if one was required, nil otherwise
  #   :fee_percentage - Integer percentage that should be withheld from the total amount that's eventually
  #                     transferred to their sponsorship credit balance as a service fee, to be retained by GitHub,
  #                     e.g., 3 for a 3% fee
  #
  # Returns a Sponsors::CreateStripeInvoice::Result.
  sig { params(inputs: T::Hash[T.any(String, Symbol), T.untyped]).returns(Result) }
  def self.call(inputs)
    new(**T.unsafe(inputs)).call
  end

  sig do
    params(
      actor: T.nilable(User),
      org: T.nilable(T.any(Organization, User)),
      stripe_customer_id: String,
      amount_in_dollars: T.nilable(String),
      should_finalize: T::Boolean,
      purchase_order_number: T.nilable(String),
      fee_percentage: T.nilable(T.any(Integer, String)),
    ).void
  end
  def initialize(
    actor:,
    org:,
    stripe_customer_id:,
    amount_in_dollars:,
    should_finalize:,
    purchase_order_number: nil,
    fee_percentage: 0
  )
    @actor = actor
    @org = org
    @purchase_order_number = purchase_order_number
    @stripe_customer_id = stripe_customer_id
    @amount_in_dollars = amount_in_dollars
    @fee_percentage = T.let((fee_percentage.presence || 0).to_i, Integer)
    @should_finalize = should_finalize
    @invoice = T.let(nil, T.nilable(Stripe::Invoice))
  end

  sig { returns(Result) }
  def call
    error_message = validate
    return Result.failure(error_message) if error_message

    error = create_invoice
    return Result.failure("Failed to create invoice: #{error}") if error

    error = create_invoice_items
    return Result.failure("Failed to add items to invoice: #{error}") if error

    if should_finalize?
      error = finalize_invoice
      return Result.failure("Failed to finalize invoice: #{error}") if error
    end

    total_cents = fee_amount_in_cents + non_fee_amount_in_cents
    instrument_invoice_create
    Result.success(T.must(invoice), total_cents)
  end

  private

  sig { returns(T.nilable(T.any(Organization, User))) }
  attr_reader :org

  sig { returns(T.nilable(String)) }
  attr_reader :purchase_order_number

  sig { returns(Integer) }
  attr_reader :fee_percentage

  sig { returns(String) }
  attr_reader :stripe_customer_id

  sig { returns(T.nilable(String)) }
  attr_reader :amount_in_dollars

  sig { returns(T::Boolean) }
  attr_reader :should_finalize

  sig { returns(T.nilable(Stripe::Invoice)) }
  attr_reader :invoice

  sig { returns(T.nilable(User)) }
  attr_reader :actor

  alias :should_finalize? :should_finalize

  sig { returns(T.nilable(String)) }
  def validate
    return "GitHub Sponsors is not a feature." unless GitHub.sponsors_enabled?
    return "Please specify who is creating the invoice." unless actor&.user?
    return "Please specify which organization should receive the invoice." unless org&.organization?
    return "Please specify the dollar amount of the invoice." unless amount_in_dollars
    return "Please specify an amount that is at least #{minimum_amount_in_dollars}." unless minimum_amount_met?
    return "Please specify which Stripe customer should receive the invoice." if stripe_customer_id.blank?
    return "Organization must be signed up for invoicing before creating an invoice." unless org&.sponsors_invoiced?

    nil
  end

  sig { returns(T.nilable(String)) }
  def create_invoice
    @invoice = begin
      # See https://stripe.com/docs/api/invoices/create?lang=ruby
      Stripe::Invoice.create(
        # Never move out of 'draft' automatically because we need a human to review, such as someone from finance for
        # a staff-created invoice:
        auto_advance: false,

        automatic_tax: { enabled: false },
        collection_method: "send_invoice",
        currency: "usd",
        customer: stripe_customer_id,
        description: invoice_description,
        due_date: (GitHub::Billing.now + 1.month).to_i,
        footer: "GitHub Sponsors",
        metadata: invoice_metadata,
        pending_invoice_items_behavior: "exclude", # create an empty draft invoice that we'll append items to
        payment_settings: {
          payment_method_types: %w[ach_credit_transfer cashapp], # this list is meant to exclude the "card" method
        },
      )
    rescue Stripe::InvalidRequestError => err
      return err.message
    end

    nil # no error
  end

  sig { returns(T.nilable(String)) }
  def create_invoice_items
    error = create_invoice_item(description: "GitHub Sponsors Program", amount_in_cents: non_fee_amount_in_cents,
      is_fee: false)
    return error if error

    if fee_percentage > 0
      error = create_invoice_item(description: "Service Fee (#{fee_percentage}%)", is_fee: true,
        amount_in_cents: fee_amount_in_cents)
      return error if error
    end

    nil # no error
  end

  sig do
    params(
      description: String,
      amount_in_cents: T.any(Integer, BigDecimal),
      is_fee: T::Boolean
    ).returns(T.nilable(String))
  end
  def create_invoice_item(description:, amount_in_cents:, is_fee:)
    params = invoice_item_creation_params_for(description: description, amount_in_cents: amount_in_cents,
      is_fee: is_fee)

    begin
      # See https://stripe.com/docs/api/invoiceitems/create?lang=ruby
      Stripe::InvoiceItem.create(params)
    rescue Stripe::InvalidRequestError => err
      return err.message
    end

    nil # no error
  end

  sig { returns(T.nilable(String)) }
  def finalize_invoice
    invoice_id = T.must(invoice)["id"]

    @invoice = begin
      Stripe::Invoice.finalize_invoice(
        invoice_id,
        # `auto_advance` must be true for us to email the invoice to user automatically
        auto_advance: true,
      )
    rescue Stripe::InvalidRequestError => err
      return err.message
    end

    nil # no error
  end

  sig { returns(String) }
  def invoice_description
    if purchase_order_number.present?
      "PO ##{purchase_order_number}\nGitHub Sponsors"
    else
      "GitHub Sponsors"
    end
  end

  sig do
    params(
      description: String,
      amount_in_cents: T.any(Integer, String, BigDecimal),
      is_fee: T::Boolean
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def invoice_item_creation_params_for(description:, amount_in_cents:, is_fee:)
    period_start_and_end = GitHub::Billing.now.to_i

    params = {
      currency: "usd",
      customer: stripe_customer_id,
      description: description,
      discountable: true,
      invoice: T.unsafe(T.must(invoice)).id,
      period: { start: period_start_and_end, end: period_start_and_end },
      quantity: 1,
      tax_behavior: "unspecified",
    }

    if is_fee
      params[:metadata] = { service_fee: true }
    end

    if amount_in_cents.is_a?(Integer)
      params[:unit_amount] = amount_in_cents
    else
      params[:unit_amount_decimal] = amount_in_cents
    end

    params
  end

  sig { returns(Billing::Money) }
  memoize def amount_as_money
    Billing::Money.parse(amount_in_dollars)
  end

  sig { returns(BigDecimal) }
  memoize def fee_amount_in_cents
    amount_as_money.cents * fee_percentage / BigDecimal(100)
  end

  sig { returns(BigDecimal) }
  def non_fee_amount_in_cents
    amount_as_money.cents - fee_amount_in_cents
  end

  sig { returns(T::Boolean) }
  def minimum_amount_met?
    amount_as_money.cents >= Customer::SponsorsDependency::MINIMUM_INVOICE_AMOUNT_IN_CENTS
  end

  sig { returns(String) }
  def minimum_amount_in_dollars
    Billing::Money.new(Customer::SponsorsDependency::MINIMUM_INVOICE_AMOUNT_IN_CENTS).format(
      no_cents_if_whole: true,
      with_currency: true,
    )
  end

  sig { returns(T::Hash[Symbol, String]) }
  memoize def invoice_metadata
    metadata = {
      receiving_org: T.must(org).login,
      actor: T.must(actor).login,
    }

    metadata[:purchase_order_number] = purchase_order_number if purchase_order_number.present?

    metadata
  end

  sig { void }
  def instrument_invoice_create
    stripe_invoice = invoice
    return unless stripe_invoice.present?
    Billing::Stripe::Invoice.from_invoice(stripe_invoice).instrument(action: "CREATE")
  end
end
