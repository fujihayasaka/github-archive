# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::CodespacesUsageController < Stafftools::Businesses::BillingController

  before_action :block_if_meuse_deprecated

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    render(Billing::Settings::Codespaces::UsageBodyComponent.new(
      account: this_business,
      show_spending: true,
    ), layout: false)
  end

  private

  def block_if_meuse_deprecated
    if FeatureFlag.vexi.enabled?(:billing_deprecate_meuse_components_part_two, current_user, default: false)
      render_404
    end
  end
end
