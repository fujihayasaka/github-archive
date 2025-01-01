# typed: true
# frozen_string_literal: true

class Businesses::SponsorsSettingsController < Businesses::BusinessController
  before_action :dotcom_required
  before_action :sponsors_required
  before_action :business_owner_required
  before_action :require_valid_org, only: [:update]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:show]

  def show
    render "businesses/settings/sponsors", locals: { business: this_business }
  end

  def update
    if params[:org_to_enable].present?
      organization_to_update.grant_sponsorships_access(actor: current_user)
      SponsorsPrimerMailer.sponsorship_permission_granted(
        organization: organization_to_update, enterprise: this_business
      ).deliver_later
      flash[:notice] = "Sponsorships access granted to #{org_to_update_login}."
    else
      organization_to_update.revoke_sponsorships_access(actor: current_user)
      SponsorsPrimerMailer.sponsorship_permission_revoked(
        organization: organization_to_update, enterprise: this_business
      ).deliver_later
      OrganizationSponsorshipAccessRevokedJob.perform_later(organization: organization_to_update, actor: current_user)
      flash[:notice] = "Sponsorships access removed for #{org_to_update_login}."
    end

    redirect_to settings_sponsors_enterprise_path
  end

  def org_suggestions # rubocop:todo GitHub/UseRestfulActions
    headers["Cache-Control"] = "no-cache, no-store"

    render Sponsors::Businesses::OrgAutocompleteSuggestionsComponent.new(
      business: this_business, actor: current_user, query: params[:q]
    )
  end

  private

  def org_to_update_login
    params[:org_to_enable].presence || params[:org_to_disable]
  end

  memoize def organization_to_update
    this_business.organizations.find_by_login(org_to_update_login)
  end

  def require_valid_org
    organization_parameter_error unless org_to_update_login.present? && organization_to_update.present?
  end

  def organization_parameter_error
    flash[:error] = "Could not update sponsorships policy for the given organization."
    redirect_to settings_sponsors_enterprise_path
  end
end
