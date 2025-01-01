# typed: strict
# frozen_string_literal: true

module Sponsors
  module Sponsorables
    class PlanPricingComponent < ApplicationComponent
      extend T::Sig
      include HydroHelper
      include SponsorsButtonsHelper

      # sponsor - the User or Organization that is doing the sponsoring
      # sponsorable - the User or Organization that is being sponsored;
      #               required if not bulk_sponsorship
      # selected_tier - SponsorsTier selected to start sponsorship with or
      #                 modified `current_sponsorship` to; required if not bulk_sponsorship
      # pay_prorated - Boolean indicating whether the sponsor should pay a
      #                prorated amount for the `selected_tier`
      # current_sponsorship - current Sponsorship from the `sponsor` to the
      #                       sponsorable; optional
      # active_on - Date a delayed sponsorship will be activated
      # via_bulk_sponsorship - Boolean indicating whether the sponsor is making
      #                        multiple sponsorships at once; optional
      # sponsorship_rows - Array of Sponsors::BulkSponsorshipRow for bulk sponsorships;
      #                    required if `bulk_sponsorship` is true
      sig do
        params(
          sponsor: T.any(User, Organization),
          sponsorable: T.nilable(T.any(User, Organization)),
          selected_tier: T.nilable(SponsorsTier),
          pay_prorated: T::Boolean,
          current_sponsorship: T.nilable(Sponsorship),
          active_on: T.nilable(Date),
          via_bulk_sponsorship: T::Boolean,
          sponsorship_rows: T::Array[Sponsors::BulkSponsorshipRow],
        ).void
      end
      def initialize(sponsor:,
        sponsorable: nil,
        selected_tier: nil,
        pay_prorated: true,
        current_sponsorship: nil,
        active_on: nil,
        via_bulk_sponsorship: false,
        sponsorship_rows: []
      )
        @sponsor = sponsor
        @sponsorable = sponsorable
        @selected_tier = selected_tier
        @pay_prorated = pay_prorated
        @current_sponsorship = current_sponsorship
        @active_on = active_on
        @via_bulk_sponsorship = via_bulk_sponsorship
        @sponsorship_rows = sponsorship_rows
      end

      private

      sig { returns T::Boolean }
      def render?
        return false unless logged_in?
        return false if single_sponsorship_without_sponsorable?
        return false if single_sponsorship_without_new_tier?
        return false if bulk_sponsorship_without_sponsorship_rows?

        bulk_sponsorship? || matches_current_sponsorship?
      end

      sig { returns T.any(User, Organization) }
      memoize def sponsorable
        T.must(@sponsorable)
      end

      sig { returns SponsorsTier }
      memoize def selected_tier
        T.must(@selected_tier)
      end

      sig { returns Sponsors::Pricing }
      memoize def pricing
        Sponsors::Pricing.new(
          sponsor: @sponsor,
          new_tier: @selected_tier,
          current_tier: @current_sponsorship&.tier,
          bulk_sponsorship_rows: @sponsorship_rows,
        )
      end

      sig { returns String }
      def invoice_billing_support_url
        SponsorsListing.support_url(subject: SponsorsPrimerMailer::INVOICE_BALANCE_SUPPORT_SUBJECT)
      end

      sig { returns String }
      def create_invoice_url
        new_org_sponsoring_invoice_path(@sponsor)
      end

      sig { returns T::Boolean }
      memoize def invoiced_sponsor_has_insufficient_funds?
        if @sponsor.sponsors_invoiced?
          !@sponsor.sufficient_invoiced_sponsor_balance?(payment_amount_with_fee)
        else
          false
        end
      end

      sig { returns T::Boolean }
      def pay_prorated?
        @pay_prorated
      end

      sig { returns String }
      memoize def formatted_payment_amount_with_fee
        payment_amount_with_fee.format
      end

      sig { returns String }
      memoize def formatted_renewal_price_with_fee
        renewal_price_with_fee.format
      end

      sig { returns Billing::Money }
      memoize def payment_amount_with_fee
        pricing.checkout_price(payment_option: payment_option)
      end

      sig { returns Billing::Money }
      memoize def payment_amount_excluding_fee
        pricing.checkout_net_price(payment_option: payment_option)
      end

      sig { returns String }
      memoize def formatted_fee
        (payment_amount_with_fee - payment_amount_excluding_fee).format
      end

      sig { returns T::Boolean }
      memoize def prorated_and_renewal_price_differ?
        return false unless recurring?
        pricing.checkout_price != pricing.renewal_price
      end

      sig { returns Sponsors::Pricing::PaymentOption }
      def payment_option
        options = pricing.available_payment_options
        return T.must(options.first) if options.count == 1
        return Sponsors::Pricing::PaymentOption::Prorated unless prorated_and_renewal_price_differ?

        if @active_on.present?
          Sponsors::Pricing::PaymentOption::Delayed
        elsif pay_prorated?
          Sponsors::Pricing::PaymentOption::Prorated
        else
          Sponsors::Pricing::PaymentOption::Full
        end
      end

      sig { returns String }
      def upgrade_bill_description
        "Why is the amount different from the tier I selected? We charge the difference between your current " \
          "sponsorship and your new sponsorship when you upgrade."
      end

      sig { returns T.nilable(String) }
      def bill_description
        return unless recurring? && prorated_and_renewal_price_differ? && !downgrade?
        return upgrade_bill_description if upgrade?

        case payment_option
        when Sponsors::Pricing::PaymentOption::Prorated
          "You're in the middle of your billing cycle and can pay a prorated amount."
        when Sponsors::Pricing::PaymentOption::Full
          "You've chosen to pay the full sponsorship amount."
        when Sponsors::Pricing::PaymentOption::Delayed
          safe_join([
            "You've chosen to schedule your sponsorship when your billing cycle starts on ",
            rendered_next_billing_date,
            "."
          ])
        end
      end

      sig { returns T::Boolean }
      def billing_date_today?
        @sponsor.next_sponsors_billing_date == GitHub::Billing.today
      end

      sig { returns String }
      def rendered_next_billing_date
        render(Primer::Beta::Text.new(tag: :span, font_weight: :bold).with_content(next_billing_date))
      end

      sig { returns String }
      def next_bill_description
        return "" unless recurring?

        next_billing_date_text = if billing_date_today?
          "Next #{@sponsor.sponsors_plan_duration} your "
        else
          safe_join([
            "On ",
            rendered_next_billing_date,
            ", your #{@sponsor.sponsors_plan_duration}ly "
          ])
        end

        safe_join([
          next_billing_date_text,
          "billing cycle starts again and you will see a charge for ",
          render(
            Primer::Beta::Text.new(tag: :span, font_weight: :bold).with_content(formatted_renewal_price_with_fee)
          ),
          ". ",
          "You can cancel at any time."
        ])
      end

      sig { returns T::Hash[Symbol, T.untyped] }
      memoize def base_payment_option_url_params
        url_params = { sponsor: @sponsor }
        if bulk_sponsorship?
          url_params[:frequency] = recurring_bulk_sponsorship? ? :recurring : :one_time
        elsif selected_tier.persisted?
          url_params[:tier_id] = selected_tier.id
        else
          url_params[:amount] = selected_tier.monthly_price_in_dollars
        end
        url_params
      end

      sig { params(payment_option: Sponsors::Pricing::PaymentOption).returns(String) }
      def payment_option_url(payment_option:)
        payment_params = case payment_option
        when Sponsors::Pricing::PaymentOption::Prorated
          { pay_prorated: true }
        when Sponsors::Pricing::PaymentOption::Full
          { pay_prorated: false }
        when Sponsors::Pricing::PaymentOption::Delayed
          { active_on: @sponsor.next_sponsors_billing_date }
        when Sponsors::Pricing::PaymentOption::Default
          {}
        else
          T.absurd(payment_option)
        end

        url_params = base_payment_option_url_params.merge(payment_params)
        if bulk_sponsorship?
          sponsors_bulk_sponsorship_checkout_path(url_params)
        else
          sponsorable_sponsorships_path(@sponsorable, url_params)
        end
      end

      sig { params(payment_option: Sponsors::Pricing::PaymentOption).returns(String) }
      def payment_option_label(payment_option:)
        case payment_option
        when Sponsors::Pricing::PaymentOption::Prorated
          "Prorated amount"
        when Sponsors::Pricing::PaymentOption::Full
          "Full amount"
        when Sponsors::Pricing::PaymentOption::Delayed
          "Pay later"
        when Sponsors::Pricing::PaymentOption::Default
          ""
        else
          T.absurd(payment_option)
        end
      end

      # Returns an Array of Hashes of data for Primer::Alpha::SegmentedControl payment option items
      sig { returns T::Array[T::Hash[Symbol, T.untyped]] }
      def payment_options
        available_options = pricing.available_payment_options
        return [] unless available_options.count > 1

        available_options.filter_map do |option|
          {
            tag: :a,
            label: payment_option_label(payment_option: option),
            selected: option == payment_option,
            data: hydro_click_data(payment_option: option),
            href: payment_option_url(payment_option: option),
          }.merge(test_selector_data_hash("payment-option-link"))
        end
      end

      sig { returns Billing::Money }
      memoize def renewal_price
        pricing.renewal_net_price
      end

      sig { returns Billing::Money }
      memoize def renewal_price_with_fee
        pricing.renewal_price
      end

      sig { returns T.nilable(String) }
      def next_billing_date
        @sponsor.formatted_next_sponsors_billing_date
      end

      sig { returns T::Boolean }
      def upgrade?
        pricing.change_type == Sponsors::Pricing::Change::Upgrade
      end

      sig { returns T::Boolean }
      def downgrade?
        return false unless @current_sponsorship.present?
        selected_tier.monthly_price_in_cents < @current_sponsorship.monthly_price_in_cents
      end

      sig { returns T::Boolean }
      def recurring?
        if bulk_sponsorship?
          # we currently enforce that bulk sponsorships can only be made with one frequency
          bulk_sponsorship_row = T.must(@sponsorship_rows.first)
          bulk_sponsorship_row.recurring?
        else
          selected_tier.recurring?
        end
      end

      sig { returns T::Boolean }
      def show_plan_pricing_breakdown?
        !@sponsor.invoiced?
      end

      sig { returns T::Array[SponsorsListing] }
      memoize def listings
        if bulk_sponsorship?
          @sponsorship_rows.map(&:approved_sponsors_listing)
        else
          [sponsorable.sponsors_listing]
        end
      end

      sig { returns T::Boolean }
      def matches_current_sponsorship?
        # there's no current sponsorship, so we don't have to match anything
        return true if @current_sponsorship.blank?

        selected_tier.sponsors_listing_id == @current_sponsorship.sponsors_listing_id &&
          @sponsor.id == @current_sponsorship.sponsor_id &&
          sponsorable.id == @current_sponsorship.sponsorable_id
      end

      sig { returns T::Boolean }
      memoize def bulk_sponsorship?
        @via_bulk_sponsorship
      end

      sig { returns T::Boolean }
      def single_sponsorship_without_sponsorable?
        !bulk_sponsorship? && @sponsorable.blank?
      end

      sig { returns T.nilable(SponsorsTier) }
      def current_recurring_tier
        if @current_sponsorship&.active? && @current_sponsorship.recurring_payment?
          @current_sponsorship.tier
        end
      end

      sig { returns T::Boolean }
      def single_sponsorship_without_new_tier?
        return false if bulk_sponsorship?

        @selected_tier.blank? || @selected_tier == current_recurring_tier
      end

      sig { returns T::Boolean }
      def bulk_sponsorship_without_sponsorship_rows?
        bulk_sponsorship? && @sponsorship_rows.blank?
      end

      sig { returns Billing::Money }
      memoize def fee_savings_by_switching_to_invoiced_billing
        pricing.checkout_sponsors_invoiced_savings
      end

      sig { returns String }
      def switch_to_invoiced_billing_link
        org_sponsoring_billing_options_path(@sponsor)
      end

      sig { returns T.nilable(String) }
      def invoiced_billing_hydro_data
        safe_data_attributes(sponsors_button_hydro_attributes(
          :INVOICED_BILLING_SETUP_CHECKOUT_FEE,
          @sponsor.display_login,
        ))
      end

      sig { params(payment_option: Sponsors::Pricing::PaymentOption).returns(T::Hash[Symbol, String]) }
      def hydro_click_data(payment_option:)
        option = payment_option
        button_name = case option
        when Sponsors::Pricing::PaymentOption::Full
          "PAY_SPONSORSHIP_IN_FULL"
        when Sponsors::Pricing::PaymentOption::Prorated
          "PAY_SPONSORSHIP_PRORATED"
        when Sponsors::Pricing::PaymentOption::Delayed
          "PAY_SPONSORSHIP_DELAYED"
        when Sponsors::Pricing::PaymentOption::Default
          nil
        else
          T.absurd(option)
        end

        return {} unless button_name

        hydro_click_tracking_attributes(
          "sponsors.button_click",
          button: button_name,
          sponsored_developer_login: @sponsorable&.display_login,
        )
      end

      sig { returns T::Boolean }
      memoize def recurring_bulk_sponsorship?
        return false unless bulk_sponsorship?

        # we currently enforce that bulk sponsorships can only be made with one frequency
        bulk_sponsorship_row = T.must(@sponsorship_rows.first)
        bulk_sponsorship_row.recurring?
      end
    end
  end
end
