# typed: true
# frozen_string_literal: true

class Businesses::MeteredExportsController < Businesses::BusinessController
  include BillingSettingsHelper

  before_action :ensure_billing_enabled
  before_action :business_access_required

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
    export = this_business.metered_usage_exports.find(params[:id])

    redirect_to export.generate_expiring_url
  end
end
