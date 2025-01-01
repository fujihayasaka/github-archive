# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Licensing::TransitionEnterpriseToMeteredLicensingJobTest < GitHub::TestCase
  include JobTestHelper
  include AuditLog::IntegrationTestHelpers
  include TurboghasHelpers
  include HydroTestHelpers

  fixtures do
    User.create_ghost
    @user = create :user
    @org = create :organization
    @org.add_member @user
    @repo = create(:private_repository, owner: @org, from_example: :pull_request_source)

    @business = create :business, organizations: [@org]
    @business.customer.update(metered_ghe: false)
    @business.update(trial_expires_at: nil)
    @business.customer.update(
      metered_via_azure: true,
      azure_subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002",
      azure_subscription_name: "Normal subscription"
    )
    stub_turboghas_summary(maximum_committers: 1, active_committers: 1)
    @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
    @business.set_advanced_security_seats_for_entity(seats: 100, actor: @user)
    @repo.enable_advanced_security!(actor: @repo.owner)
    @business.set_advanced_security_seats_for_entity(seats: 0, actor: @user)
    @business.mark_advanced_security_as_not_purchased_for_entity(actor: @user)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  test "does not run if already on metered plan", skip_enterprise: true do
    events = subscribe "business.change_licensing_model"

    @business.customer.update(metered_ghe: true)

    assert_enqueued_jobs 0, only: Billing::OnboardCustomerToProductInBillingPlatformJob do
      Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(@business, actor: @user)
    end

    assert event = events.pop, "an event was expected"
    assert_equal "business.change_licensing_model", event.name
    assert_equal "Business is already on a metered plan", event.payload[:result]
    assert_equal false, event.payload[:success]
  end

  test "does not run if metered trial is active", skip_enterprise: true do
    @business.customer.update(metered_ghe: true)
    @business.update(trial_expires_at: Date.today + 1.day)

    assert_enqueued_jobs 0, only: Billing::OnboardCustomerToProductInBillingPlatformJob do
      Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(@business, actor: @user)
    end
  end

  test "does not run with active enterprise agreement", skip_enterprise: true do
    @business.customer.update(metered_ghe: false)
    @business.update(trial_expires_at: nil)
    @business.customer.update(
      metered_via_azure: true,
      azure_subscription_id: nil,
      azure_subscription_name: nil
    )
    create(:enterprise_agreement, seats: 4, business: @business)

    Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(@business, actor: @user)
    refute @business.customer.metered_ghe
  end

  test "does not run when on a trial", skip_enterprise: true do
    @business.customer.update(metered_ghe: false)
    @business.update(trial_expires_at: Time.now + 1.day)

    Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(@business, actor: @user)
    refute @business.customer.metered_ghe
  end

  test "does not run if already onboarded to billing platform" do
    events = subscribe "business.change_licensing_model"

    create(:billing_platform_enabled_product, customer: @business.customer, ghec: true)

    Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(@business, actor: @user)

    refute @business.customer.metered_ghe

    assert event = events.pop, "an event was expected"
    assert_equal "business.change_licensing_model", event.name
    assert_equal "GHEC product already enabled for this business", event.payload[:result]
    assert_equal false, event.payload[:success]
  end

  test "instruments job errors" do
    events = subscribe "business.change_licensing_model"

    Business.any_instance.expects(:metered_plan?).raises(StandardError.new("job failure"))

    Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(@business, actor: @user)

    assert_equal 1, GitHub.dogstats.increments("licensing.transition_enterprise_to_metered_licensing").length

    assert_equal 1, events.length
    assert_equal "job failure", events.first.payload[:result]
    assert_equal false, events.first.payload[:success]
  end

  test "job transitions business to metered licensing", skip_enterprise: true do
    events = subscribe "business.change_licensing_model"

    refute BillingPlatformEnabledProduct.find_by(customer_id: @business.customer.id)&.ghec?

    Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(@business, actor: @user)

    @business.reload
    @user.business_user_account.reload

    assert BillingPlatformEnabledProduct.find_by(customer_id: @business.customer.id)&.ghec?, true
    assert @business.customer.metered_plan, true
    assert @business.customer.metered_ghe, true
    assert @business.customer.billed_via_billing_platform, true

    assert_equal 1, GitHub.dogstats.increments("licensing.transition_enterprise_to_metered_licensing").length

    assert event = events.pop, "an event was expected"
    assert_equal "business.change_licensing_model", event.name
    assert_equal "Success", event.payload[:result]
    assert_equal true, event.payload[:success]
  end

  test "Can reset GHAS configuration when requested", skip_enterprise: true do
    events = subscribe "business.change_licensing_model"

    refute BillingPlatformEnabledProduct.find_by(customer_id: @business.customer.id)&.ghec?

    perform_enqueued_jobs only: [SecurityAnalysisSettingsBatchUpdateBusinessJob, UpdateBusinessSecurityFeatureForNewReposJob, SecurityAnalysisSettingsUpdateJob] do
      Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(@business, actor: @user, reset_ghas_configuration: true)
    end

    @repo.reload
    refute @repo.advanced_security_enabled?
  end

  test "Leaves GHAS configuration alone when it was already purchased, even when a reset is requested", skip_enterprise: true do
    events = subscribe "business.change_licensing_model"

    @business.mark_advanced_security_as_purchased_for_entity(actor: @user)

    refute BillingPlatformEnabledProduct.find_by(customer_id: @business.customer.id)&.ghec?

    perform_enqueued_jobs only: [SecurityAnalysisSettingsBatchUpdateBusinessJob, UpdateBusinessSecurityFeatureForNewReposJob, SecurityAnalysisSettingsUpdateJob] do
      Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(@business, actor: @user, reset_ghas_configuration: true)
    end

    @repo.reload
    assert @repo.advanced_security_enabled?
  end

  test "Enables metered GHAS if not purchased", skip_enterprise: true do
    events = subscribe "business.change_licensing_model"
    refute @business.advanced_security_metered_for_entity?

    Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(@business, actor: @user)

    @business.reload

    assert @business.advanced_security_metered_for_entity?
  end

  test "Enables metered GHAS if purchased and not on a trial", skip_enterprise: true do
    events = subscribe "business.change_licensing_model"
    @business.mark_advanced_security_as_purchased_for_entity(actor: @user)
    @business.set_advanced_security_seats_for_entity(actor: @user, seats: 1)
    refute @business.advanced_security_metered_for_entity?

    Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(@business, actor: @user)

    @business.reload

    assert @business.advanced_security_metered_for_entity?
  end

  test "Only transitions GHAS for GHAS only transitions", skip_enterprise: true do
    events = subscribe "business.change_licensing_model"
    refute @business.advanced_security_metered_for_entity?

    Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(@business, ghas_only: true, actor: @user)

    @business.reload

    assert @business.advanced_security_metered_for_entity?
    refute @business.customer.metered_ghe
  end

  test "records error message when transitioning to metered" do
    transition = create(
      :licensing_licensing_model_transition,
      customer: @business.customer,
      licensing_model: "metered",
      actor: @user
    )

    Billing::Platform::Api::Client.any_instance
    .stubs(:get_subscribed_items)
    .returns({
      subscribedItems: []
    })

    Business.any_instance.expects(:enable_metered_product_suite).raises(StandardError.new("ohh no")).once

    Licensing::TransitionEnterpriseToMeteredLicensingJob.new.perform(
      @business,
      licensing_model_transition_id: transition.id,
      actor: @user
    )

    assert_equal "ohh no", transition.reload.message
  end

  test "job updates scheduled transition status", skip_enterprise: true do
    events = subscribe "business.change_licensing_model"

    scheduled_transition = create(:licensing_licensing_model_transition, customer: @business.customer)

    refute BillingPlatformEnabledProduct.find_by(customer_id: @business.customer.id)&.ghec?
    Licensing::LicensingModelTransition.any_instance.expects(:update!).twice

    Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(@business, licensing_model_transition_id: scheduled_transition.id, actor: @user)
  end

  test "Runs plan duration change if currently on yearly plan", skip_enterprise: true do
    @business.update! plan_duration: "year"

    actor = User.ghost

    Billing::SchedulePlanChange.stubs(:run).with(
      account: @business,
      actor: actor,
      plan_duration: Business::BillingDependency::MONTHLY_PLAN,
      active_on: GitHub::Billing.today
    ).once

    Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(
      @business,
      actor: actor
    )
  end

  test "Does not runs plan duration change if only converting GHAS", skip_enterprise: true do
    @business.update! plan_duration: "year"

    actor = User.ghost

    Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(
      @business,
      actor: actor,
      ghas_only: true
    )

    @business.reload

    assert_equal @business.plan_duration, "year"
  end

  test "Creates metered enterprise agreement when paying via Azure paper", skip_enterprise: true do
    enterprise_agreement = create(:enterprise_agreement, :github_enterprise_unified, business: @business)

    actor = User.ghost

    Licensing::TransitionEnterpriseToMeteredLicensingJob.perform_now(
      @business,
      actor: actor
    )

    enterprise_agreement.reload

    assert_equal enterprise_agreement.status, "ended"
    assert_equal @business.enterprise_agreements.last.category, "metered"
  end
end
