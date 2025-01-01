# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Licensing::TransitionEnterpriseToVolumeLicensingJobTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @user = create :user
    @org = create :organization
    @org.add_member @user

    @business = create :business, organizations: [@org]
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    GitHub.flipper.disable(:licensify_enabled)
  end

  test "job only runs when business & customer are already on metered billing", skip_enterprise: true do
    @business.customer.update!(metered_ghe: false)

    assert_enqueued_jobs 0, only: Billing::OffboardCustomerFromProductInBillingPlatformJob do
      Licensing::TransitionEnterpriseToVolumeLicensingJob.perform_now(@business)
    end
  end

  test "instruments job errors" do
    events = subscribe "business.change_licensing_model"

    Business.any_instance.expects(:metered_plan?).raises(StandardError.new("job failure"))

    Licensing::TransitionEnterpriseToVolumeLicensingJob.perform_now(@business)

    assert_equal 1, GitHub.dogstats.increments("licensing.transition_enterprise_to_volume_licensing").length

    assert_equal 1, events.length
    assert_equal "job failure", events.first.payload[:result]
    assert_equal false, events.first.payload[:success]
  end

  test "job transitions business to volume licensing", skip_enterprise: true do
    events = subscribe "business.change_licensing_model"

    @business.customer.update!(metered_ghe: true)
    @user.business_user_account.update!(ghec_license: :enterprise_license)

    assert @business.metered_plan?
    assert @user.business_user_account.has_ghec_license?

    Billing::Platform::Api::Client.any_instance
      .stubs(:get_subscribed_items)
      .returns({
         subscribedItems: [{
          subscriptionId: @user.id,
          status: true,
          subscribedAt: (::GitHub::Billing.today.beginning_of_month.beginning_of_day - 1.day).to_i * 1000,
          lastBilledForAt: 0
        }]
      })

    Timecop.freeze do
      Billing::Platform::Api::Client.any_instance
        .stubs(:remove_license)
        .with(
          sku: "ghec_seats",
          subscription_at: Time.now.to_i,
          entity_detail: {
            customerId: @business.customer_id.to_s,
            actorId: @user.id,
          }
        )
        .returns(true)

      Billing::Platform::Api::Client.any_instance.expects(:remove_license).once
      BusinessUserAccountUpdateAttributesJob.expects(:enqueue).once
      Billing::OffboardCustomerFromProductInBillingPlatformJob.expects(:perform_now).once
      Licensing::LicensingModelTransition.any_instance.expects(:update!).never

      Licensing::TransitionEnterpriseToVolumeLicensingJob.perform_now(@business)

      @user.reload

      refute @business.metered_plan?
      refute @user.business_user_account.has_ghec_license?

      assert_equal 1, GitHub.dogstats.increments("licensing.transition_enterprise_to_volume_licensing").length

      assert event = events.pop, "an event was expected"
      assert_equal "business.change_licensing_model", event.name
    end
  end

  test "job fails if subscriptions can't be requested", skip_enterprise: true do
    @business.customer.update!(metered_ghe: true)
    assert @business.metered_plan?
    Billing::Platform::Api::Client.any_instance
     .stubs(:get_subscribed_items)
     .returns(Billing::Platform::Api::Error.new("Failed to request licenses"))

    Licensing::TransitionEnterpriseToVolumeLicensingJob.perform_now(@business)

    assert @business.metered_plan?
  end

  test "job fails if subscription can't be removed", skip_enterprise: true do
    @business.customer.update!(metered_ghe: true)
    assert @business.metered_plan?
    Billing::Platform::Api::Client.any_instance
     .stubs(:get_subscribed_items)
     .returns({
       subscribedItems: [{
         subscriptionId: @user.id,
         status: true,
         subscribedAt: (::GitHub::Billing.today.beginning_of_month.beginning_of_day - 1.day).to_i * 1000,
         lastBilledForAt: 0
       }]
     })

    Timecop.freeze do
      Billing::Platform::Api::Client.any_instance
        .stubs(:remove_license)
        .with(
          sku: "ghec_seats",
          subscription_at: Time.now.to_i,
          entity_detail: {
            customerId: @business.customer_id.to_s,
            actorId: @user.id,
          }
        )
        .returns(Billing::Platform::Api::Error.new("Failed to remove license"))

      Licensing::TransitionEnterpriseToVolumeLicensingJob.perform_now(@business)

      assert @business.metered_plan?
    end
  end

  test "records error message when transitioning to volume" do
    @business.customer.update!(metered_plan: true)
    transition = create(
      :licensing_licensing_model_transition,
      customer: @business.customer,
      licensing_model: "volume",
      actor: @user
    )

    Billing::Platform::Api::Client.any_instance
    .stubs(:get_subscribed_items)
    .returns({
       subscribedItems: []
    })

    Billing::OffboardCustomerFromProductInBillingPlatformJob.expects(:perform_now).raises(StandardError.new("ohh no")).once

    Licensing::TransitionEnterpriseToVolumeLicensingJob.new.perform(
      @business,
      licensing_model_transition_id: transition.id
    )

    assert_equal "ohh no", transition.reload.message
  end

  test "job updates scheduled transition status", skip_enterprise: true do
    events = subscribe "business.change_licensing_model"

    @business.customer.update!(metered_ghe: true)
    @user.business_user_account.update!(ghec_license: :enterprise_license)

    assert @business.metered_plan?
    assert @user.business_user_account.has_ghec_license?

    scheduled_transition = create(:licensing_licensing_model_transition, customer: @business.customer, licensing_model: "volume")

    Billing::Platform::Api::Client.any_instance
      .stubs(:get_subscribed_items)
      .returns({
         subscribedItems: [{
          subscriptionId: @user.id,
          status: true,
          subscribedAt: (::GitHub::Billing.today.beginning_of_month.beginning_of_day - 1.day).to_i * 1000,
          lastBilledForAt: 0
        }]
      })

    Timecop.freeze do
      Billing::Platform::Api::Client.any_instance
        .stubs(:remove_license)
        .with(
          sku: "ghec_seats",
          subscription_at: Time.now.to_i,
          entity_detail: {
            customerId: @business.customer_id.to_s,
            actorId: @user.id,
          }
        )
        .returns(true)

      Billing::Platform::Api::Client.any_instance.expects(:remove_license).once
      BusinessUserAccountUpdateAttributesJob.expects(:enqueue).once
      Billing::OffboardCustomerFromProductInBillingPlatformJob.expects(:perform_now).once
      Licensing::LicensingModelTransition.any_instance.expects(:update!).twice

      Licensing::TransitionEnterpriseToVolumeLicensingJob.perform_now(@business, licensing_model_transition_id: scheduled_transition.id)
    end
  end
end
