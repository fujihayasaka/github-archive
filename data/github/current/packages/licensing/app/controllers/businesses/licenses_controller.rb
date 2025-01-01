# typed: strict
# frozen_string_literal: true

class Businesses::LicensesController < Businesses::BusinessController

  before_action :business_owner_required
  before_action :licensed_mode_required

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:download]

  sig { void }
  def index
    advanced_security_organizations_page = params[AdvancedSecurityEntitiesLinkRenderer::PAGE_PARAM].to_i
    advanced_security_organizations_page = 1 if advanced_security_organizations_page == 0
    advanced_security_users_page = params[AdvancedSecurityUsersLinkRenderer::PAGE_PARAM].to_i
    advanced_security_users_page = 1 if advanced_security_users_page == 0

    render "businesses/settings/license", locals: {
      params: params,
      advanced_security_organizations_page: advanced_security_organizations_page,
      advanced_security_users_page: advanced_security_users_page,
    }
  end

  sig { void }
  def download # rubocop:todo GitHub/UseRestfulActions
    info = DotcomConnection.new.license_info
    send_data JSON.generate(info), filename: "#{GitHub.host_name}.json"
  end

  sig { void }
  def manual_sync # rubocop:todo GitHub/UseRestfulActions
    UploadEnterpriseServerUserAccountsJob.perform_later
    message = "Syncing license usage. This may take a few minutes."

    redirect_to settings_license_enterprise_path(this_business), notice: message
  end

  private

  sig { void }
  def licensed_mode_required
    render_404 unless GitHub.licensed_mode?
  end
end
