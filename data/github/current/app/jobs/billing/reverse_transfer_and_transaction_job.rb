# typed: strict
# frozen_string_literal: true

module Billing
  class ReverseTransferAndTransactionJob < BillingJob
    extend T::Sig
    include GitHub::Memoizer

    queue_as :billing

    retry_on_dirty_exit

    sig do
      params(
        stripe_transfer_id: String,
        transaction_id: String,
        stripe_account_id: T.any(Integer, String),
        sponsor_id: T.any(Integer, String),
        sponsorable: GitHubSponsors::Types::Sponsorable,
        notify_sponsorable: T::Boolean,
      ).void
    end
    def perform(stripe_transfer_id:, transaction_id:, stripe_account_id:, sponsor_id:, sponsorable:, notify_sponsorable:)
      @stripe_transfer_id = T.let(stripe_transfer_id, T.nilable(String))
      @transaction_id = T.let(transaction_id, T.nilable(String))
      @stripe_account_id = T.let(stripe_account_id, T.nilable(T.any(Integer, String)))
      @sponsor_id = T.let(sponsor_id, T.nilable(T.any(Integer, String)))
      @sponsorable = T.let(sponsorable, T.nilable(User))
      @notify_sponsorable = T.let(notify_sponsorable, T.nilable(T::Boolean))

      result = Billing::Stripe::TransferReversal.perform(stripe_transfer_id: transfer.id)

      if result.success?
        billing_transaction = ::Billing::BillingTransaction.find_by(transaction_id: transaction_id)
        transfer_payment_amount = transfer.metadata[:payment_amount].to_i

        with_write { T.must(billing_transaction).refund!(transfer_payment_amount) }
        send_transaction_reversal_notification if notify_sponsorable?(result)
      end
    end

    sig { returns(T.nilable(T.any(Integer, String))) }
    attr_reader :stripe_account_id, :sponsor_id

    sig { returns(T.nilable(GitHubSponsors::Types::Sponsorable)) }
    attr_reader :sponsorable

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :notify_sponsorable

    sig { returns(String) }
    def stripe_transfer_id
      T.must_because(@stripe_transfer_id) { "called after #perform which ensures non-nil" }
    end

    sig { returns(::Stripe::Transfer) }
    memoize def transfer
      ::Stripe::Transfer.retrieve(stripe_transfer_id)
    end

    sig { params(result: Billing::Stripe::TransferReversal::Result).returns(T::Boolean) }
    def notify_sponsorable?(result)
      return false unless notify_sponsorable
      return false unless sponsor && sponsorable && stripe_account
      return false unless result.message

      T.must(result.message).include?("reversed for Stripe transfer #{stripe_transfer_id}")
    end

    sig { void }
    def send_transaction_reversal_notification
      SponsorsPrimerMailer.transaction_reversal(
        sponsor: T.must_because(sponsor) { "non-nil sponsor expected in #perform" },
        sponsorable: T.must_because(sponsorable) { "non-nil sponsorable expected in #perform" },
        stripe_account: T.must_because(stripe_account) { "non-nil stripe_account expected in #perform" }
      ).deliver_later
    end

    sig { returns(T.nilable(GitHubSponsors::Types::Sponsor)) }
    memoize def sponsor
      User.find(T.must(sponsor_id)) if transfer
    end

    sig { returns(T.nilable(StripeConnect::Account)) }
    memoize def stripe_account
      StripeConnect::Account.find(T.must(stripe_account_id))
    end
  end
end
