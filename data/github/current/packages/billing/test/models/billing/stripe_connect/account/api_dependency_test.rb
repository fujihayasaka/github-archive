# typed: true
# frozen_string_literal: true

require "test_helper"

class BilingStripeConnectAccountApiDependencyTest < GitHub::TestCase
  fixtures do
    @account = create(:stripe_connect_account)
  end

  setup do
    @balance = Stripe::Balance.construct_from({ available: [{ amount: 10, currency: "usd" }] })
  end

  context "#current_balance" do
    test "returns a balance response for an account" do
      Stripe::Balance.stubs(:retrieve).returns(@balance)
      response = @account.current_balance
      balance = response.result

      assert_predicate response, :success?
      assert_equal @balance, balance
    end

    test "returns error if request fails" do
      exception = Stripe::StripeError.new
      Stripe::Balance.stubs(:retrieve).raises(exception)
      response = @account.current_balance

      refute_predicate response, :success?
      assert_nil response.result
      assert_equal exception, response.error
    end
  end
end if GitHub.sponsors_enabled?
