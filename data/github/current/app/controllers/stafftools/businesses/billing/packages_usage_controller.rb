# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::PackagesUsageController < Stafftools::Businesses::BillingController
  before_action :block_if_meuse_deprecated

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render(Billing::Settings::Packages::PackagesUsageComponent.new(
      account: this_business,
      spending_limit_enabled: ::Billing::Budget.configurable?(this_business)),
      layout: false)
  end

  private

  def block_if_meuse_deprecated
    if FeatureFlag.vexi.enabled?(:billing_deprecate_meuse_components_part_two, current_user, default: false)
      render_404
    end
  end
end
