# typed: true
# frozen_string_literal: true

# Public: A representation of all sponsorship payments an invoiced sponsor has made as an Invoiced Sponsors Customer
#
# Prior to March 2022, payments made by invoiced sponsors customers to maintainers were tracked through
# the InvoicedSponsorshipTransfer model. The InvoicedSponsorshipTransfer model is no longer being used for new
# payments, but still holds historical data for invoiced sponsors customers that participated in our beta.
#
# This class provides a way of querying all of a sponsor's payments without context of the legacy model.
module Sponsors
  class InvoicedSponsorshipLineItem
    # Public: all payments that an invoiced sponsors organization has made in a given time period.
    #
    # org        - an Organization that pays for sponsorships via invoice
    # time_range - an optional Range of Time objects to bound the query
    # sponsorable_ids - optional Array of Integer User and Organization IDs for filtering; if any are given, only
    #                   payments made to these maintainers will be included
    #
    # Returns an Array of Sponsors::InvoicedSponsorshipLineItems.
    def self.for_org(org, time_range: nil, sponsorable_ids: [])
      from_billing_line_items(org, time_range: time_range, sponsorable_ids: sponsorable_ids) +
        from_invoiced_sponsorship_transfers(org, time_range: time_range, sponsorable_ids: sponsorable_ids)
    end

    # Public: the first payment that an invoiced sponsors organization made
    #
    # org - an Organization that pays for sponsorships via invoice
    #
    # Returns a Sponsors::InvoicedSponsorshipLineItem or Nil
    def self.first_for_org(org)
      billable = first_invoiced_sponsorship_transfer_for(org) || first_billing_line_item_for(org)

      new(billable: billable) if billable.present?
    end

    # Private: all payments that an invoiced sponsors organization made in a given time period that are stored as
    # Billing::BillingTransaction::LineItems.
    #
    # Maps the result of the query to an array of Sponsors::InvoicedSponsorshipLineItems.
    #
    # Returns an Array of Sponsors::InvoicedSponsorshipLineItems.
    def self.from_billing_line_items(org, time_range: nil, sponsorable_ids: [])
      billing_line_items_for(org, time_range: time_range, sponsorable_ids: sponsorable_ids).map do |line_item|
        new(billable: line_item)
      end
    end

    # Private: all of the BillingTransaction::LineItems that represent payments that an
    # invoiced sponsors organization has made for sponsorships in a given time period.
    #
    # Because Billing::BillingTransaction::LineItems can have a non-sponsors purpose, and can
    # represent refunds, we scope down to only LineItems that were paid to a sponsorable.
    #
    # Returns an ActiveRecord::Collection of Billing::BillingTransaction::LineItems.
    def self.billing_line_items_for(org, time_range: nil, sponsorable_ids: [])
      plan_sub_id = org.sponsors_plan_subscription_id
      return Billing::BillingTransaction::LineItem.none unless plan_sub_id
      line_items = Billing::BillingTransaction::LineItem
        .sponsorships
        .for_sponsors_plan_subscription(plan_sub_id)
        .paid
      line_items = line_items.created_between(time_range.begin, time_range.end) if time_range
      line_items = line_items.paying_sponsorable(sponsorable_ids) if sponsorable_ids.present?
      line_items.includes(:subscribable)
    end

    # Private: all of the InvoicedSponsorshipTransfers that represent payments that an invoiced sponsors
    # organization made in a given time period.
    #
    # Returns an ActiveRecord::Collection of InvoicedSponsorshipTransfers.
    def self.invoiced_sponsorship_transfers_for(org, time_range: nil, sponsorable_ids: [])
      transfers = InvoicedSponsorshipTransfer.for_sponsor(org)
      transfers = transfers.created_between(time_range.begin, time_range.end) if time_range
      transfers = transfers.for_sponsorable(sponsorable_ids) if sponsorable_ids.present?
      transfers
    end

    # Private: Add one month onto each end of the time range for InvoicedSponsorshipTransfers
    #
    # Because InvoicedSponsorshipTransfers can only be marked as recurring based on comparing them to
    # other InvoicedSponsorshipTransfers, this method widens the time range of the query to ensure we don't miss
    # InvoicedSponsorshipTransfers that have similar payments slightly outside the time range queried.
    #
    # Returns Range of Dates or Nil.
    def self.extended_time_range(range = nil)
      return unless range
      first_month = range.begin ? range.begin - 1.month : nil
      last_month = range.end ? range.end + 1.month : nil
      Range.new(first_month&.beginning_of_month, last_month&.end_of_month)
    end

    # Private: all payments that an invoiced sponsors organization made in a given time period that are stored
    # as InvoicedSponsorshipTransfers.
    #
    # This method queries for InvoicedSponsorshipTransfers that were created within one month of the specified start
    # and end dates for comparison purposes, but only includes InvoicedSponsorshipTransfers that match the original
    # date parameters in the result.
    #
    # Maps the result of the query to an arry of Sponsors::InvoicedSponsorshipLineItems.
    def self.from_invoiced_sponsorship_transfers(org, time_range: nil, sponsorable_ids: [])
      transfers = invoiced_sponsorship_transfers_for(org, time_range: extended_time_range(time_range),
        sponsorable_ids: sponsorable_ids)

      filtered_transfers = if time_range.present?
        transfers.select { |transfer| time_range.cover?(transfer.created_at) }
      else
        transfers
      end

      filtered_transfers.map { |transfer| new(billable: transfer, transfers: transfers) }
    end

    # Private: The first InvoicedSponsorshipTransfer an organization paid
    #
    # org - An Organization that pays for sponsorships via invoice
    #
    # Returns an InvoicedSponsorshipTransfer or Nil
    def self.first_invoiced_sponsorship_transfer_for(org)
      InvoicedSponsorshipTransfer
        .for_sponsor(org)
        .order(created_at: :asc)
        .first
    end

    # Private: the first Billing::Billingtransaction::LineItem an organization paid
    #
    # org - an Organization that pays for sponsorships via invoice
    #
    # Returns a Billing::BillingTransaction::LineItem or Nil
    def self.first_billing_line_item_for(org)
      plan_sub_id = org.sponsors_plan_subscription_id
      return unless plan_sub_id
      Billing::BillingTransaction::LineItem
        .sponsorships
        .for_sponsors_plan_subscription(plan_sub_id)
        .paid
        .order(created_at: :asc)
        .first
    end

    private_class_method :from_billing_line_items, :billing_line_items_for, :from_invoiced_sponsorship_transfers,
      :invoiced_sponsorship_transfers_for, :extended_time_range, :first_invoiced_sponsorship_transfer_for,
      :first_billing_line_item_for

    # billable  - a Billing::BillingTransaction::LineItem or InvoicedsponsorshipTransfer
    # transfers - a collection of InvoicedSponsorshipTransfers for the organization.
    #             Only used to compare an InvoicedSponsorshipTransfer to other InvoicedSponsorshipTransfers
    #             in order to determine if the billable is recurring.
    def initialize(billable:, transfers: [])
      @billable = billable
      @transfers = transfers
    end

    attr_reader :billable
    delegate :created_at, :amount_in_cents, to: :billable

    # Private: Was this payment part of a set of recurring payments from this sponsor to this sponsorable?
    #
    # For Billing::BillingTransaction::LineItems, recurring is True if the associated SponsorsTier is recurring.
    # Since InvoicedSponsorshipLineItems are a series of manual one-time payments, we infer whether the payment was
    # recurring based on if the sponsor made repeated similar payments to the sponsorable.
    #
    # Returns Boolean.
    def recurring?
      return billable.recurring? if billable.respond_to?(:recurring?)
      similar_transfers_for(billable).present?
    end

    def one_time?
      !recurring?
    end

    private

    # Private: Find InvoicedSponsorshipTransfer that are similar to a given InvoicedSponsorshipTransfer, but are not
    # the same instance.
    #
    # Useful for determining whether a sponsor has made recurring payments to a sponsorable.
    #
    # Returns Array of InvoicedSponsorshipTransfers.
    def similar_transfers_for(transfer)
      @transfers.select { |t| t.id != transfer.id }
                .detect { |t| similar_to(t, transfer) }
    end

    # Private: Are two InvoicedSponsorshipTransfers similar enough that they should be considered recurring?
    #
    # True if the transfer:
    # - Is from the same sponsor
    # - Is to the same sponsorable
    # - Is for the same amount of money
    # - Has occurred in two consecutive months
    #
    # Returns Boolean.
    def similar_to(transfer1, transfer2)
      same_sponsor?(transfer1, transfer2) &&
        same_sponsorable?(transfer1, transfer2) &&
        paying_same_amount?(transfer1, transfer1) &&
        on_monthly_cadence?(transfer1, transfer2)
    end

    # Private: Were each of these payments made by the same sponsor?
    #
    # Returns Boolean.
    def same_sponsor?(transfer1, transfer2)
      transfer1.sponsor_id == transfer2.sponsor_id
    end

    # Private: Were each of these payments made to the same sponsorable?
    #
    # Returns Boolean.
    def same_sponsorable?(transfer1, transfer2)
      transfer1.sponsors_listing_id == transfer2.sponsors_listing_id
    end

    # Private: Were both of these payments made for the same amount of money?
    #
    # Returns Boolean.
    def paying_same_amount?(transfer1, transfer2)
      transfer1.amount_in_cents == transfer2.amount_in_cents
    end

    # Private: Were both of these payments made within a month of each other?
    #
    # Returns Boolean.
    def on_monthly_cadence?(transfer1, transfer2)
      one_month_before = transfer1.created_at - 1.month
      one_month_after = transfer1.created_at + 1.month
      transfer2.created_at.between?(one_month_before.beginning_of_month, one_month_after.end_of_month)
    end
  end
end
