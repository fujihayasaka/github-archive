# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PrepaidMeteredUsageRefillCreatorTest < GitHub::TestCase
  context "#create" do
    test "creates a the record and returns a hash with the status and created record" do
      owner = create(:business)
      zuora_rate_plan_charge_id = SecureRandom.hex
      expires_on = 1.year.ago.to_date
      amount_in_subunits = 10_000
      currency_code = "AUD"

      creator = Billing::PrepaidMeteredUsageRefillCreator.new(
        owner: owner,
        zuora_rate_plan_charge_id: zuora_rate_plan_charge_id,
        expires_on: expires_on,
        amount_in_subunits: amount_in_subunits,
        currency_code: currency_code,
      )

      result = creator.create
      record = result[:record]

      assert result[:success]

      assert record.persisted?
      assert_equal owner, record.owner
      assert_equal zuora_rate_plan_charge_id, record.zuora_rate_plan_charge_id
      assert_equal expires_on, record.expires_on
      assert_equal amount_in_subunits, record.amount_in_subunits
      assert_equal currency_code, record.currency_code
    end

    test "returns a hash with a false `success` value and the record with validation errors when creation fails" do
      owner = create(:business)
      zuora_rate_plan_charge_id = SecureRandom.hex
      expires_on = 1.year.ago.to_date
      currency_code = "AUD"

      creator = Billing::PrepaidMeteredUsageRefillCreator.new(
        owner: owner,
        zuora_rate_plan_charge_id: zuora_rate_plan_charge_id,
        expires_on: expires_on,
        currency_code: currency_code,
      )

      result = creator.create
      record = result[:record]

      refute result[:success]

      refute record.persisted?
      assert_equal owner, record.owner
      assert_equal zuora_rate_plan_charge_id, record.zuora_rate_plan_charge_id
      assert_equal expires_on, record.expires_on
      assert_nil record.amount_in_subunits
      assert_equal currency_code, record.currency_code
      assert record.errors.any?
    end
  end

  context "#create!" do
    test "creates a the record and returns a hash with the status and created record" do
      owner = create(:business)
      zuora_rate_plan_charge_id = SecureRandom.hex
      expires_on = 1.year.ago.to_date
      amount_in_subunits = 10_000
      currency_code = "AUD"

      creator = Billing::PrepaidMeteredUsageRefillCreator.new(
        owner: owner,
        zuora_rate_plan_charge_id: zuora_rate_plan_charge_id,
        expires_on: expires_on,
        amount_in_subunits: amount_in_subunits,
        currency_code: currency_code,
      )

      result = creator.create!
      record = result[:record]

      assert result[:success]

      assert record.persisted?
      assert_equal owner, record.owner
      assert_equal zuora_rate_plan_charge_id, record.zuora_rate_plan_charge_id
      assert_equal expires_on, record.expires_on
      assert_equal amount_in_subunits, record.amount_in_subunits
      assert_equal currency_code, record.currency_code
    end

    test "raises an exception when it can't save the refill" do
      owner = create(:business)
      zuora_rate_plan_charge_id = SecureRandom.hex
      expires_on = 1.year.ago.to_date
      currency_code = "AUD"

      creator = Billing::PrepaidMeteredUsageRefillCreator.new(
        owner: owner,
        zuora_rate_plan_charge_id: zuora_rate_plan_charge_id,
        expires_on: expires_on,
        currency_code: currency_code,
      )

      assert_raises ActiveRecord::RecordInvalid do
        creator.create!
      end
    end
  end
end
