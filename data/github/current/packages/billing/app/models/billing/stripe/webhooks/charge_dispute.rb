# typed: strict
# frozen_string_literal: true

class Billing::Stripe::Webhooks::ChargeDispute
  sig { returns(T.nilable(::Billing::Dispute)) }
  attr_reader :dispute

  sig { returns(::Stripe::Event) }
  attr_reader :event

  sig { returns(::Billing::StripeWebhook) }
  attr_reader :webhook

  sig { returns(::Stripe::Dispute) }
  attr_reader :stripe_dispute

  # Public: Handle the charge dispute webhook payload
  sig { params(webhook: Billing::StripeWebhook).void }
  def self.perform(webhook)
    new(webhook).perform
  end

  # Public: Initializes a new ChargeDispute webhook handler
  sig { params(webhook: ::Billing::StripeWebhook).void }
  def initialize(webhook)
    @webhook = webhook
    @event = T.let(webhook.stripe_event, Stripe::Event)
    @stripe_dispute = T.let(T.cast(event.data.object, Stripe::Dispute), ::Stripe::Dispute)
  end

  # Public: Handle the charge dispute webhook payload
  sig { void }
  def perform
    Billing::BillingTransaction.retry_on_find_or_create_error do
      @dispute = T.let(disputed_transaction.disputes.find_or_initialize_by(
        platform: :stripe,
        platform_dispute_id: stripe_dispute.id,
      ), T.nilable(Billing::Dispute))

      dispute = T.must(self.dispute)

      return if webhook_older_than_latest_update?

      if dispute.new_record?
        dispute.created_at = Time.at(stripe_dispute.created)

        create_zendesk_chargeback_ticket
      end

      dispute.update!(
        amount_in_subunits: stripe_dispute.amount,
        currency_code: stripe_dispute.currency.upcase,
        reason: stripe_dispute.reason,
        status: stripe_dispute.status,
        refundable: stripe_dispute.is_charge_refundable,
        response_due_by: Time.at(stripe_dispute.evidence_details.due_by),
        user_id: disputed_transaction.user_id,
        updated_at: Time.at(event.created),
      )
    end
  end

  private

  sig { void }
  def create_zendesk_chargeback_ticket
    dispute = T.must(self.dispute)
    body = <<~BODY
      This ticket represents a single fraud case:

      #{dispute.url}

      In an effort to more accurately forecast our future hiring needs, this ticket is being sent as a record of a single chargeback case or fraudulent transaction.
    BODY
    tags = %w[chargeback squad_billing]

    custom_fields = {
      GitHub.zendesk_fields[:level] => "level_2",
      GitHub.zendesk_fields[:category] => "cat_chargebacks"
    }
    zendesk_form_id = 360000294291 # Account Support Form ID
    zendesk_group_id = 360003703071 # Accounts Support group ID

    CreateZendeskTicket.perform_later(
      "Chargebacks",
      "chargebacks@noreply.github.com",
      "Chargeback record",
      body,
      group_id: zendesk_group_id,
      ticket_form_id: zendesk_form_id,
      brand_id: GitHub.zendesk_brand_id,
      tags: tags,
      custom_fields: custom_fields,
    )
  end

  # Returns Billing::BillingTransaction
  # Raises ActiveRecord::RecordNotFound
  sig { returns(Billing::BillingTransaction) }
  def disputed_transaction
    @disputed_transaction ||= T.let(Billing::BillingTransaction.find_by!(
      transaction_id: stripe_dispute.charge,
    ), T.nilable(Billing::BillingTransaction))
  end

  # Checks if the webhook event is older than the most recent update in order
  # to prevent saving outdated information if webhooks are processed out of
  # order. Each webhook will have the most recent version of the Stripe Dispute
  # object serialized, so we don't want to update our copy with data that is
  # out-of-data.
  sig { returns(T::Boolean) }
  def webhook_older_than_latest_update?
    dispute = T.must(self.dispute)
    return false if dispute.new_record?

    Time.at(event.created) < dispute.updated_at
  end
end
