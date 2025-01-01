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

    Timecop.freeze do
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

  test "records error message when transitioning to volume" do
    @business.customer.update!(metered_plan: true)
    transition = create(
      :licensing_licensing_model_transition,
      customer: @business.customer,
      licensing_model: "volume",
      actor: @user
    )

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

    Timecop.freeze do
      BusinessUserAccountUpdateAttributesJob.expects(:enqueue).once
      Billing::OffboardCustomerFromProductInBillingPlatformJob.expects(:perform_now).once
      Licensing::LicensingModelTransition.any_instance.expects(:update!).twice

      Licensing::TransitionEnterpriseToVolumeLicensingJob.perform_now(@business, licensing_model_transition_id: scheduled_transition.id)
    end
  end
end
