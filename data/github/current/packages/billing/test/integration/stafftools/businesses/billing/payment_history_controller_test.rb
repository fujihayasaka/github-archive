# typed: true
# frozen_string_literal: true

require "test_helper"

class Stafftools::Businesses::Billing::PaymentHistoryControllerTest < GitHub::IntegrationTestCase
  fixtures do
    @staff = create(:staff_admin_user)
    @transaction = create(:billing_transaction, :business_owned)
    @business = @transaction.billable_entity
    @user = @business.owners.first
  end

  context "GET :index" do
    test "loads when user has neither transactions nor disputes" do
      business = create(:business, :with_self_serve_payment)
      as @staff
      get "/stafftools/enterprises/#{business}/billing/payment_history"

      assert_response :ok
      assert_test_selector "payment-history", text: /#{business} has not made any self-serve payments/
      refute_test_selector "dispute-history"
    end

    test "shows credit card transactions" do
      transaction = create(:billing_transaction, customer: @business.customer)

      as @staff
      get "/stafftools/enterprises/#{@business}/billing/payment_history"

      assert_response :ok
      assert_test_selector "payment-history" do
        assert_select "a", transaction.transaction_id.last(8).upcase
      end
      refute_test_selector "dispute-history"
    end

    test "handles billing transactions with no transaction_id" do
      create(:billing_transaction, :failed, customer: @business.customer, transaction_id: nil)

      as @staff
      get "/stafftools/enterprises/#{@business}/billing/payment_history"

      assert_response :success
    end

    test "shows disputes" do
      skip "Disputes are not supported for enterprise accounts"
      dispute = create(:billing_dispute, customer: @business.customer)

      as @staff
      get "/stafftools/enterprises/#{@business}/billing/payment_history"

      assert_response :ok
      assert_test_selector "dispute-history" do
        assert_select "a", dispute.platform_dispute_id.last(8).upcase
        assert_select "a[title='Respond to Dispute in Stripe']"
        assert_select "a[title='Open Transaction in Zuora']"
        assert_select "a[title='Open Dispute in Stripe']"
      end
      assert_test_selector "payment-history", text: /#{@business} has not made any self-serve payments/
    end

    test "404s for nonexistent users" do
      as @staff
      get "/stafftools/enterprises/not-a-real-user/billing/payment_history"
      assert_response :not_found
    end

    test "404s for anonymous viewer" do
      get "/stafftools/enterprises/#{@business}/billing/payment_history"
      assert_response :not_found
    end

    test "404s for non-staff viewer" do
      as @user
      get "/stafftools/enterprises/#{@business}/billing/payment_history"
      assert_response :not_found
    end
  end
end if GitHub.billing_enabled?
