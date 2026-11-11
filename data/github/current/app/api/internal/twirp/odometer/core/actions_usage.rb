# typed: true
# frozen_string_literal: true

require "active_support/concern"

module Api::Internal::Twirp::Odometer
  module Core
    module ActionsUsage
      extend ActiveSupport::Concern

      SKU_ACTIONS_STORAGE = "actions_storage"


      def billing_platform_client
        @billing_platform_client ||= Billing::Platform::Api::Client.new
      end

      # The included actions minutes included limit. For the legacy/default billing platform calls actions_included_private_minutes.
      # For Licensify, it calls the billing platform API to get the discounts. Unfortunately, there aren't helper
      # methods to just return the included limit and the logic is spread across ruby and react.
      def business_actions_limit(business)
        # https://github.com/github/github/blob/931fccf048c4caedda2602afcc5abedea6f002d6/ui/packages/billing-app/utils/discount.ts#L88-L91 :/
        actions_discount_map = {
          800 => 100_000,
          400 => 50_000,
          24 => 3_000,
          16 => 2_000,
        }
        if business.customer.billed_via_billing_platform?
          # https://github.com/github/github/blob/91ea35fcc9555c1952ed4f10677e9af377214326/app/controllers/concerns/billing/discounts_dependency.rb#L73
          # https://github.com/github/billing-platform/blob/e59b518387cd2cd77ad95186f0ae9f6bf15fa11b/proto/customer-api.proto#L144C9-L144C37
          # https://github.com/github/billing-platform/blob/716c796b663d4251ec845d2c33a7ddd346b89634/lib/engines/discount.go#L522
          discounts = billing_platform_client.get_all_discount_states(
            customer_id: business.customer.id, year: Time.now.utc.year, month: Time.now.utc.month)
          actions_discounts = if discounts.is_a?(Hash)
            discounts[:discounts]&.select do |discount|
              discount[:targets]&.any? { |t| t[:id]&.start_with?("actions_") && t[:id] != SKU_ACTIONS_STORAGE }
            end
          else
            []
          end
          actions_discount = actions_discounts&.first&.dig(:targetAmount)&.to_i
          if actions_discount
            actions_discount_map[actions_discount]
          else
            business.trial? ? actions_discount_map[24] : actions_discount_map[400]
          end
        else
          business.plan.actions_included_private_minutes
        end
      end

      def actions_consumed(entity)
        return 0 unless entity&.customer
        # 166f08f3/app/controllers/concerns/billing/usage_table.rb#L15
        # 166f08f3/packages/billing/app/public/billing/public/usage/query_builder.rb#L18C68-L18C116
        if entity.customer&.billed_via_billing_platform?
          product = "actions"
          group = BillingPlatform::Base::UsageGroupBy::GroupByProduct.to_s
          this_month_query = Billing::Public::Usage::QueryBuilder.build(entity, group:, product:, period: BillingSettingsHelper::USAGE_PERIOD[:this_month])
          last_month_query = Billing::Public::Usage::QueryBuilder.build(entity, group:, product:, period: BillingSettingsHelper::USAGE_PERIOD[:last_month])
          this_month_usage_response = billing_platform_client.get_net_usage_line_items(**T.unsafe(**this_month_query))
          last_month_usage_response = billing_platform_client.get_net_usage_line_items(**T.unsafe(**last_month_query))
          if this_month_usage_response.is_a?(Billing::Platform::Api::Error) || last_month_usage_response.is_a?(Billing::Platform::Api::Error)
            return 0
          end
          this_month_usage = this_month_usage_response
            &.dig(:netUsageItems)
            &.select { |item| item[:sku] != SKU_ACTIONS_STORAGE }
            &.map { |item| item[:quantity] }
            &.sum
          thirty_days_ago = (30.days.ago.to_f * 1000).to_i
          partial_last_month_usage = last_month_usage_response
            &.dig(:netUsageItems)
            &.select { |item| item[:sku] != SKU_ACTIONS_STORAGE && item[:usageAt] > thirty_days_ago }
            &.map { |item| item[:quantity] }
            &.sum
          this_month_usage.to_i + partial_last_month_usage.to_i
        else
          begin
            actions_usage = ::Billing::ActionsUsage.product_usage(entity)
            if actions_usage.has_error?
              0
            else
              actions_usage.total_minutes_used
            end
          end
        end
      end
    end
  end
end
