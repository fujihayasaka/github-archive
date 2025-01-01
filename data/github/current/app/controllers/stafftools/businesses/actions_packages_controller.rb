# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class ActionsPackagesController < Stafftools::Businesses::BusinessBaseController

      depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql5,
      only: [:show]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:show], optional: true

      def show
        render "stafftools/businesses/actions_packages/show"
      end

      def trigger_packages_billing_reconciliation # rubocop:todo GitHub/UseRestfulActions
        this_business.organizations.each do |organization|
          Packages::BillingStorageReconciliationJob.perform_later(user_id: organization.id)
        end

        flash[:notice] = "Successfully dispatched billing reconciliation jobs for #{this_business.organizations.count} organizations. It might take some time for results to show."
        redirect_to stafftools_actions_packages_path(this_business)
      end

      private

      memoize def shared_storage_usage
        ::Billing::SharedStorageUsage.usage_quote(this_business)
      end
      helper_method :shared_storage_usage

      memoize def purchased_prepaid_metered_usage_refills
        ::Billing::Money.new(
          ::Billing::PrepaidMeteredUsageRefill.total_active_amount_in_cents_for(owner: this_business)
        )
      end
      helper_method :purchased_prepaid_metered_usage_refills

      memoize def remaining_prepaid_metered_usage_refills
        (this_business.customer&.credit_balance || ::Billing::Money.new(0))
      end
      helper_method :remaining_prepaid_metered_usage_refills

      def show_spending
        true
      end
      helper_method :show_spending
    end
  end
end
