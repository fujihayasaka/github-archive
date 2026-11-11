# typed: true
# frozen_string_literal: true

class OrganizationHooksController < ApplicationController
  before_action :login_required
  before_action :this_organization_required
  before_action :org_members_only
  before_action :org_admins_or_fgp_user_only
  before_action :ensure_trade_restrictions_allows_org_settings_access

  javascript_bundle :settings
  stylesheet_bundle :settings

  include OrganizationsHelper
  include HooksControllerMethods # All Hook related actions

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  private

  def org_admins_or_fgp_user_only
    render_404 unless current_organization && current_organization.async_can_write_org_webhooks?(current_user).sync
  end

  # Org hooks
  def current_context
    current_organization
  end
end
