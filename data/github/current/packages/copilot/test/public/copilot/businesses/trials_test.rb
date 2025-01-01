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

    @business = create :business, :metered_ghec, name: "CDE Ltd", owners: [@owner], organizations: [@org1, @org2, @org3], seats: 30, trial_expires_at: Date.current + 30.days

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

  context "has_staff_created_trial_organization?" do
    test "returns true if any Copilot Business trial part of the business' organizations was created by a staff user" do
      @trial1.update!(managing_user: create(:employee))
      copilot_business = Copilot::Business.new(@business)
      assert copilot_business.has_staff_created_trial_organization?
    end

    test "returns false if no Copilot Business trial part of the business' organizations was created by a staff user" do
      copilot_business = Copilot::Business.new(@business)
      refute copilot_business.has_staff_created_trial_organization?
    end
  end

  context "#cancel_copilot_business_trials" do
    test "cancels the Copilot Business trial for all organizations part of DFD trial business" do
      @business.update! dfd_trial: true

      copilot_business = Copilot::Business.new(@business)
      copilot_business.cancel_copilot_business_trials(@owner)

      assert_equal "canceled", @trial1.reload.state
      assert_equal Date.current, @trial1.ends_at

      assert_equal "canceled", @trial2.reload.state
      assert_equal Date.current, @trial2.ends_at

      assert_equal "canceled", @trial3.reload.state
      assert_equal Date.current, @trial3.ends_at
    end

    test "disables Copilot access for all organizations part of DFD trial business" do
      @business.update! dfd_trial: true
      Copilot::Business.new(@business).enable_copilot!
      Copilot::Organization.new(@org1).enable_copilot!
      Copilot::Organization.new(@org2).enable_copilot!
      Copilot::Organization.new(@org3).enable_copilot!
      assert_predicate Copilot::Organization.new(@org1), :copilot_enabled?
      assert_predicate Copilot::Organization.new(@org2), :copilot_enabled?
      assert_predicate Copilot::Organization.new(@org3), :copilot_enabled?

      copilot_business = Copilot::Business.new(@business)
      copilot_business.cancel_copilot_business_trials(@owner)

      assert_equal "canceled", @trial1.reload.state
      assert_equal Date.current, @trial1.ends_at
      refute_predicate Copilot::Organization.new(@org1), :copilot_enabled?

      assert_equal "canceled", @trial2.reload.state
      assert_equal Date.current, @trial2.ends_at
      refute_predicate Copilot::Organization.new(@org2), :copilot_enabled?

      assert_equal "canceled", @trial3.reload.state
      assert_equal Date.current, @trial3.ends_at
      refute_predicate Copilot::Organization.new(@org3), :copilot_enabled?
    end

    test "does nothing for non-DFD trial business" do
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
    test "creates a new Copilot Business trial for all organizations part of DFD trial business" do
      @business.update! dfd_trial: true

      @trial1.destroy!
      @trial2.destroy!
      @trial3.destroy!

      copilot_business = Copilot::Business.new(@business)
      assert_equal 0, copilot_business.ongoing_organization_trials.count
      copilot_business.create_or_resume_copilot_business_trials(@owner)

      assert_equal 3, copilot_business.ongoing_organization_trials.count
      copilot_org1 = Copilot::Organization.new(@org1)
      assert_equal "recently_started", copilot_org1.business_trial&.state

      copilot_org2 = Copilot::Organization.new(@org2)
      assert_equal "recently_started", copilot_org2.business_trial&.state

      copilot_org3 = Copilot::Organization.new(@org3)
      assert_equal "recently_started", copilot_org3.business_trial&.state
    end

    test "enables Copilot access for a new Copilot Business trial of an eligible organization" do
      @business.update! dfd_trial: true
      @trial1.destroy!

      copilot_org1 = Copilot::Organization.new(@org1)
      refute_predicate copilot_org1, :copilot_enabled?

      copilot_business = Copilot::Business.new(@business)
      copilot_business.create_or_resume_copilot_business_trials(@owner)

      copilot_org1 = Copilot::Organization.new(@org1.reload)
      assert_predicate copilot_org1, :copilot_enabled?
      assert_equal "recently_started", copilot_org1.business_trial&.state
    end

    test "does nothing for non-DFD trial business" do
      @trial1.destroy!
      @trial2.destroy!
      @trial3.destroy!

      copilot_business = Copilot::Business.new(@business)
      assert_empty copilot_business.ongoing_organization_trials
      copilot_business.create_or_resume_copilot_business_trials(@owner)

      assert_empty copilot_business.ongoing_organization_trials
    end

    test "does nothing for DFD trial business whose remaining trial days is not greater than 0" do
      @business.update! dfd_trial: true, trial_expires_at: 5.days.ago
      @trial1.destroy!
      @trial2.destroy!
      @trial3.destroy!

      copilot_business = Copilot::Business.new(@business)
      assert_equal 0, @business.trial_days_remaining.to_i
      assert_empty copilot_business.ongoing_organization_trials
      copilot_business.create_or_resume_copilot_business_trials(@owner)

      assert_empty copilot_business.ongoing_organization_trials
    end

    test "resumes the Copilot Business trials for all organizations part of a business if it already exists" do
      @business.update! dfd_trial: true
      @trial1.update!(state: :canceled)  # Cancel all the CB trials
      @trial2.update!(state: :canceled)
      @trial3.update!(state: :canceled)

      copilot_business = Copilot::Business.new(@business)
      copilot_business.create_or_resume_copilot_business_trials(@owner)

      assert_equal "recently_started", @trial1.reload.state
      assert_equal "recently_started", @trial2.reload.state
      assert_equal "recently_started", @trial3.reload.state
    end

    test "re-enables Copilot access for an existing Copilot Business trial of an eligible organization" do
      @business.update! dfd_trial: true
      Copilot::Organization.new(@org1).disable_copilot!
      Copilot::Organization.new(@org2).disable_copilot!
      Copilot::Organization.new(@org3).disable_copilot!

      copilot_business = Copilot::Business.new(@business)
      copilot_business.cancel_copilot_business_trials(@owner)

      refute_predicate Copilot::Organization.new(@org1), :copilot_enabled?
      refute_predicate Copilot::Organization.new(@org2), :copilot_enabled?
      refute_predicate Copilot::Organization.new(@org3), :copilot_enabled?

      assert_equal "canceled", @trial1.reload.state
      assert_equal "canceled", @trial2.reload.state
      assert_equal "canceled", @trial3.reload.state

      copilot_business = Copilot::Business.new(@business)
      copilot_business.create_or_resume_copilot_business_trials(@owner)

      assert_predicate Copilot::Organization.new(@org1), :copilot_enabled?
      assert_predicate Copilot::Organization.new(@org2), :copilot_enabled?
      assert_predicate Copilot::Organization.new(@org3), :copilot_enabled?
    end

    test "does nothing if the business is not on a GHE trial" do
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

  context "#create_or_resume_copilot_business_trial" do
    test "creates a new Copilot Business trial for a single organization part of a business" do
      @business.update! dfd_trial: true

      @trial1.destroy!

      copilot_business = Copilot::Business.new(@business)
      assert_equal 2, copilot_business.ongoing_organization_trials.count  # Org2 and Org3 still have a trial
      copilot_business.create_or_resume_copilot_business_trial(@owner, @org1)

      assert_equal 3, copilot_business.ongoing_organization_trials.count  # Org1 now has a trial
      copilot_org1 = Copilot::Organization.new(@org1)
      assert_equal "recently_started", copilot_org1.business_trial&.state
    end

    test "resumes the Copilot Business trials for a single organization part of a business" do
      @trial1.update!(state: :canceled)  # Cancel this CB trial

      copilot_business = Copilot::Business.new(@business)
      copilot_business.create_or_resume_copilot_business_trial(@owner, @org1)

      assert_equal "recently_started", @trial1.reload.state
    end
  end

  context "#upgrade_copilot_business_trials" do
    test "upgrades the Copilot Business trial for all organizations part of DFD trial business" do
      @business.update! dfd_trial: true
      Business.any_instance.stubs(:metered_services_billable?).returns(billable: true, reason: nil)

      copilot_business = Copilot::Business.new(@business)
      copilot_business.upgrade_copilot_business_trials(@owner)

      assert_equal "upgraded", @trial1.reload.state
      assert_equal "upgraded", @trial2.reload.state
      assert_equal "upgraded", @trial3.reload.state
    end

    test "does nothing for non-DFD trial business" do
      Business.any_instance.stubs(:metered_services_billable?).returns(billable: true, reason: nil)

      copilot_business = Copilot::Business.new(@business)
      copilot_business.upgrade_copilot_business_trials(@owner)

      assert_equal "recently_started", @trial1.reload.state
      assert_equal "recently_started", @trial2.reload.state
      assert_equal "recently_started", @trial3.reload.state
    end
  end

end if GitHub.copilot_enabled?
