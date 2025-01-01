# typed: true
# frozen_string_literal: true

require "test_helper"

class ZuoraDeleteCardsFromAccountJobTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper

  test "uses the 'zuora' queue" do
    assert_enqueued_jobs(1, queue: :zuora) do
      ZuoraDeleteCardsFromAccountJob.perform_later("the_account_id")
    end
  end

  test "retries on Zuorest::HttpError" do
    fake_zuora = FakeZuora.mock
    http_error = Zuorest::HttpError.new \
      400, { error: "Testing error" }.to_json
    fake_zuora.expects(:update_action).raises(http_error)
    ZuoraDeleteCardsFromAccountJob.any_instance.expects(:retry_job)

    assert_nothing_raised do
      ZuoraDeleteCardsFromAccountJob.perform_now("the_account_id")
    end
  end

  test "retries on Zuorest::TooManyRequestsError" do
    fake_zuora = FakeZuora.mock
    http_error = Zuorest::TooManyRequestsError.new \
      429, { error: "Testing error" }.to_json
    fake_zuora.expects(:update_action).raises(http_error)
    ZuoraDeleteCardsFromAccountJob.any_instance.expects(:retry_job)

    assert_nothing_raised do
      ZuoraDeleteCardsFromAccountJob.perform_now("the_account_id")
    end
  end

  test "deletes all the cards associated with an account" do
    # This account was set up in Zuora Sandbox 2 with a credit card
    zuora_account_id = "2c92c0f95d59764d015d7be3e51402e5"
    with_live_zuora("zuora/find_and_delete_cards_from_account") do
      payment_methods = Zuorest::Model::PaymentMethod.find_by_account_id(zuora_account_id)
      refute_empty payment_methods

      ZuoraDeleteCardsFromAccountJob.perform_now(zuora_account_id)

      payment_methods = Zuorest::Model::PaymentMethod.find_by_account_id(zuora_account_id)
      assert_empty payment_methods
    end
  end
end if GitHub.billing_enabled?
