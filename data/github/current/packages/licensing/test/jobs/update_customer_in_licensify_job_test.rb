# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class UpdateCustomerInLicensifyJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @business = create(:business)
  end

  setup do
    skip unless GitHub.billing_enabled?
  end

  test "sets sdlcLicensingModel on create" do
    assert_twirp_response(12345)

    perform_enqueued_jobs(only: UpdateCustomerInLicensifyJob) do
      create(:customer, id: 12345, metered_plan: true, billing_type: "card")
    end
  end

  test "sets sdlcLicensingModel to volume based if metered_plan is not set" do
    assert_twirp_response(12345, Licensify::Services::V1::LicensingModel::LICENSING_MODEL_VOLUME)

    perform_enqueued_jobs(only: UpdateCustomerInLicensifyJob) do
      create(:customer, id: 12345, metered_plan: false, billing_type: "card")
    end
  end

  test "sets sdlcLicensingModel on update when metered_plan changes" do
    customer = @business.customer

    assert_twirp_response(customer.id)

    perform_enqueued_jobs(only: UpdateCustomerInLicensifyJob) do
      customer.update(metered_plan: true)
    end
  end

  test "does not set sdlcLicensingModel on update when metered_plan haven't changed" do
    customer = @business.customer
    ::Licensify::Client.any_instance.expects(:upsert_customer).never

    assert_no_enqueued_jobs(only: UpdateCustomerInLicensifyJob) do
      customer.update(billed_via_billing_platform: true)
    end
  end

  test "sets sdlcTrial to true when the business is on a trial" do
    @business.update(trial_expires_at: 1.day.from_now)
    customer = @business.customer

    assert @business.trial?
    assert_twirp_response(customer.id, Licensify::Services::V1::LicensingModel::LICENSING_MODEL_METERED, true)

    perform_enqueued_jobs(only: UpdateCustomerInLicensifyJob) do
      customer.update(metered_plan: true)
    end
  end

  test "sets correct fields when the customer is a standalone org", skip_with_all_emus: true do
    customer_id = Customer.maximum(:id).next

    assert_twirp_response(customer_id, Licensify::Services::V1::LicensingModel::LICENSING_MODEL_VOLUME, false)

    perform_enqueued_jobs(only: UpdateCustomerInLicensifyJob) do
      create(:organization, customer: create(:customer, id: customer_id))
    end
  end

  test "retries on errors" do
    [
      Net::OpenTimeout,
      Net::ReadTimeout,
      Licensing::Licensify::Error,
    ].each do |error|
      assert_retry_on_error(error, UpdateCustomerInLicensifyJob, [@business.customer_id])
    end
  end

  sig { params(customer_id: Integer, expected_license_model: Integer, expected_trial: T::Boolean).void }
  def assert_twirp_response(customer_id, expected_license_model = Licensify::Services::V1::LicensingModel::LICENSING_MODEL_METERED, expected_trial = false)
    expected_args = {
      customer: {
        id: customer_id,
        sdlcLicensingModel: expected_license_model,
        sdlcTrial: expected_trial,
      }
    }

    ::Licensify::Client.any_instance.expects(:upsert_customer)
      .with(equals(expected_args))
      .returns(
        Twirp::ClientResp.new(
          data: ::Licensify::Services::V1::UpsertCustomerResponse.new,
          error: nil,
        )
      ).once
  end
end
