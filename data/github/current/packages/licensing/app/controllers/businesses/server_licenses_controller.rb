# typed: true
# frozen_string_literal: true

class Businesses::ServerLicensesController < Businesses::BusinessController
  before_action :business_owner_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    license_file_data = GitHub::EnterpriseWeb::License.download(this_business.enterprise_web_business_id, params[:id])
    instrument(params[:id])
    send_data license_file_data, filename: "github-enterprise-#{params[:id]}.ghl"
  rescue Faraday::Error
    head :not_found
  end

  private

  def instrument(license_id)
    GitHub.instrument "business.enterprise_server_license_download",
      user: current_user,
      license_id: license_id,
      business: this_business
  end
end
