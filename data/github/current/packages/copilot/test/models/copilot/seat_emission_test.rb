# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::SeatEmissionTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    GitHub::Logger.stubs(:log).returns(true)
    GitHub.flipper[:strict_zuora_validation_on_metered_billable_check].enable
  end

  context "validates" do
    test "factory" do
      seat_emission = build(:copilot_seat_emission)
      assert seat_emission.valid?
    end

    test "requires emission" do
      seat_emission = build(:copilot_seat_emission)
      seat_emission.emission = nil
      refute seat_emission.valid?
      refute_nil seat_emission.errors[:emission]

      seat_emission.emission = {}
      refute seat_emission.valid?
      assert_equal ["can't be blank", "must have a meuse_payload or billing_platform_payload key"], seat_emission.errors[:emission]

      seat_emission.emission = { meuse_payload: {} }
      refute seat_emission.valid?
      errors = seat_emission.errors[:emission]
      Copilot::SeatEmission::REQUIRED_EMISSION_KEYS.each do |key|
        assert_includes errors, "must have a #{key} key"
      end

      seat_emission = Copilot::SeatEmission.new
      seat_emission.emission = fake_emission
      refute seat_emission.valid?
      assert_equal [], seat_emission.errors[:emission]
    end

    test "requires unique_id" do
      seat_emission = Copilot::SeatEmission.new
      refute seat_emission.valid?
      refute_nil seat_emission.errors[:unique_id]

      seat_emission.unique_id = SecureRandom.uuid
      refute seat_emission.valid?
      assert_equal [], seat_emission.errors[:unique_id]
    end

    test "requires quantity" do
      seat_emission = Copilot::SeatEmission.new
      refute seat_emission.valid?
      refute_nil seat_emission.errors[:quantity]

      seat_emission.quantity = Faker::Number.within(range: 0.0..1.0)
      refute seat_emission.valid?
      assert_equal [], seat_emission.errors[:quantity]
    end

    test "requires occurred_at" do
      seat_emission = Copilot::SeatEmission.new
      refute seat_emission.valid?
      refute_nil seat_emission.errors[:occurred_at]

      seat_emission.occurred_at = Time.zone.now
      refute seat_emission.valid?
      assert_equal [], seat_emission.errors[:occurred_at]
    end

    test "put it all together" do
      organization = create(:business_organization)
      seat_emission = Copilot::SeatEmission.new(
        emission: fake_emission,
        occurred_at: Time.now,
        owner: organization,
        quantity: Faker::Number.within(range: 0.0..1.0),
        unique_id: SecureRandom.uuid
      )
      assert seat_emission.valid?
      seat_emission.save!
      assert seat_emission.owner == organization
    end

    test "put it all together with a business owner" do
      organization = create(:business_organization)
      seat_emission = Copilot::SeatEmission.new(
        emission: fake_emission,
        occurred_at: Time.now,
        owner: organization.business,
        quantity: Faker::Number.within(range: 0.0..1.0),
        unique_id: SecureRandom.uuid
      )
      assert seat_emission.valid?
      seat_emission.save!
      assert seat_emission.owner == organization.business
    end

    test "put it all together for billing platform emission" do
      organization = create(:business_organization)
      seat_emission = Copilot::SeatEmission.new(
        emission: fake_emission_billing_platform,
        occurred_at: Time.now,
        owner: organization,
        quantity: Faker::Number.within(range: 0.0..1.0),
        unique_id: SecureRandom.uuid
      )
      assert seat_emission.valid?
      seat_emission.save!
      assert seat_emission.owner == organization
    end

    test "requires 24 hours between emissions" do
      travel_to(DateTime.new(2023, 4, 1, 12, 0, 0)) do
        organization = create(:business_organization)
        create(:copilot_seat_emission, owner: organization, occurred_at: 1.hour.ago)
        seat_emission = Copilot::SeatEmission.new(
          emission: fake_emission,
          occurred_at: Time.now,
          owner: organization,
          quantity: Faker::Number.within(range: 0.0..1.0),
          unique_id: SecureRandom.uuid
        )
        refute seat_emission.valid?
        assert_equal ["already have an emission for this date"], seat_emission.errors[:occurred_at]
        assert_raises(ActiveRecord::RecordInvalid) { seat_emission.save! }
      end
    end
  end

  context ".can_emit?" do
    test "returns false and clean up any seats if doesn't have copilot for business" do
      organization = create(:credit_card_organization)
      co = Copilot::Organization.new(organization)
      Copilot::OrganizationCleaner.expects(:call).with(organization.id, T.must(co.customer_for).id, ::Copilot::COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]).once
      refute Copilot::Organization.new(organization).has_copilot_for_business?
      refute Copilot::SeatEmission.can_emit?(organization, allow_cleanup: true)
    end

    test "returns false but doesn't clean up any seats if doesn't have copilot for business and the cleanup flag is off" do
      organization = create(:credit_card_organization)
      co = Copilot::Organization.new(organization)
      Copilot::OrganizationCleaner.expects(:call).with(organization.id, T.must(co.customer_for).id, ::Copilot::COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]).never
      refute Copilot::Organization.new(organization).has_copilot_for_business?
      refute Copilot::SeatEmission.can_emit?(organization)
    end

    test "returns false if in free feature flag" do
      organization = create(:copilot_for_business_enabled_free_organization)
      co = Copilot::Organization.new(organization)
      Copilot::OrganizationCleaner.expects(:call).with(organization.id, T.must(co.customer_for).id).never
      refute Copilot::SeatEmission.can_emit?(organization, allow_cleanup: true)
    end

    test "returns false if on Copilot Business trial" do
      organization = create(:copilot_for_business_enabled_free_organization)
      create(:copilot_business_trial, :organization, :active, trialable: organization)
      co = Copilot::Organization.new(organization)
      assert co.on_free_copilot_business_trial?
      Copilot::OrganizationCleaner.expects(:call).with(organization.id, T.must(co.customer_for).id).never
      refute Copilot::SeatEmission.can_emit?(organization, allow_cleanup: true)
    end

    test "returns true if on Copilot Enterprise trial" do
      organization = create(:copilot_for_business_enabled_organization)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      create(:copilot_business_trial, :organization, :active, trialable: organization, copilot_plan: "enterprise")
      co = Copilot::Organization.new(organization)
      refute co.on_free_copilot_business_trial?
      assert Copilot::SeatEmission.can_emit?(organization, allow_cleanup: true)
    end

    test "returns true without prior emission" do
      organization = create(:copilot_for_business_enabled_organization)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      assert Copilot::SeatEmission.can_emit?(organization, allow_cleanup: true)
    end

    test "returns true with prior emission older than a day" do
      organization = create(:copilot_for_business_enabled_organization)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      create(:copilot_seat_emission, owner: organization, occurred_at: 20.days.ago)
      assert Copilot::SeatEmission.can_emit?(organization, allow_cleanup: true)
    end

    test "returns false with prior emission younger? than a day and in flag" do
      organization = create(:copilot_for_business_enabled_organization)
      travel_to(Time.new(2020, 1, 1, 12, 0, 0, 0)) do # 12 because the db still loves PST
        create(:copilot_seat_emission, owner: organization, occurred_at: 1.hour.ago)
        refute Copilot::SeatEmission.can_emit?(organization, allow_cleanup: true)
      end
    end

    test "returns false and reports an error when the org is spammy" do
      organization = create(:copilot_for_business_enabled_organization)
      organization.mark_as_spammy
      co = Copilot::Organization.new(organization)
      reason = ::Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]

      Copilot::OrganizationCleaner.expects(:call).with(organization.id, T.must(co.customer_for).id, reason).once
      refute Copilot::SeatEmission.can_emit?(organization, allow_cleanup: true)
      stats = GitHub.dogstats.increments("copilot.seat_emission.cannot_emit")
      assert_equal(1, stats.count)
      assert_equal(2, stats.first.tags.count)
    end

    test "returns false, cleans org, and reports an error when the org is not billable" do
      org = create(:copilot_for_business_enabled_organization)

      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(false)
      reason = ::Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]

      Copilot::OrganizationCleaner.expects(:call).with(org.id, T.must(Copilot::Organization.new(org).customer_for).id, reason).once

      logs = capture_logs do
        refute Copilot::SeatEmission.can_emit?(org, allow_cleanup: true)
        stats = GitHub.dogstats.increments("copilot.seat_emission.cannot_emit")

        assert_equal(1, stats.count)
        assert_equal(2, stats.first.tags.count)
        assert_equal(
          "reason:#{reason}",
          stats.first.tags.to_a[1]
        )
      end

      assert_includes logs, "Cleaning organization that failed copilot_billable?"
      assert_includes logs, "gh.copilot.organization.id=\"#{org.id}\""
      assert_includes logs, "gh.copilot.reason=\"#{reason}\""
    end

    test "returns true when billable" do
      org = create(:copilot_for_business_enabled_organization)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      assert Copilot::SeatEmission.can_emit?(org)
    end

    test "returns false and reports an error if the org is suspended" do
      organization = create(:copilot_for_business_enabled_organization)
      organization.suspend("they are bad")
      co = Copilot::Organization.new(organization)
      reason = ::Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_suspended]

      Copilot::OrganizationCleaner.expects(:call).with(organization.id, T.must(co.customer_for).id, reason).once
      refute Copilot::SeatEmission.can_emit?(organization, allow_cleanup: true)
      stats = GitHub.dogstats.increments("copilot.seat_emission.cannot_emit")
      assert_equal(1, stats.count)
      assert_equal(2, stats.first.tags.count)
      assert_equal(
        "reason:#{reason}",
        stats.first.tags.to_a[1]
      )
    end
  end

  context "#enterprise_can_emit?" do
    test "returns false if in free feature flag" do
      business = create(:business)
      GitHub.flipper[:copilot_for_business_free].enable(business)
      refute Copilot::SeatEmission.enterprise_can_emit?(business, allow_cleanup: true)
    end

    test "returns true without prior emission" do
      business = create(:business)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
      Copilot::Business.any_instance.stubs(:copilot_disabled?).returns(false)
      assert Copilot::SeatEmission.enterprise_can_emit?(business, allow_cleanup: true)
    end

    test "returns true with prior emission older than a day" do
      business = create(:business)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
      Copilot::Business.any_instance.stubs(:copilot_disabled?).returns(false)
      create(:copilot_seat_emission, owner: business, occurred_at: 20.days.ago)
      assert Copilot::SeatEmission.enterprise_can_emit?(business, allow_cleanup: true)
    end

    test "returns false with prior emission younger? than a day and in flag" do
      business = create(:business)
      travel_to(Time.new(2020, 1, 1, 12, 0, 0, 0)) do # 12 because the db still loves PST
        create(:copilot_seat_emission, owner: business, occurred_at: 1.hour.ago)
        refute Copilot::SeatEmission.enterprise_can_emit?(business, allow_cleanup: true)
      end
    end

    test "returns false, reports an error when business is not billable" do
      business = create(:business, seats_plan_type: :basic)

      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(false)
      copilot_biz = Copilot::Business.new(business)
      copilot_biz.enable_copilot!
      reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]

      Copilot::Helpers.expects(:chatterbox_say).once

      logs = capture_logs do
        assert Copilot::SeatEmission.enterprise_can_emit?(business, allow_cleanup: true)
        stats = GitHub.dogstats.increments("copilot.seat_emission.cannot_emit")

        assert_equal(1, stats.count)
        assert_equal(2, stats.first.tags.count)
        assert_equal(
          "reason:#{reason}",
          stats.first.tags.to_a[1]
        )
      end

      assert_includes logs, "Enterprise is not billable"
      assert_includes logs, "gh.copilot.enterprise.id=\"#{business.id}\""
      assert_includes logs, "gh.copilot.reason=\"#{reason}\""
      assert_includes logs, "gh.copilot.is_standalone=\"#{copilot_biz.copilot_standalone?}\""
    end

    test "returns true if the improved_billable feature flag is disabled" do
      business = create(:business)
      Copilot::Business.any_instance.stubs(:copilot_disabled?).returns(false)

      assert Copilot::SeatEmission.enterprise_can_emit?(business, allow_cleanup: true)
    end

    test "returns false and cleans if the business is spammy" do
      business = create(:business)
      business.mark_as_spammy
      copilot_biz = Copilot::Business.new(business)
      reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]

      logs = capture_logs do
        Copilot::EnterpriseCleaner.expects(:call).with(business.id, reason).once
        refute Copilot::SeatEmission.enterprise_can_emit?(business, allow_cleanup: true)
        stats = GitHub.dogstats.increments("copilot.seat_emission.cannot_emit")

        assert_equal(1, stats.count)
        assert_equal(2, stats.first.tags.count)
        assert_equal(
          "reason:#{reason}",
          stats.first.tags.to_a[1]
        )
      end

      assert_includes logs, "Enterprise is spammy"
      assert_includes logs, "gh.copilot.enterprise.id=\"#{business.id}\""
      assert_includes logs, "gh.copilot.reason=\"#{reason}\""
      assert_includes logs, "gh.copilot.is_standalone=\"#{copilot_biz.copilot_standalone?}\""
    end

    test "returns false and cleans if the business is suspended" do
      business = create(:business)
      business.suspend("they are bad")
      copilot_biz = Copilot::Business.new(business)
      reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_suspended]

      logs = capture_logs do
        Copilot::EnterpriseCleaner.expects(:call).with(business.id, reason).once
        refute Copilot::SeatEmission.enterprise_can_emit?(business, allow_cleanup: true)
        stats = GitHub.dogstats.increments("copilot.seat_emission.cannot_emit")

        assert_equal(1, stats.count)
        assert_equal(2, stats.first.tags.count)
        assert_equal(
          "reason:#{reason}",
          stats.first.tags.to_a[1]
        )
      end

      assert_includes logs, "Enterprise is suspended"
      assert_includes logs, "gh.copilot.enterprise.id=\"#{business.id}\""
      assert_includes logs, "gh.copilot.reason=\"#{reason}\""
      assert_includes logs, "gh.copilot.is_standalone=\"#{copilot_biz.copilot_standalone?}\""
    end

    test "returns false and logs if the copilot is disabled" do
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
      business = create(:business)
      copilot_biz = Copilot::Business.new(business)
      copilot_biz.disable_copilot!
      reason = Copilot::COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]

      logs = capture_logs do
        refute Copilot::SeatEmission.enterprise_can_emit?(business, allow_cleanup: true)
        stats = GitHub.dogstats.increments("copilot.seat_emission.cannot_emit")
        assert_equal(1, stats.count)
        assert_equal(2, stats.first.tags.count)
        assert_equal(
          "reason:#{reason}",
          stats.first.tags.to_a[1]
        )
      end

      assert_includes logs, "Copilot is disabled for this enterprise"
      assert_includes logs, "gh.copilot.enterprise.id=\"#{business.id}\""
      assert_includes logs, "gh.copilot.reason=\"#{reason}\""
      assert_includes logs, "gh.copilot.is_standalone=\"#{copilot_biz.copilot_standalone?}\""
    end
  end

  sig do
    params(usage_at: T.nilable(T.any(Time, DateTime))).
    returns(T::Hash[Symbol, T.any(String, Float, Integer, T::Hash[Symbol, String])])
  end
  def fake_emission(usage_at: DateTime.now.utc)
    {
      meuse_payload: {
        usage_uuid: "00000000-0000-0000-0000-000000000000",
        product_name: "copilot",
        product_sku_name: "copilot_for_business",
        usage_at: usage_at,
        quantity: 10.0,
        account_id: 9919,
        custom_fields: { mood: "excited", happy: "yes" },
        source_uri: "test_source_uri",
      }
    }
  end

  sig do
    params(usage_at: T.nilable(T.any(Time, DateTime))).
    returns(T::Hash[Symbol, T.any(String, Float, Integer, T::Hash[Symbol, String])])
  end
  def fake_emission_billing_platform(usage_at: DateTime.now.utc)
    {
      billing_platform_payload: {
        usage_uuid: "00000000-0000-0000-0000-000000000000",
        product_name: "copilot",
        product_sku_name: "copilot_for_business",
        usage_at: usage_at,
        quantity: 10.0,
        account_id: 9919,
        custom_fields: { mood: "excited", happy: "yes" },
        source_uri: "test_source_uri",
      }
    }
  end
end if GitHub.copilot_enabled?
