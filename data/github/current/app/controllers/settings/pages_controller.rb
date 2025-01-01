# typed: true
# frozen_string_literal: true

class Settings::PagesController < ApplicationController
  include Settings::ControllerMethods
  include PagesProtectedDomainsHelper

  before_action :login_required
  before_action :ensure_pages_domain_protection_enabled

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Pages,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    protected_domains = Page::ProtectedDomain.where(
      owner: current_user,
    ).includes(:owner)

    render "settings/pages/index", locals: {
      pages_protected_domains: protected_domains,
    }
  end

  private

  def ensure_pages_domain_protection_enabled
    render_404 unless pages_domain_protection_enabled?(user: current_user)
  end
end
