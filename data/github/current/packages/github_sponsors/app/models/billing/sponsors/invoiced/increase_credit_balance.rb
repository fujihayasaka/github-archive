# typed: true
# frozen_string_literal: true

module Billing
  module Sponsors
    module Invoiced
      # Increases the credit balance for a Sponsors-specific Zuora account by applying an external payment
      # to the credit balance.
      class IncreaseCreditBalance
        extend T::Sig

        include ActiveModel::Validations

        validates :actor, presence: true, unless: -> (icb) { icb.via_automation? }
        validates :sponsor, presence: true
        validates :amount, presence: true, numericality: { greater_than: 0 }
        validates :comment, presence: true
        validates :reference_id, presence: true
        validate :actor_can_admin_invoiced_sponsors, unless: -> (icb) { icb.via_automation? }
        validate :sponsor_is_invoiced_sponsor

        # Public: Increases the credit balance for a Sponsors-specific Zuora account
        #
        # Returns GitHub::Billing::Result
        sig do
          params(
            actor: T.nilable(T.any(User, Organization)),
            sponsor: T.nilable(Organization),
            amount: T.nilable(Billing::Money),
            comment: T.nilable(String),
            reference_id: T.nilable(String),
            via_automation: T::Boolean,
          ).returns(GitHub::Billing::Result)
        end
        def self.perform(actor:, sponsor:, amount:, comment:, reference_id:, via_automation: false)
          new(
            actor: actor,
            sponsor: sponsor,
            amount: amount,
            comment: comment,
            reference_id: reference_id,
            via_automation: via_automation
           ).perform
        end

        ## Initialize a new IncreaseCreditBalance
        #
        # actor - the staff User increasing the credit balance
        # sponsor - the Org whose Sponsors-specific credit balance is being increased
        # amount - the Billing::Money amount to apply to the credit balance
        # comment - a String comment that we make up, to include as metadata on the Zuora payment
        # reference_id - a String reference ID that we make up, to include as metadata on the Zuora payment
        # via_automation - a Boolean that indicates whether the balance increase happened automatically
        sig do
          params(
            actor: T.nilable(T.any(User, Organization)),
            sponsor: T.nilable(Organization),
            amount: T.nilable(Billing::Money),
            comment: T.nilable(String),
            reference_id: T.nilable(String),
            via_automation: T::Boolean,
          ).void
        end
        def initialize(actor:, sponsor:, amount:, comment:, reference_id:, via_automation: false)
          @actor = actor
          @sponsor = sponsor
          @amount = amount
          @comment = comment
          @reference_id = reference_id
          @via_automation = via_automation
        end

        # Public: Increases the credit balance for a Sponsors-specific Zuora account
        sig { returns GitHub::Billing::Result }
        def perform
          if valid?
            increase_credit_balance
          else
            error_sentence = errors.full_messages.to_sentence
            GitHub::Billing::Result.failure(error_sentence)
          end
        end

        sig { returns T::Boolean }
        def via_automation?
          @via_automation
        end

        private

        attr_reader :actor, :sponsor, :amount, :comment, :reference_id

        sig { returns GitHub::Billing::Result }
        def increase_credit_balance
          result = create_zuora_payment

          sponsor.instrument_sponsors_credit_balance_increase(
            actor: actor,
            result: result,
            amount_in_cents: amount.cents,
            comment: comment,
            reference_id: reference_id,
            payment_id: result.zuora_result["Id"]
          )

          result
        end

        sig { returns GitHub::Billing::Result }
        def create_zuora_payment
          zuora_result = begin
            GitHub.zuorest_client.create_payment(
              {
                "AccountId" => account_id,
                "Amount" => amount.dollars,
                "AppliedCreditBalanceAmount" => amount.dollars,
                "Type" => "External",
                "Comment" => comment,
                "ReferenceId" => reference_id,
                "Status" => "Processed",
                "EffectiveDate" => GitHub::Billing.today.strftime("%F"),
                "PaymentMethodId" => GitHub.zuora_other_payment_method_id
              }
            )
          rescue Zuorest::HttpError => e
            Failbot.report!(e, app: "github-zuora")
            e.data
          end
          GitHub::Billing::Result.from_zuora(zuora_result)
        end

        def account_id
          sponsor.invoiced_sponsor_zuora_account_id
        end

        def actor_can_admin_invoiced_sponsors
          unless actor&.can_admin_sponsors_listings?
            errors.add(:actor, "does not have permission to admin invoiced sponsors")
          end
        end

        def sponsor_is_invoiced_sponsor
          unless sponsor&.sponsors_invoiced?
            errors.add(:sponsor, "is not an invoiced sponsor")
          end
        end
      end
    end
  end
end
