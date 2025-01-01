# typed: strict
# frozen_string_literal: true

class Businesses::GhecLicensingSettingsController < Businesses::BusinessController
  before_action :dotcom_required
  before_action :business_owner_required
  before_action :can_view_enterprise_settings

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationHelper
  include LicensingReactHelper
  include ::Licensing::Licensify

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
  only: [:show, :licensees, :summary, :history]

  sig { void }
  def show
    if FeatureFlag.vexi.enabled?(:update_license_usage_on_licensing_page_load, this_business, default: false)
      # Update the license usage when the page is loaded. This should improve scenarios where the license usage is not up to date
      # due to dotcom's prior run of the job having run before Licensify processed some change event.
      this_business&.update_license_usage
    end

    render "businesses/enterprise_licensing/ghec/show", locals: {
      title: "Enterprise Cloud",
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

  sig { void }
  def summary # rubocop:todo GitHub/UseRestfulActions
    render json: ghe_details_summary_react_payload(
      business: this_business
    )
  end

  sig { void }
  def history # rubocop:todo GitHub/UseRestfulActions
    begin
      history_events = get_license_history(this_business.customer_id, product: LicensifyProduct::SDLC)
    rescue LicensifyRequestFailed => e
      return render json: { error: "Failed to retrieve license history", changes: [] }, status: :internal_server_error
    end

    render json: ghe_license_history_payload(history_events: history_events)
  end

  private

  sig { void }
  def can_view_enterprise_settings
    render_404 unless this_business.has_active_vss_bundle? || show_licensing_history?(business: this_business, current_user:)
  end
end
