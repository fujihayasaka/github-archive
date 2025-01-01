# typed: true
# frozen_string_literal: true

# Controller getting organizations Codespaces usage
# rubocop:todo GitHub/ControllersShouldHaveTests
class Orgs::BillingSettings::CodespacesUsageController < Orgs::Controller
  # rubocop:enable GitHub/ControllersShouldHaveTests
  before_action :login_required
  before_action :block_if_meuse_deprecated
  before_action :org_billing_management_only
  before_action :ensure_billing_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    org = current_organization_for_member_or_billing
    view = ::BillingSettings::ProductUsageView.new(account: org, current_user: current_user)


    show_spending = begin
      if org&.feature_flag_enabled_or_raise?(:codespaces_billing_no_surprises) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        view.spending_limit_enabled?
      else
        view.spending_limit_enabled? && !org.delegate_billing_to_business?
      end
    end

    render(Billing::Settings::Codespaces::UsageBodyComponent.new(
      account: view.account,
      show_spending: show_spending,
      spending_limit_path: view.spending_limit_path,
    ), layout: false)
  end

  private

  def ensure_billing_enabled
    render_404 unless GitHub.billing_enabled?
  end

  def block_if_meuse_deprecated
    if FeatureFlag.vexi.enabled?(:billing_deprecate_meuse_components_part_two, current_user, default: false)
      render_404
    end
  end
end
