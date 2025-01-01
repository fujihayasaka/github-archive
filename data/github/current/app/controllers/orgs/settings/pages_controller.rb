# typed: true
# frozen_string_literal: true

class Orgs::Settings::PagesController < Orgs::Controller
  include PagesProtectedDomainsHelper

  before_action :login_required
  before_action :ensure_current_organization
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  stylesheet_bundle :settings

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    return render_404 unless pages_domain_protection_enabled?(user: current_user)

    protected_domains = Page::ProtectedDomain.where(owner: current_organization).includes(:owner)
    render "settings/organization/pages", locals: {
      pages_protected_domains: protected_domains,
    }
  end
end
