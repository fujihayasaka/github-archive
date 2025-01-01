# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::Webhooks::ChargeDisputeTest < GitHub::BillingTestCase
  fixtures do
    @account = create(:user)
    @billing_transaction = create(:billing_transaction, user: @account)
  end

  test "creates a zendesk ticket for new disputes with the dispute URL" do
    webhook = create(
      :stripe_webhook,
      :charge_dispute_created,
      object: {
        id: "dp_1",
        charge: @billing_transaction.transaction_id,
        amount: -7_00,
        currency: "usd",
        reason: "fraudulent",
        status: "needs_response",
        evidence_details: { due_by: Time.new(2019, 9, 1).to_i },
        is_charge_refundable: false,
        created: Time.new(2019, 9, 1, 12, 0, 0).to_i,
      },
      created: Time.new(2019, 9, 1, 12, 0, 0).to_i,
    )

    CreateZendeskTicket.expects(:perform_later).with(
      "Chargebacks",
      "chargebacks@noreply.github.com",
      "Chargeback record",
      regexp_matches(/#{@billing_transaction.transaction_id}/),
      group_id: 360003703071,
      ticket_form_id: 360000294291,
      brand_id: "400594",
      tags: %w[chargeback squad_billing],
      custom_fields: {
        GitHub.zendesk_fields[:level] => "level_2",
        GitHub.zendesk_fields[:category] => "cat_chargebacks"
      }
    )

    Billing::Stripe::Webhooks::ChargeDispute.perform(webhook)
  end

  test "creates a Billing::Dispute when receiving a charge.dispute.created webhook" do
    webhook = create(
      :stripe_webhook,
      :charge_dispute_created,
      object: {
        id: "dp_1",
        charge: @billing_transaction.transaction_id,
        amount: -7_00,
        currency: "usd",
        reason: "fraudulent",
        status: "needs_response",
        evidence_details: { due_by: Time.new(2019, 9, 1).to_i },
        is_charge_refundable: false,
        created: Time.new(2019, 9, 1, 12, 0, 0).to_i,
      },
      created: Time.new(2019, 9, 1, 12, 0, 0).to_i,
    )

    assert_difference(-> { @billing_transaction.disputes.count }, 1) do
      Billing::Stripe::Webhooks::ChargeDispute.perform(webhook)
    end

    dispute = @billing_transaction.disputes.last
    assert_equal "stripe", dispute.platform
    assert_equal "dp_1", dispute.platform_dispute_id
    assert_equal(-7_00, dispute.amount_in_subunits)
    assert_equal "USD", dispute.currency_code
    assert_equal "fraudulent", dispute.reason
    assert_equal "needs_response", dispute.status
    refute_predicate dispute, :refundable?
    assert_equal Time.new(2019, 9, 1), dispute.response_due_by
    assert_equal @account.id, dispute.user_id
    assert_equal Time.new(2019, 9, 1, 12, 0, 0), dispute.created_at
    assert_equal Time.new(2019, 9, 1, 12, 0, 0), dispute.updated_at
  end

  test "creates a Billing::Dispute if one doesn't exist when receiving a charge.dispute.updated webhook" do
    webhook = create(
      :stripe_webhook,
      :charge_dispute_updated,
      object: {
        id: "dp_1",
        charge: @billing_transaction.transaction_id,
        amount: -7_00,
        currency: "usd",
        reason: "fraudulent",
        status: "under_review",
        evidence_details: { due_by: Time.new(2019, 9, 1).to_i },
        is_charge_refundable: false,
        created: Time.new(2019, 9, 1, 12, 0, 0).to_i,
      },
      created: Time.new(2019, 9, 1, 12, 0, 0).to_i,
    )

    assert_difference(-> { @billing_transaction.disputes.count }, 1) do
      Billing::Stripe::Webhooks::ChargeDispute.perform(webhook)
    end

    dispute = @billing_transaction.disputes.last
    assert_equal "stripe", dispute.platform
    assert_equal "dp_1", dispute.platform_dispute_id
    assert_equal(-7_00, dispute.amount_in_subunits)
    assert_equal "USD", dispute.currency_code
    assert_equal "fraudulent", dispute.reason
    assert_equal "under_review", dispute.status
    refute_predicate dispute, :refundable?
    assert_equal Time.new(2019, 9, 1), dispute.response_due_by
    assert_equal @account.id, dispute.user_id
    assert_equal Time.new(2019, 9, 1, 12, 0, 0), dispute.created_at
    assert_equal Time.new(2019, 9, 1, 12, 0, 0), dispute.updated_at
  end

  test "creates a Billing::Dispute if one doesn't exist when receiving a charge.dispute.closed webhook" do
    webhook = create(
      :stripe_webhook,
      :charge_dispute_closed,
      object: {
        id: "dp_1",
        charge: @billing_transaction.transaction_id,
        amount: -7_00,
        currency: "usd",
        reason: "fraudulent",
        status: "lost",
        evidence_details: { due_by: Time.new(2019, 9, 1).to_i },
        is_charge_refundable: false,
        created: Time.new(2019, 9, 1, 12, 0, 0).to_i,
      },
      created: Time.new(2019, 9, 1, 12, 0, 0).to_i,
    )

    assert_difference(-> { @billing_transaction.disputes.count }, 1) do
      Billing::Stripe::Webhooks::ChargeDispute.perform(webhook)
    end

    dispute = @billing_transaction.disputes.last
    assert_equal "stripe", dispute.platform
    assert_equal "dp_1", dispute.platform_dispute_id
    assert_equal(-7_00, dispute.amount_in_subunits)
    assert_equal "USD", dispute.currency_code
    assert_equal "fraudulent", dispute.reason
    assert_equal "lost", dispute.status
    refute_predicate dispute, :refundable?
    assert_equal Time.new(2019, 9, 1), dispute.response_due_by
    assert_equal @account.id, dispute.user_id
    assert_equal Time.new(2019, 9, 1, 12, 0, 0), dispute.created_at
    assert_equal Time.new(2019, 9, 1, 12, 0, 0), dispute.updated_at
  end

  test "updates a Billing::Dispute when receiving a charge.dispute.updated webhook" do
    webhook_timestamp = Time.new(2019, 9, 30, 14, 0, 0)
    dispute = create(
      :billing_dispute,
      :stripe,
      :needs_response,
      platform_dispute_id: "dp_1",
      billing_transaction: @billing_transaction,
      updated_at: webhook_timestamp - 1.second,
    )

    webhook = create(
      :stripe_webhook,
      :charge_dispute_updated,
      object: {
        id: "dp_1",
        charge: @billing_transaction.transaction_id,
        status: "under_review",
      },
      created: webhook_timestamp.to_i,
    )

    Billing::Stripe::Webhooks::ChargeDispute.perform(webhook)

    assert_equal "under_review", dispute.reload.status
    assert_equal webhook_timestamp, dispute.updated_at
  end

  test "updates a Billing::Dispute when receiving a charge.dispute.closed webhook" do
    webhook_timestamp = Time.new(2019, 9, 30, 14, 0, 0)
    dispute = create(
      :billing_dispute,
      :stripe,
      :needs_response,
      platform_dispute_id: "dp_1",
      billing_transaction: @billing_transaction,
      updated_at: webhook_timestamp - 1.second,
    )

    webhook = create(
      :stripe_webhook,
      :charge_dispute_closed,
      object: {
        id: "dp_1",
        charge: @billing_transaction.transaction_id,
        status: "lost",
      },
      created: webhook_timestamp.to_i,
    )

    Billing::Stripe::Webhooks::ChargeDispute.perform(webhook)

    assert_equal "lost", dispute.reload.status
    assert_equal webhook_timestamp, dispute.updated_at
  end

  test "does not update a Billing::Dispute if it was updated more recently" do
    dispute = create(
      :billing_dispute,
      :stripe,
      :lost,
      platform_dispute_id: "dp_1",
      billing_transaction: @billing_transaction,
      updated_at: Time.new(2019, 9, 1, 14, 0, 0),
    )

    webhook = create(
      :stripe_webhook,
      :charge_dispute_updated,
      object: {
        id: "dp_1",
        charge: @billing_transaction.transaction_id,
        status: "under_review",
      },
      created: Time.new(2019, 9, 1, 12, 0, 0).to_i,
    )

    Billing::Stripe::Webhooks::ChargeDispute.perform(webhook)

    assert_equal "lost", dispute.reload.status
    assert_equal Time.new(2019, 9, 1, 14, 0, 0), dispute.updated_at
  end

  test "does not create duplicate Billing::Dispute records" do
    webhook = create(
      :stripe_webhook,
      :charge_dispute_created,
      object: {
        id: "dp_1",
        charge: @billing_transaction.transaction_id,
        amount: -7_00,
        currency: "usd",
        reason: "fraudulent",
        status: "needs_response",
        evidence_details: { due_by: Time.new(2019, 9, 1).to_i },
        is_charge_refundable: false,
      },
    )

    assert_difference(-> { @billing_transaction.disputes.count }, 1) do
      Billing::Stripe::Webhooks::ChargeDispute.perform(webhook)
      Billing::Stripe::Webhooks::ChargeDispute.perform(webhook)
    end
  end

  test "raises if the disputed transaction is not found" do
    webhook = create(:stripe_webhook, :charge_dispute_created, object: { charge: "does_not_exist" })

    assert_raises(ActiveRecord::RecordNotFound) do
      Billing::Stripe::Webhooks::ChargeDispute.perform(webhook)
    end
  end
end
