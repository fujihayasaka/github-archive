# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotBusinessesTrialsTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @owner = create :user
    @org1 = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admins: [@owner]
    @org2 = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admins: [@owner]
    @org3 = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admins: [@owner]

    @business = create :business, :with_self_serve_payment, name: "CDE Ltd", owners: [@owner], organizations: [@org1, @org2, @org3], seats: 30, trial_expires_at: Date.current + 30.days

    @trial1 = create(:copilot_business_trial, trialable: @org1, trialable_type: "Organization", state: :recently_started, ends_at: @business.trial_expires_at)
    @trial2 = create(:copilot_business_trial, trialable: @org2, trialable_type: "Organization", state: :recently_started, ends_at: @business.trial_expires_at)
    @trial3 = create(:copilot_business_trial, trialable: @org3, trialable_type: "Organization", state: :recently_started, ends_at: @business.trial_expires_at)
  end

  context "has_trial_organization?" do
    test "it doesnt" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      refute copilot_business.has_trial_organization?
    end

    test "it does" do
      organization = create(:enterprise_linked_organization)
      trial = create(:copilot_business_trial, :organization, trialable: organization)
      organization = trial.trialable
      assert organization.business
      copilot_business = Copilot::Business.new(organization.business)

      assert copilot_business.has_trial_organization?
    end
  end

  context "#cancel_copilot_business_trials" do
    test "cancels the Copilot Business trial for all organizations part of a business if the digital_front_door_mvp feature flag is enabled" do
      GitHub.flipper[:digital_front_door_mvp].enable(@business)

      copilot_business = Copilot::Business.new(@business)
      copilot_business.cancel_copilot_business_trials(@owner)

      assert_equal "canceled", @trial1.reload.state
      assert_equal Date.current, @trial1.ends_at

      assert_equal "canceled", @trial2.reload.state
      assert_equal Date.current, @trial2.ends_at

      assert_equal "canceled", @trial3.reload.state
      assert_equal Date.current, @trial3.ends_at
    end

    test "does nothing if the digital_front_door_mvp feature flag is disabled" do
      GitHub.flipper[:digital_front_door_mvp].disable

      copilot_business = Copilot::Business.new(@business)
      copilot_business.cancel_copilot_business_trials(@owner)

      assert_equal "recently_started", @trial1.reload.state
      assert_equal @business.trial_expires_at, @trial1.ends_at

      assert_equal "recently_started", @trial2.reload.state
      assert_equal @business.trial_expires_at, @trial2.ends_at

      assert_equal "recently_started", @trial3.reload.state
      assert_equal @business.trial_expires_at, @trial3.ends_at
    end
  end

  context "#create_or_resume_copilot_business_trials" do
    test "creates a new Copilot Business trial for all organizations part of a business if the digital_front_door_mvp feature flag is enabled" do
      GitHub.flipper[:digital_front_door_mvp].enable(@business)

      @trial1.destroy!
      @trial2.destroy!
      @trial3.destroy!

      copilot_business = Copilot::Business.new(@business)
      assert_equal 0, copilot_business.ongoing_organization_trials.count
      copilot_business.create_or_resume_copilot_business_trials(@owner)

      assert_equal 3, copilot_business.ongoing_organization_trials.count
      copilot_org1 = Copilot::Organization.new(@org1)
      assert_equal "pending", copilot_org1.business_trial&.state

      copilot_org2 = Copilot::Organization.new(@org2)
      assert_equal "pending", copilot_org2.business_trial&.state

      copilot_org3 = Copilot::Organization.new(@org3)
      assert_equal "pending", copilot_org3.business_trial&.state
    end

    test "does nothing if the digital_front_door_mvp feature flag is disabled" do
      GitHub.flipper[:digital_front_door_mvp].disable

      @trial1.destroy!
      @trial2.destroy!
      @trial3.destroy!

      copilot_business = Copilot::Business.new(@business)
      assert_empty copilot_business.ongoing_organization_trials
      copilot_business.create_or_resume_copilot_business_trials(@owner)

      assert_empty copilot_business.ongoing_organization_trials
    end

    test "resumes the Copilot Business trials for all organizations part of a business if it already exists" do
      GitHub.flipper[:digital_front_door_mvp].enable(@business)
      @trial1.update!(state: :canceled)  # Cancel all the CB trials
      @trial2.update!(state: :canceled)
      @trial3.update!(state: :canceled)

      copilot_business = Copilot::Business.new(@business)
      copilot_business.create_or_resume_copilot_business_trials(@owner)

      assert_equal "pending", @trial1.reload.state  # Pending means the trial is resumed and ready to be activated
      assert_equal "pending", @trial2.reload.state
      assert_equal "pending", @trial3.reload.state
    end

    test "does nothing if the business is not on a GHE trial" do
      GitHub.flipper[:digital_front_door_mvp].enable(@business)
      @business.update!(trial_expires_at: nil)
      refute_predicate @business, :trial?

      @trial1.destroy!
      @trial2.destroy!
      @trial3.destroy!

      copilot_business = Copilot::Business.new(@business)
      copilot_business.create_or_resume_copilot_business_trials(@owner)

      assert_empty copilot_business.ongoing_organization_trials
    end
  end

  context "#upgrade_copilot_business_trials" do
    test "upgrades the Copilot Business trial for all organizations part of a business if the digital_front_door_mvp feature flag is enabled" do
      GitHub.flipper[:digital_front_door_mvp].enable(@business)
      Business.any_instance.stubs(:metered_services_billable?).returns(billable: true, reason: nil)

      copilot_business = Copilot::Business.new(@business)
      copilot_business.upgrade_copilot_business_trials(@owner)

      assert_equal "upgraded", @trial1.reload.state
      assert_equal "upgraded", @trial2.reload.state
      assert_equal "upgraded", @trial3.reload.state
    end

    test "does nothing if the digital_front_door_mvp feature flag is disabled" do
      GitHub.flipper[:digital_front_door_mvp].disable
      Business.any_instance.stubs(:metered_services_billable?).returns(billable: true, reason: nil)

      copilot_business = Copilot::Business.new(@business)
      copilot_business.upgrade_copilot_business_trials(@owner)

      assert_equal "recently_started", @trial1.reload.state
      assert_equal "recently_started", @trial2.reload.state
      assert_equal "recently_started", @trial3.reload.state
    end
  end

end if GitHub.copilot_enabled?
