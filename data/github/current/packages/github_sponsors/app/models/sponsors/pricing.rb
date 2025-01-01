# typed: strict
# frozen_string_literal: true

# PORO that support Sponsors pricing information.
#
# * Tier, checkout, and renewal net and fee prices
#   * tier prices are passed to the billing system for the new tier (which may subsequently be prorated)
#   * checkout prices describe the amount due today (approximating the billing system's proration behavior)
#   * renewal prices describe the amount due on the next billing cycle (if relevant)
# * Change type (i.e. upgrade, downgrade, or new sponsorship)
# * Available payment options (e.g. pay-in-full or prorated)
module Sponsors
  class Pricing
    extend T::Sig

    include GitHub::Memoizer

    # Private: Percent of the sponsorship payment we retain as GitHub as a service fee.
    PERCENT_SERVICE_FEE = 3
    private_constant :PERCENT_SERVICE_FEE

    # Private: Percent of the sponsorship payment we retain as GitHub as a transaction fee
    # for credit card payments.
    PERCENT_TRANSACTION_FEE = 3
    private_constant :PERCENT_TRANSACTION_FEE

    # Public: Percent fee charged to Sponsors-invoiced orgs
    PERCENT_SPONSORS_INVOICED_FEE = PERCENT_SERVICE_FEE

    # Public: Percent fee charged to orgs paying via credit card
    PERCENT_CREDIT_CARD_FEE = T.let(PERCENT_SERVICE_FEE + PERCENT_TRANSACTION_FEE, Integer)

    class ListingMismatchError < StandardError; end
    class PaymentOptionError < StandardError; end

    class PaymentOption < T::Enum
      enums do
        Default = new # use the default given the situation (e.g. full for one-time, prorated for new recurring)
        Prorated = new # pay a prorated amount now, and the full amount on the next billing cycle
        Full = new # pay the renewal amount now and again on the next billing cycle
        Delayed = new # pay nothing now, and the full amount on the next billing cycle
      end
    end

    class Change < T::Enum
      enums do
        New = new # new sponsorship
        Upgrade = new # changing to a higher-amount tier, only possible if recurring
        Downgrade = new # changing to a lower-amount tier, only possible if recurring
      end
    end

    sig do
      params(
        sponsor: T.any(User, Organization),
        new_tier: T.nilable(SponsorsTier),
        current_tier: T.nilable(SponsorsTier),
        bulk_sponsorship_rows: T::Array[BulkSponsorshipRow]
      ).void
    end
    def initialize(sponsor:, new_tier: nil, current_tier: nil, bulk_sponsorship_rows: [])
      @sponsor = sponsor
      @new_tier = new_tier
      @current_tier = current_tier
      @bulk_sponsorship_rows = bulk_sponsorship_rows

      validate
    end

    sig { returns Billing::Money }
    def tier_price
      tier_net_price + tier_fee_price
    end

    sig { returns Billing::Money }
    def tier_net_price
      incoming_tier = new_tier
      return Billing::Money.zero unless incoming_tier.present?

      if incoming_tier.recurring?
        incoming_tier.to_money * duration_factor
      else
        incoming_tier.to_money
      end
    end

    sig { returns Billing::Money }
    def tier_fee_price
      tier_net_price * fee_percent
    end

    sig { returns Billing::Money }
    def sponsorship_rows_net_price
      @bulk_sponsorship_rows.inject(Billing::Money.zero) do |sum, row|
        row_duration_factor = row.recurring? ? duration_factor : 1
        amount = row.amount * row_duration_factor
        sum + amount
      end
    end

    sig { params(payment_option: PaymentOption).returns(Billing::Money) }
    def checkout_price(payment_option: PaymentOption::Default)
      checkout_net_price(payment_option: payment_option) + checkout_fee_price(payment_option: payment_option)
    end

    sig { params(payment_option: PaymentOption).returns(Billing::Money) }
    def checkout_net_price(payment_option: PaymentOption::Default)
      # use local vars so Sorbet can statically track enums
      change = change_type
      option = payment_option

      if option != PaymentOption::Default && !available_payment_options.include?(option)
        raise PaymentOptionError.new("Invalid payment option")
      end

      net_price = bulk_sponsorship? ? sponsorship_rows_net_price : tier_net_price

      case change
      when Change::New
        case option
        when PaymentOption::Default, PaymentOption::Prorated
          net_price * service_percent_remaining
        when PaymentOption::Full
          net_price
        when PaymentOption::Delayed
          Billing::Money.zero
        else T.absurd(option)
        end
      when Change::Upgrade
        case option
        when PaymentOption::Default, PaymentOption::Prorated
          price_difference = new_tier.to_money - current_tier.to_money
          price_difference * duration_factor * service_percent_remaining
        when PaymentOption::Full
          raise PaymentOptionError.new("Upgrades only support prorated payments")
        when PaymentOption::Delayed
          raise PaymentOptionError.new("Upgrades only support prorated payments")
        else T.absurd(option)
        end
      when Change::Downgrade
        case option
        when PaymentOption::Prorated
          raise PaymentOptionError.new("Downgrades only support delayed payments")
        when PaymentOption::Full
          raise PaymentOptionError.new("Downgrades only support delayed payments")
        when PaymentOption::Default, PaymentOption::Delayed
          Billing::Money.zero
        else T.absurd(option)
        end
      else T.absurd(change)
      end
    end

    sig { params(payment_option: PaymentOption).returns(Billing::Money) }
    def checkout_fee_price(payment_option: PaymentOption::Default)
      checkout_net_price(payment_option: payment_option) * fee_percent
    end


    # Public: Hypothetical savings if the user were to join Sponsors invoicing
    #
    # While we charge Sponsors-invoiced users a fee at time of invoicing, this allows us to attempt to upsell folks
    # by providing a comparison during checkout.
    sig { params(payment_option: PaymentOption).returns(Billing::Money) }
    def checkout_sponsors_invoiced_savings(payment_option: PaymentOption::Default)
      current_fee = checkout_fee_price(payment_option: payment_option)
      sponsors_invoiced_fee = checkout_net_price(payment_option: payment_option) * sponsors_invoiced_fee_percent
      sponsors_invoiced_fee < current_fee ? current_fee - sponsors_invoiced_fee : Billing::Money.zero
    end

    sig { returns Billing::Money }
    def renewal_price
      renewal_net_price + renewal_fee_price
    end

    sig { returns Billing::Money }
    def renewal_net_price
      return Billing::Money.zero unless recurring?

      return sponsorship_rows_net_price if bulk_sponsorship?

      incoming_tier = T.must(new_tier)
      Billing::Money.new(incoming_tier.monthly_price_in_cents * duration_factor)
    end

    sig { returns Billing::Money }
    def renewal_fee_price
      renewal_net_price * fee_percent
    end

    sig { returns T::Array[PaymentOption] }
    def available_payment_options
      return [PaymentOption::Full] unless recurring?

      change = change_type

      case change
      when Change::New
        options = T.let([PaymentOption::Prorated], T::Array[PaymentOption])
        if checkout_price != renewal_price && sponsor.can_skip_sponsorship_proration?
          options << PaymentOption::Full
        end
        if sponsor.can_schedule_sponsorships?
          options << PaymentOption::Delayed
        end
        options
      when Change::Upgrade
        [PaymentOption::Prorated]
      when Change::Downgrade
        [PaymentOption::Delayed]
      else T.absurd(change)
      end
    end

    sig { returns Change }
    def change_type
      return Change::New if bulk_sponsorship?

      # use local vars so Sorbet can statically track nil checking (yup, its awkard :-)
      incoming_tier = new_tier
      existing_tier = current_tier
      return Change::New unless incoming_tier&.recurring? && existing_tier&.recurring?

      incoming_tier_price = incoming_tier.monthly_price_in_cents
      existing_tier_price = existing_tier.monthly_price_in_cents
      incoming_tier_price > existing_tier_price ? Change::Upgrade : Change::Downgrade
    end

    private

    sig { returns T.any(User, Organization) }
    attr_reader :sponsor

    sig { returns T.nilable(SponsorsTier) }
    attr_reader :new_tier

    sig { returns T.nilable(SponsorsTier) }
    attr_reader :current_tier

    sig { void }
    def validate
      if new_tier.nil? && !bulk_sponsorship?
        raise ArgumentError.new("new_tier or bulk_sponsorship_rows must be provided")
      end

      if bulk_sponsorship? && @bulk_sponsorship_rows.map(&:recurring?).uniq.size > 1
        raise ArgumentError.new("All bulk sponsorships must have the same frequency")
      end

      existing_tier = current_tier
      incoming_tier = new_tier

      return unless existing_tier.present? && incoming_tier.present?
      if incoming_tier.sponsors_listing_id != existing_tier.sponsors_listing_id
        raise ListingMismatchError.new("Current and new tier must be for the same listing")
      end
    end

    sig { returns Integer }
    memoize def duration_factor
      sponsor.yearly_sponsors_plan? ? 12 : 1
    end

    sig { returns Rational }
    memoize def fee_percent
      if sponsor.user? || sponsor.sponsors_invoiced?
        Rational(0)
      else
        Rational(PERCENT_CREDIT_CARD_FEE, 100)
      end
    end

    sig { returns Rational }
    memoize def sponsors_invoiced_fee_percent
      Rational(PERCENT_SPONSORS_INVOICED_FEE, 100)
    end

    sig { returns Rational }
    memoize def service_percent_remaining
      next_sponsors_billing_date = sponsor.next_sponsors_billing_date
      return Rational(1) unless next_sponsors_billing_date > GitHub::Billing.today

      service_duration_in_days = if sponsor.yearly_sponsors_plan?
        12.months / 1.day
      else
        1.month / 1.day
      end

      service_days_remaining = next_sponsors_billing_date - GitHub::Billing.today - 1

      service_percent_remaining = Rational(service_days_remaining, service_duration_in_days)
      service_percent_remaining.clamp(Rational(0), Rational(1))
    end

    sig { returns T::Boolean }
    memoize def recurring?
      new_tier&.recurring? || recurring_bulk_sponsorship?
    end

    sig { returns T::Boolean }
    memoize def bulk_sponsorship?
      @bulk_sponsorship_rows.present?
    end

    sig { returns T::Boolean }
    memoize def recurring_bulk_sponsorship?
      return false unless bulk_sponsorship?

      # we currently enforce that bulk sponsorships can only be made with one frequency
      bulk_sponsorship_row = T.must(@bulk_sponsorship_rows.first)
      bulk_sponsorship_row.recurring?
    end
  end
end
