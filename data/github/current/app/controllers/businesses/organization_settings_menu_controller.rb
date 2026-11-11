# typed: true
# frozen_string_literal: true

class Businesses::OrganizationSettingsMenuController < Businesses::BusinessController
  include BusinessesHelper

  before_action :login_required
  before_action :destroy_permission_required
  before_action :organization_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: %i(show)

  def show
    respond_to do |format|
      format.html do
        render Businesses::Organizations::SettingsMenuComponent.new(
          business: this_business,
          organization: organization,
        ), layout: false
      end
    end
  end

  private

  memoize def organization
    this_business.organizations.find_by(login: params[:organization])
  end

  def organization_required
    render_404 unless organization.present?
  end

  def destroy_permission_required
    render_404 unless Authz.domain.check_allowed(current_user, :remove_enterprise_organizations, this_business)
  end
end
