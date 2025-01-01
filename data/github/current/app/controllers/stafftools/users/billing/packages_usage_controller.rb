# typed: true
# frozen_string_literal: true

class Stafftools::Users::Billing::PackagesUsageController < Stafftools::Users::BillingController
  before_action :block_if_meuse_deprecated

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    billable_owner = this_user.billable_owner

    render(Billing::Settings::Packages::PackagesUsageComponent.new(
      account: this_user,
      spending_limit_enabled: ::Billing::Budget.configurable?(billable_owner)), layout: false)
  end

  private

  def block_if_meuse_deprecated
    if FeatureFlag.vexi.enabled?(:billing_deprecate_meuse_components_part_two, current_user, default: false)
      render_404
    end
  end
end
