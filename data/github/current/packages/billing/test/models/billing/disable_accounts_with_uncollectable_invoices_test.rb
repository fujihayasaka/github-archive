# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::DisableAccountsWithUncollectableInvoicesTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @user = create(:credit_card_user, billed_on: ::GitHub::Billing.today - 1.month)
    # Account needs at least one past successful payment to be eligible for dunning
    create(:billing_transaction, user: @user, amount_in_cents: 1_00, last_status: :settled)
  end

  test "does nothing if no account found" do
    Billing::DisableAccountsWithUncollectableInvoices.perform(account: nil, amount: 10)

    assert_dogstats_increment(0, "billing.disable_accounts_with_uncollectable_invoices")
  end

  test "does not disable if account is invoiced" do
    @user.update!(billing_type: "invoice", billing_attempts: User::BillingDependency::BILLING_ATTEMPTS_LIMIT)
    assert @user.invoiced?
    assert @user.enabled?

    assert_no_changes -> { @user.enabled? } do
      Billing::DisableAccountsWithUncollectableInvoices.perform(account: @user, amount: 10)
    end

    assert_dogstats_increment(0, "billing.disable_accounts_with_uncollectable_invoices")
  end

  test "does not disable if account requires manual transactions" do
    @user.update!(billing_attempts: User::BillingDependency::BILLING_ATTEMPTS_LIMIT)
    @user.payment_method.update!(country: "IND")
    assert @user.customer.requires_manual_transactions?
    assert @user.enabled?

    assert_no_changes -> { @user.enabled? } do
      Billing::DisableAccountsWithUncollectableInvoices.perform(account: @user, amount: 10)
    end

    assert_dogstats_increment(0, "billing.disable_accounts_with_uncollectable_invoices")
  end

  test "does nothing if invoice amount is not positive" do
    @user.update!(billing_attempts: User::BillingDependency::BILLING_ATTEMPTS_LIMIT)

    Billing::DisableAccountsWithUncollectableInvoices.perform(account: @user, amount: 0)
    assert @user.reload.enabled?
    Billing::DisableAccountsWithUncollectableInvoices.perform(account: @user, amount: -10)
    assert @user.reload.enabled?

    assert_dogstats_increment(0, "billing.disable_accounts_with_uncollectable_invoices")
  end

  test "does nothing if neither the account nor the payment method reflect the need to disable" do
    @user.update!(billing_attempts: User::BillingDependency::BILLING_ATTEMPTS_LIMIT - 1)
    PaymentMethod.any_instance.expects(:external_payment_method_consecutive_failure_count).returns(2)

    assert_no_changes -> { @user.enabled? } do
      Billing::DisableAccountsWithUncollectableInvoices.perform(account: @user, amount: 10)
    end

    assert_dogstats_increment(0, "billing.disable_accounts_with_uncollectable_invoices")
  end

  test "does not disable the account if billing_attempts reflects the need to disable" do
    @user.update!(billing_attempts: User::BillingDependency::BILLING_ATTEMPTS_LIMIT)
    assert @user.enabled?

    # Even though we short-circuit, we reach out to Zuora for publishing metrics
    PaymentMethod.any_instance.expects(:external_payment_method_consecutive_failure_count).returns(2)

    assert_no_changes -> { @user.reload.enabled? } do
      Billing::DisableAccountsWithUncollectableInvoices.perform(account: @user, amount: 10)
    end

    assert_dogstats_increment(1, "billing.disable_accounts_with_uncollectable_invoices")
  end

  test "enqueues CancelPastDueProductsJob if the payment_method reflects the need to disable and the account is already disabled", skip_unless: :billing_enabled? do
    @user.update!(disabled: true, billing_attempts: 3)
    assert @user.disabled?

    external_biling_attempts = 3
    PaymentMethod.any_instance.expects(:external_payment_method_consecutive_failure_count).returns(external_biling_attempts)

    assert_enqueued_jobs(1, only: [Billing::CancelPastDueProductsJob]) do
      Billing::DisableAccountsWithUncollectableInvoices.perform(account: @user, amount: 10)
    end

    assert_dogstats_increment(1, "billing.disable_accounts_with_uncollectable_invoices")
  end

  test "disables the account if the payment_method reflects the need to disable and updates billing_attempts to match" do
    @user.update!(billing_attempts: 0)
    assert @user.enabled?

    external_biling_attempts = 3
    PaymentMethod.any_instance.expects(:external_payment_method_consecutive_failure_count).returns(external_biling_attempts)

    assert_changes -> { @user.reload.enabled? }, from: true, to: false do
      Billing::DisableAccountsWithUncollectableInvoices.perform(account: @user, amount: 10)
    end

    assert_equal external_biling_attempts, @user.billing_attempts
    assert_dogstats_increment(1, "billing.disable_accounts_with_uncollectable_invoices")
  end

  test "publishes an event to Hydro with the amount, account, and payment method" do
    @user.update!(billing_attempts: 1, billed_on: ::GitHub::Billing.today - 1.month)
    payment_method = @user.payment_method

    PaymentMethod.any_instance.expects(:external_payment_method_consecutive_failure_count).returns(User::BillingDependency::BILLING_ATTEMPTS_LIMIT)

    Billing::DisableAccountsWithUncollectableInvoices.perform(account: @user, amount: 10089)

    expected_hydro_message = {
      account: Hydro::EntitySerializer.user(@user),
      payment_method: {
        id: payment_method.id,
        payment_instrument_type: :CREDIT_CARD,
        credit_card_bin: payment_method.bank_identification_number,
        credit_card_unique_id: payment_method.unique_number_identifier,
      },
      invoice_amount_in_cents: 10089,
      disabled_in_dotcom: false,
      consecutive_failures_in_zuora: 3
    }
    assert_hydro_published(expected_hydro_message, schema: "github.billing.v0.PositiveInvoicePosted")
  end
end
