# typed: strict
# frozen_string_literal: true

module Billing
  module Stripe
    class Transfer
      extend T::Sig
      include GitHub::Memoizer

      class NotEnoughMatchError < StandardError; end

      sig { returns T.nilable(String) }
      attr_reader :transfer_id

      alias_method :id, :transfer_id

      sig { returns T.nilable(String) }
      attr_reader :transfer_group

      sig { returns T.nilable(String) }
      attr_reader :platform_url

      sig { returns Billing::Money }
      memoize def match_amount
        Billing::Money.new(@metadata[:match_amount].to_i, @currency)
      end

      sig { returns Billing::Money }
      memoize def match_amount_reversed
        Billing::Money.new(reversals.sum { |reversal| reversal.metadata[:match_amount_reversed].to_i }, @currency)
      end

      sig { returns Billing::Money }
      memoize def amount
        @amount || Billing::Money.zero
      end

      sig { returns Billing::Money }
      memoize def amount_reversed
        payment_amount_reversed + match_amount_reversed
      end

      sig { returns T.nilable(String) }
      attr_reader :destination

      sig { returns T.nilable(String) }
      attr_reader :destination_currency

      sig { returns T.nilable(Billing::Money) }
      attr_reader :destination_amount

      sig { returns T.nilable(DateTime) }
      attr_reader :transferred_at

      sig { returns T.any(::Stripe::StripeObject, T::Hash[T.any(String, Symbol), T.untyped]) }
      attr_reader :metadata

      sig { returns(T::Array[::Stripe::Reversal]) }
      def reversals
        @reversals.is_a?(::Stripe::ListObject) ? @reversals.data : @reversals
      end

      sig { returns T.nilable(Integer) }
      attr_reader :sponsors_listing_id

      sig { returns T::Array[Billing::BillingTransaction::LineItem] }
      attr_reader :sponsorship_line_items

      sig { returns T.nilable(String) }
      attr_reader :original_transaction_id

      sig { returns T.nilable(T.any(GitHubSponsors::Types::Sponsor, Billing::DeadUser)) }
      attr_reader :sponsor

      LIMIT = 100

      # Public: Retrieve transfers from stripe and modify for our use
      #
      # destination - optional Stripe Connect account id
      # destination_currency - The default currency of the destination account, if known
      # starting_after - transfer id, used for pagination.
      # ending_before - transfer id, used for pagination.
      # transfer_group - initial platform_transaction_id from the transaction that triggered the transfer
      # sponsor - optional string to filter transfers by sponsor
      sig do
        params(
          destination: T.nilable(String),
          destination_currency: T.nilable(String),
          limit: T.nilable(Integer),
          starting_after: T.nilable(String),
          transfer_group: T.nilable(String),
          ending_before: T.nilable(String),
          sponsor: T.nilable(String)
        ).returns(T::Array[Transfer])
      end
      def self.list(destination: nil, destination_currency: nil, limit: LIMIT, starting_after: nil, transfer_group: nil, ending_before: nil, sponsor: nil)
        return [] if ending_before && starting_after

        param_list = {
          limit: limit,
          destination: destination,
          starting_after: starting_after,
          transfer_group: transfer_group,
          ending_before: ending_before,
        }

        stripe_transfers     = ::Stripe::Transfer.list(param_list)
        billing_transactions = Billing::BillingTransaction
          .for_zuora_transaction_id(stripe_transfers.data.map(&:transfer_group))
          .includes(:live_user)
          .to_a

        invoiced_transfers = InvoicedSponsorshipTransfer
          .where(stripe_transfer_id: stripe_transfers.data.map(&:id))
          .includes(:sponsor)
          .to_a

        sponsors = (billing_transactions.map(&:live_user) + invoiced_transfers.map(&:sponsor)).compact.uniq
        GitHub::PrefillAssociations.prefill_associations(sponsors, :profile)

        from_transfers(stripe_transfers, billing_transactions, invoiced_transfers, destination_currency, sponsor)
      end

      # Public: Hydrate a Billing::Stripe::Transfer with data from Stripe.
      #
      # transfer - a transfer object from the Stripe API
      # billing_transaction - optional Billing::BillingTransaction if known
      # destination_currency - optional currency of the destination account if known;
      #                        will grab the destination currency from the Stripe data
      #                        otherwise
      # sponsor - the sponsor responsible for this transfer occurring, if known
      sig do
        params(
          transfer: ::Stripe::Transfer,
          billing_transaction: T.nilable(Billing::BillingTransaction),
          destination_currency: T.nilable(String),
          sponsor: T.nilable(T.any(GitHubSponsors::Types::Sponsor, Billing::DeadUser))
        ).returns(Transfer)
      end
      def self.from_transfer(transfer, billing_transaction: nil, destination_currency: nil, sponsor: nil)
        destination_currency ||= transfer.try(:destination_currency)
        destination_amount = if destination_currency && transfer.try(:destination_amount)
          Billing::Money.new(transfer.destination_amount, destination_currency)
        end

        sponsorship_line_items = if billing_transaction
          billing_transaction.line_items.sponsorships.includes(:subscribable).to_a
        end

        transfer_sponsor = if sponsor && !sponsor.is_a?(Billing::DeadUser)
          sponsor
        else
          line_item = sponsorship_line_items&.first
          line_item ? line_item.sponsor : nil
        end

        new(
          transfer_id: transfer.id,
          transfer_group: transfer.transfer_group,
          platform_url: billing_transaction&.platform_url,
          currency: transfer.currency,
          amount: Billing::Money.new(transfer.amount, transfer.currency),
          sponsor: transfer_sponsor,
          destination: transfer.destination,
          destination_currency: destination_currency,
          destination_amount: destination_amount,
          transferred_at: Time.at(transfer.created).utc.to_datetime,
          metadata: transfer.metadata,
          reversals: transfer.reversals,
          fully_reversed: transfer.reversed,
          sponsors_listing_id: transfer.metadata[:sponsors_listing_id],
          sponsorship_line_items: sponsorship_line_items,
          charged_back: billing_transaction&.charged_back?,
          original_transaction_id: billing_transaction&.transaction_id,
        )
      end

      # Internal: Takes an array of transfers from Stripe and formats them for our usage
      # Pulls in user_login from billing_transactions, based on the transfer_group
      # information found in the Stripe transfer object.
      sig do
        params(
          transfers: ::Stripe::ListObject,
          billing_transactions: T::Array[Billing::BillingTransaction],
          invoiced_transfers: T::Array[InvoicedSponsorshipTransfer],
          destination_currency: T.nilable(String),
          sponsor_filter: T.nilable(String)
        ).returns(T::Array[Transfer])
      end
      def self.from_transfers(transfers, billing_transactions, invoiced_transfers, destination_currency, sponsor_filter = nil)
        return [] unless transfers.present?

        internal_transfers = transfers.data.map do |transfer|
          billing_transaction = billing_transactions.detect do |bt|
            bt.platform_transaction_id == transfer.transfer_group
          end

          invoiced_transfer = invoiced_transfers.detect do |it|
            it.stripe_transfer_id == transfer.id
          end

          sponsor = if billing_transaction
            # Should already be preloaded by #list:
            billing_transaction.user
          elsif invoiced_transfer
            # Should already be preloaded by #list:
            invoiced_transfer.sponsor
          end

          next if sponsor_filter.present? && (sponsor.nil? || sponsor.login.exclude?(sponsor_filter))

          from_transfer(transfer, billing_transaction: billing_transaction,
            destination_currency: destination_currency, sponsor: sponsor)
        end

        internal_transfers.compact
      end
      private_class_method :from_transfers

      sig do
        params(
          transfer_id: T.nilable(String),
          transfer_group: T.nilable(String),
          platform_url: T.nilable(String),
          amount: T.nilable(Billing::Money),
          currency: T.nilable(String),
          sponsor: T.nilable(T.any(GitHubSponsors::Types::Sponsor, Billing::DeadUser)),
          destination: T.nilable(String),
          destination_currency: T.nilable(String),
          destination_amount: T.nilable(Billing::Money),
          transferred_at: T.nilable(DateTime),
          metadata: T.nilable(T.any(::Stripe::StripeObject, T::Hash[T.any(String, Symbol), T.untyped])),
          reversals: T.nilable(T.any(::Stripe::ListObject, T::Array[::Stripe::Reversal])),
          fully_reversed: T.nilable(T::Boolean),
          sponsors_listing_id: T.nilable(T.any(String, Integer)),
          sponsorship_line_items: T.nilable(T::Array[Billing::BillingTransaction::LineItem]),
          charged_back: T.nilable(T::Boolean),
          original_transaction_id: T.nilable(String)
        ).void
      end
      def initialize(
        transfer_id: nil,
        transfer_group: nil,
        platform_url: nil,
        amount: nil,
        currency: nil,
        sponsor: nil,
        destination: nil,
        destination_currency: nil,
        destination_amount: nil,
        transferred_at: nil,
        metadata: {},
        reversals: nil,
        fully_reversed: nil,
        sponsors_listing_id: nil,
        sponsorship_line_items: [],
        charged_back: nil,
        original_transaction_id: nil
      )
        @transfer_id            = transfer_id
        @transfer_group         = transfer_group
        @platform_url           = platform_url
        @amount                 = amount
        @currency               = currency
        @sponsor                = sponsor
        @destination            = destination
        @destination_currency   = destination_currency
        @destination_amount     = destination_amount
        @transferred_at         = transferred_at
        @metadata               = T.let(metadata || {},
          T.any(::Stripe::StripeObject, T::Hash[T.any(String, Symbol), T.untyped]))
        @reversals              = T.let(reversals || [], T.any(::Stripe::ListObject, T::Array[::Stripe::Reversal]))
        @fully_reversed         = fully_reversed
        @sponsors_listing_id    = T.let(sponsors_listing_id ? sponsors_listing_id.to_i : nil, T.nilable(Integer))
        @sponsorship_line_items = T.let(sponsorship_line_items || [], T::Array[Billing::BillingTransaction::LineItem])
        @charged_back           = charged_back
        @original_transaction_id = original_transaction_id
      end

      sig { returns(Billing::Money) }
      memoize def payment_amount_reversed
        Billing::Money.new(reversals.sum { |reversal| reversal.metadata[:payment_amount_reversed].to_i }, @currency)
      end

      sig { returns(Billing::Money) }
      memoize def payment_amount
        Billing::Money.new(@metadata[:payment_amount].to_i, @currency)
      end

      # Public: Have both the payment and any GitHub match been reversed entirely?
      sig { returns T::Boolean }
      memoize def fully_reversed?
        if @fully_reversed.nil?
          amount == amount_reversed
        else
          @fully_reversed
        end
      end

      # Public: Has some part of the payment or GitHub match been reversed, but not the entire amount?
      sig { returns T::Boolean }
      memoize def partially_reversed?
        amount_reversed > 0 && !fully_reversed?
      end

      # Public: Have we fully reversed all of GitHub's match on this transfer?
      sig { returns T::Boolean }
      def match_fully_reversed?
        match_amount == match_amount_reversed
      end

      # Public: Have we reached the max default return of reversals?
      # Retrieving transfer records returns a default of 10 reversals. If we
      # have done 10 or more reversals for a given transfer we are at risk
      # of the match_amount_reversed being incorrect. Used to display a warning
      # in the UI.
      sig { returns T::Boolean }
      def possibility_of_reversal_mismatch?
        number_of_reversals >= 10
      end

      # Public: The billing_transaction has been charged back?
      sig { returns T::Boolean }
      def charged_back?
        @charged_back || false
      end

      # Public: Build the url to view this transfer in Stripe
      sig { returns String }
      def transfer_url
        "#{GitHub.stripe_connect_dashboard_base_url}/transfers/#{transfer_id}"
      end

      sig { returns T::Boolean }
      def user_sponsor?
        return false unless sponsor
        T.must(sponsor).user?
      end

      sig { returns T.nilable(String) }
      memoize def sponsor_time_zone_name
        return unless live_sponsor?
        T.must(sponsor).time_zone_name
      end

      sig { returns String }
      memoize def sponsor_ip_address_country_name
        ip_address_location = sponsor_ip_address_location
        if ip_address_location
          ip_address_location[:country_name].presence || "none"
        else
          "none"
        end
      end

      sig { returns T::Boolean }
      def sponsor_has_time_zone_matching_ip_address?
        ip_address_location = sponsor_ip_address_location
        if ip_address_location.present?
          return false if sponsor_time_zone_name.blank?

          country_code = ip_address_location[:country_code]
          return false if country_code.blank?

          ::Sponsors::TimeZone.new(sponsor_time_zone_name).matches_country_code?(country_code)
        else
          sponsor_time_zone_name.blank?
        end
      end

      sig { returns T::Boolean }
      def sponsor_has_young_github_account?
        return false unless live_sponsor?
        created_at = T.must(sponsor).created_at
        return false unless created_at
        created_at >= 60.days.ago
      end

      sig { returns T::Boolean }
      def sponsor_has_customized_user_profile?
        profile = sponsor.try(:profile)
        return false unless profile.present?
        # Profile relation preloaded in #list:
        profile_fields = [profile.name, profile.bio, profile.twitter_username, profile.blog, profile.company]
        profile_fields.any?(&:present?)
      end

      sig { returns T.nilable(String) }
      memoize def sponsor_login
        sponsor&.login
      end

      sig { returns T.nilable(Integer) }
      def sponsor_id
        sponsor&.id
      end

      # Public: If this transfer has *likely* been paid out
      # We check if the latest payout happened after this transaction
      # There is a chance that the payout does not include this transaction
      # And therefore has *NOT* already been paid out.
      sig do
        params(
          stripe_account: Billing::StripeConnect::Account,
          latest_payout: T.nilable(Stripe::Payout)
        ).returns(T::Boolean)
      end
      def has_been_paid_out?(stripe_account, latest_payout)
        return false if stripe_account.nil?
        return false if latest_payout.nil?
        payout_created = Time.at(latest_payout.created).utc.to_datetime
        return false unless transferred_at
        T.must(transferred_at) <= payout_created
      end

      sig { returns T::Boolean }
      memoize def dead_sponsor?
        sponsor.is_a?(Billing::DeadUser)
      end

      private

      sig { returns Integer }
      def number_of_reversals
        reversals.count { |data| data.metadata[:match_amount_reversed] }
      end

      sig { returns T.nilable(T::Hash[Symbol, T.untyped]) }
      memoize def sponsor_ip_address_location
        if sponsor
          ip_address = T.must(sponsor).last_ip
          GitHub::Location.look_up(ip_address) if ip_address.present?
        end
      end

      sig { returns T::Boolean }
      memoize def live_sponsor?
        !!(sponsor && !dead_sponsor?)
      end
    end
  end
end
