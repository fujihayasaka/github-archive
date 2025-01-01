# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class PlanSubscription::CreateBillingTransaction::ChargeTypeResolverTest < GitHub::BillingTestCase
    include GitHub::ZuoraTestHelper

    def resolver(recurring_amount: 0)
      PlanSubscription::CreateBillingTransaction::ChargeTypeResolver.new(
        payment: @payment,
        recurring_amount: recurring_amount,
      )
    end

    test "#data_pack_upgrade is true when adding data packs" do
      with_live_zuora("zuora/get_data_pack_payment", match_requests_on: [:body]) do
        @payment = Billing::Zuora::Payment.find("2c92c0f865f204440165f87581616ac8")

        assert resolver.data_pack_upgrade?
        refute resolver.seats_upgrade?
        assert_equal "prorate-asset-pack-charge", resolver.charge_type
      end
    end

    test "#seats_upgrade is true when upgrading seats" do
      with_live_zuora("zuora/get_seats_payment", match_requests_on: [:body]) do
        @payment = Billing::Zuora::Payment.find("2c92c0f8661febcc0166216cf59115b4")

        assert resolver.seats_upgrade?
        assert_equal "prorate-seat-charge", resolver.charge_type
      end
    end

    test "#seats_delta returns number of added seats" do
      with_live_zuora("zuora/get_seats_payment", match_requests_on: [:body]) do
        @payment = Billing::Zuora::Payment.find("2c92c0f8661febcc0166216cf59115b4")

        assert_equal 5, resolver.seats_delta
      end
    end

    test "#seats_delta works when there were previously 0 seats" do
      with_live_zuora("zuora/get_first_prorated_seat_payment", match_requests_on: [:body]) do
        @payment = Billing::Zuora::Payment.find("2c92c0f965e66fd10165ee89409b2ab7")

        assert_equal 1, resolver.seats_delta
      end
    end

    test "#seats_delta works when there are multiple seat upgrades invoices on payment" do
      with_live_zuora("zuora/get_multiple_invoice_prorated_seat_payment", match_requests_on: [:body]) do
        @payment = Billing::Zuora::Payment.find("2c92c0f86a548485016a54f00e804e90")

        assert resolver.seats_upgrade?
        assert_equal 3, resolver.seats_delta # Multiple Seat Upgrade Invoices 0 -> 1 -> 3
        assert_equal "prorate-seat-charge", resolver.charge_type
      end
    end

    test "#asset_packs_delta returns number of added asset packs" do
      with_live_zuora("zuora/get_data_pack_payment", match_requests_on: [:body]) do
        @payment = Billing::Zuora::Payment.find("2c92c0f865f204440165f87581616ac8")

        assert_equal 2, resolver.asset_packs_delta
      end
    end

    test "first time upgrade to a per seat plan is not a seat or data pack upgrade" do
      with_live_zuora("zuora/get_org_payment_by_id", match_requests_on: [:body]) do
        @payment = Billing::Zuora::Payment.find("2c92c0fa65f203fe0165f26534da55e6")

        refute resolver.seats_upgrade?
        refute resolver.data_pack_upgrade?
        assert_equal "prorate-charge", resolver.charge_type
      end
    end

    test "switching between per seat plans is not a seat or data pack upgrade" do
      with_live_zuora("zuora/get_plan_change_payment", match_requests_on: [:body]) do
        @payment = Billing::Zuora::Payment.find("2c92c0f9661ff98001662178d2ea7ec9")

        refute resolver.seats_upgrade?
        refute resolver.data_pack_upgrade?
        assert_equal "prorate-charge", resolver.charge_type
      end
    end

    test "duration change is not a seat or data pack upgrade" do
      with_live_zuora("zuora/get_duration_change_payment", match_requests_on: [:body]) do
        @payment = Billing::Zuora::Payment.find("2c92c0f865f2044b0165fd2b35344fab")

        refute resolver.seats_upgrade?
        refute resolver.data_pack_upgrade?
        assert_equal "prorate-charge", resolver.charge_type
      end
    end

    test "reoccuring charge when recurring_amount equals sum of line items" do
      with_live_zuora("zuora/get_org_payment_by_id", match_requests_on: [:body]) do
        @payment = Billing::Zuora::Payment.find("2c92c0fa65f203fe0165f26534da55e6")

        # $21 GitHub Business Plan - Month
        recurring_amount = BigDecimal(21)
        resolver = resolver(recurring_amount: recurring_amount)

        refute resolver.seats_upgrade?
        refute resolver.data_pack_upgrade?
        assert_nil resolver.charge_type
      end
    end

    test "excludes usage overages to determine if recurring charge" do
      with_live_zuora("zuora/get_usage_payment", match_requests_on: [:body]) do
        @payment = Billing::Zuora::Payment.find("2c92c0f96ded2167016df40ee0440636")

        # $7 (GitHub Pro) - Excludes Usage overages
        recurring_amount = BigDecimal(7)
        resolver = resolver(recurring_amount: recurring_amount)

        refute resolver.seats_upgrade?
        refute resolver.data_pack_upgrade?
        assert_nil resolver.charge_type
      end
    end

    test "excludes zero quantity usage charges when determining charge type" do
      with_live_zuora("zuora/get_usage_and_copilot_payment", match_requests_on: [:body]) do
        @payment = Billing::Zuora::Payment.find("8ad088718499b10101849ca5acff145e")

        assert_equal "prorate-charge", resolver.charge_type
      end
    end
  end
end
