# typed: true
# frozen_string_literal: true

class Businesses::EnterpriseLicensingController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency

  before_action :business_access_required

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: %i(show)
  before_action :enable_microsoft_analytics, only: %i(show)
  before_action :add_microsoft_analytics_csp_exceptions, only: %i(show)
  layout "enterprise_funnel", only: %i(show)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Copilot,
    ApplicationRecord::Notify,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:download_active_committers]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    only: [:download_consumed_licenses]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:download_active_committers, :download_consumed_licenses], optional: true

  stylesheet_bundle :settings

  def show
    if FeatureFlag.vexi.enabled?(:update_license_usage_on_licensing_page_load, this_business, default: false)
      # Update the license usage when the page is loaded. This should improve scenarios where the license usage is not up to date
      # due to dotcom's prior run of the job having run before Licensify processed some change event.
      this_business&.update_license_usage
    end

    render "businesses/enterprise_licensing/show"
  end

  def destroy
    survey_id = params[:id]
    return redirect_to :back unless survey_id.present? && current_user.present?

    dismissal_setting_key = Licensing::FeedbackLinkComponent.dismissal_setting_key(survey_id: survey_id, business_slug: this_business&.slug)
    Billing::Kv.store.set(dismissal_setting_key, "true", expires: 1.week.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
    redirect_to :back
  end

  def download_consumed_licenses # rubocop:todo GitHub/UseRestfulActions
    send_data Business::LicenseCsvGenerator.new(this_business).generate,
      filename: "consumed_licenses.csv"
  end

  def download_active_committers # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_business.advanced_security_purchased?

    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: this_business, committer_type: :ACTIVE_COMMITTERS, sku: GitHub::Turboghas::SKU.from_param(params[:sku])),
      filename: "ghas_active_committers_#{this_business.slug}_#{Time.now.strftime("%FT%H%M")}.csv"
  end

  def download_maximum_committers # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_business.advanced_security_purchased?

    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: this_business, committer_type: :MAXIMUM_COMMITTERS, sku: GitHub::Turboghas::SKU.from_param(params[:sku])),
      filename: "ghas_maximum_committers_#{this_business.slug}_#{Time.now.strftime("%FT%H%M")}.csv"
  end
end
