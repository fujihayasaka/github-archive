# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  module Actions
    class ZuoraProductTest < GitHub::TestCase
      include GitHub::ZuoraTestHelper

      def rate_plan_charges
        Billing::Actions::ZuoraProduct.rate_plan_charges
      end

      context "#sync_to_zuora" do
        test "create the product and associated rate plans if they do not exist" do
          with_live_zuora("zuora/github_actions_product") do
            assert_difference("Billing::ProductUUID.count", rate_plan_charges.length) do
              Billing::Actions::ZuoraProduct.sync_to_zuora
            end
          end
        end

        test "uses the existing product and associated rate plans if they exist" do
          with_live_zuora("zuora/github_actions_product_already_exist") do
            Billing::Actions::ZuoraProduct.sync_to_zuora

            assert_difference("Billing::ProductUUID.count", 0) do
              Billing::Actions::ZuoraProduct.sync_to_zuora
            end
          end
        end

        test "creates rate plans in Zuora for each Operating System" do
          with_live_zuora("zuora/github_actions_product") do
            Billing::Actions::ZuoraProduct.sync_to_zuora
          end

          assert_equal rate_plan_charges.count, 2

          first_product_uuid = Billing::ProductUUID.find_by!(product_type: "github.actions", product_key: "Private Repos Usage")
          assert first_product_uuid.zuora_product_id
          assert first_product_uuid.zuora_product_rate_plan_id
          assert first_product_uuid.zuora_product_rate_plan_charge_ids[:github_actions_private_repos_usage]
          assert_equal first_product_uuid.zuora_product_rate_plan_charge_ids.keys.count, 1

          charges = first_product_uuid.charges
          assert_equal 1, charges.count
          charge = charges.first
          assert_equal "overage", charge["type"]
          assert_equal "GitHub Actions - Private Repos Usage", charge["name"]
          assert_includes first_product_uuid.zuora_product_rate_plan_charge_ids.values, charge["zuora_product_rate_plan_charge_id"]

          second_product_uuid = Billing::ProductUUID.find_by!(product_type: "github.actions", product_key: "GitHub Actions - Runners")
          assert second_product_uuid.zuora_product_id
          assert second_product_uuid.zuora_product_rate_plan_id
          assert second_product_uuid.zuora_product_rate_plan_charge_ids[:"4_core"]
          assert second_product_uuid.zuora_product_rate_plan_charge_ids[:"8_core"]
          assert second_product_uuid.zuora_product_rate_plan_charge_ids[:"16_core"]
          assert second_product_uuid.zuora_product_rate_plan_charge_ids[:"32_core"]
          assert second_product_uuid.zuora_product_rate_plan_charge_ids[:"64_core"]
          assert_equal second_product_uuid.zuora_product_rate_plan_charge_ids.keys.count, 5
          assert_equal 5, second_product_uuid.charges.count
        end
      end
    end
  end
end if GitHub.billing_enabled?
