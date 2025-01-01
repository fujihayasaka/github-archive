# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdateExternalCustomerJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::BillingTest
  include GitHub::ZuoraTestHelper

  test "updates zuora customer name, soldToContact, and billToContact for a customer object tied to a user" do
    user = create :user
    zuora_successful_customer_account_creation(user)
    with_live_zuora("zuora/update_customer_account_name") do
      refute_equal user.login, user.customer.zuora_account["basicInfo"]["name"]
      refute_equal user.login, user.customer.zuora_account["billToContact"]["firstName"]
      refute_equal user.login, user.customer.zuora_account["billToContact"]["lastName"]
      refute_equal user.login, user.customer.zuora_account["soldToContact"]["firstName"]
      refute_equal user.login, user.customer.zuora_account["soldToContact"]["lastName"]

      user.update_column(:login, "updated-name")
      user.update_column(:display_login, "updated-name")
      ::UpdateExternalCustomerJob.perform_now(user.customer)

      assert_equal user.login, user.customer.zuora_account["basicInfo"]["name"]
      assert_equal user.login, user.customer.zuora_account["billToContact"]["firstName"]
      assert_equal user.login, user.customer.zuora_account["billToContact"]["lastName"]
      assert_equal user.login, user.customer.zuora_account["soldToContact"]["firstName"]
      assert_equal user.login, user.customer.zuora_account["soldToContact"]["lastName"]
    end
  end

  test "updates zuora customer name, soldToContact, and billToContact for a customer object tied to a business" do
    business = create :business
    zuora_successful_customer_account_creation(business)
    customer = business.reload.customer

    with_live_zuora("zuora/update_customer_account_name_for_business") do
      before_update_account = customer.zuora_account
      refute_equal business.name, before_update_account["basicInfo"]["name"]
      refute_equal business.name, before_update_account["billToContact"]["firstName"]
      refute_equal business.name, before_update_account["billToContact"]["lastName"]
      refute_equal business.name, before_update_account["soldToContact"]["firstName"]
      refute_equal business.name, before_update_account["soldToContact"]["lastName"]

      business.update_column(:name, "completely-new-slug")
      ::UpdateExternalCustomerJob.perform_now(customer)

      after_update_account = customer.zuora_account
      assert_equal business.name, after_update_account["basicInfo"]["name"]
      assert_equal business.name, after_update_account["billToContact"]["firstName"]
      assert_equal business.name, after_update_account["billToContact"]["lastName"]
      assert_equal business.name, after_update_account["soldToContact"]["firstName"]
      assert_equal business.name, after_update_account["soldToContact"]["lastName"]
    end
  end

  test "retries job on common HTTP and Zuora errors" do
    user = create(:user, :zuora, plan: GitHub::Plan.pro)

    [
      Errno::ECONNREFUSED.new("Boom"),
      Errno::ECONNRESET.new("Boom"),
      Errno::ETIMEDOUT.new("Boom"),
      Faraday::ConnectionFailed.new("Boom"),
      Faraday::TimeoutError.new("Boom"),
      Zuorest::HttpError.new(500, {}),
      Net::ReadTimeout.new,
    ].each do |error|
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      user.update_column(:login, "updated-name")
      user.update_column(:display_login, "updated-name")
      user.customer.expects(:update_external_account_name).raises(error)

      ::UpdateExternalCustomerJob.perform_now(user.customer)

      assert_equal 1, GitHub.dogstats.increments("active_job.retry", tags: [
        "class:update_external_customer_job",
        "queue:billing",
        "adapter:#{UpdateExternalCustomerJob.queue_adapter_name}",
        "error:#{error.class.name&.underscore}",
      ]).length, "Expected job to be retried on #{error.class.name}, but it wasn't"
    end
  end

  test "retries using the ZuoraRateLimitHandler for too many requests error" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    user = create(:user, :zuora, plan: GitHub::Plan.pro)

    user.update_column(:login, "updated-name")
    user.update_column(:display_login, "updated-name")
    user.customer.expects(:update_external_account_name)
      .raises(Zuorest::TooManyRequestsError.new("", {}, { "RateLimit-Reset" => "600" }))
    Failbot.expects(:report).never

    assert_enqueued_jobs(1, only: UpdateExternalCustomerJob) do
      UpdateExternalCustomerJob.perform_now(user.customer)
    end

    assert_dogstats_increment 1, "billing.zuora_rate_limit_error", tags: ["class:update_external_customer_job"]
  end
end
