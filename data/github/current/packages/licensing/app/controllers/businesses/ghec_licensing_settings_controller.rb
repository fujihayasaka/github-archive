# typed: strict
# frozen_string_literal: true

class Businesses::GhecLicensingSettingsController < Businesses::BusinessController
  before_action :feature_licensing_vss_management_required
  before_action :dotcom_required
  before_action :business_owner_required
  before_action :active_vss_bundle_required

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationHelper
  include LicensingReactHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
  only: [:show, :licensees]

  sig { void }
  def show
    render "businesses/enterprise_licensing/ghec/show", locals: {
      title: "Enterprise Cloud"
    }
  end

  sig { void }
  def licensees # rubocop:todo GitHub/UseRestfulActions
    render json: ghe_licensee_list_page_payload(
      business: this_business,
      search: params[:search],
      page: [params[:page].to_i, 1].max,
      per_page: (params[:per_page].to_i < 1 ? 30 : params[:per_page].to_i),
      vs_filter: params[:vs_filter] || "all"
    )
  end

  private

  sig { void }
  def active_vss_bundle_required
    render_404 unless this_business.has_active_vss_bundle?
  end

  sig { void }
  def feature_licensing_vss_management_required
    render_404 unless current_user.feature_enabled?(:licensing_vss_management)
  end
end
