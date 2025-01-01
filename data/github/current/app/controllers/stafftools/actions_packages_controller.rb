# typed: true
# frozen_string_literal: true

class Stafftools::ActionsPackagesController < StafftoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  include ActionView::Helpers::NumberHelper

  before_action :ensure_billing_enabled
  before_action :ensure_user_exists, only: [:show]

  def show
    render "stafftools/actions_packages/show", layout: "layouts/stafftools/organization/content"
  end

  private

  memoize def shared_storage_usage
    Billing::SharedStorageUsage.usage_quote(this_user)
  end
  helper_method :shared_storage_usage

  memoize def purchased_prepaid_metered_usage_refills
    Billing::Money.new(
      Billing::PrepaidMeteredUsageRefill.total_active_amount_in_cents_for(owner: this_user)
    )
  end
  helper_method :purchased_prepaid_metered_usage_refills

  memoize def remaining_prepaid_metered_usage_refills
    this_user.customer&.credit_balance || Billing::Money.new(0)
  end
  helper_method :remaining_prepaid_metered_usage_refills

  def show_spending
    !this_user.business.present?
  end
  helper_method :show_spending
end
