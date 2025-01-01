# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class InvoicedOrganizationSetSpendingLimitBannerComponent < ApplicationComponent
      def initialize(organization:, dismissed_notice:, override_spending_limit_path: nil)
        @organization = organization
        @override_spending_limit_path = override_spending_limit_path
        @dismissed_notice = dismissed_notice
      end

      def render?
        @organization.invoiced? && !@dismissed_notice
      end

      def call
        render(InvoicedSetSpendingLimitBannerComponent.new(
          spending_limit_path: spending_limit_path,
          dismissal_path: dismissal_path
        ))
      end

      # Some organizations are billed by the business, and the spending limit
      # is managed there
      def spending_limit_path
        return @override_spending_limit_path if @override_spending_limit_path
        settings_org_billing_tab_path(organization_id: @organization.display_login, tab: "spending_limit")
      end

      def dismissal_path
        dismiss_org_notice_path(@organization, input: { organizationId: @organization.id, notice: "invoiced_customer_set_spending_limit" })
      end
    end
  end
end
