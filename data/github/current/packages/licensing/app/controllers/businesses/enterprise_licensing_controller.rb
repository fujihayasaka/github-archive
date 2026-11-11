# typed: true
# frozen_string_literal: true

class Businesses::EnterpriseLicensingController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include Licensing::GeoComplianceHelper

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
    if request.path_parameters[:legacy_enterprise_licensing]
      redirect_to enterprise_licensing_path(this_business) and return
    end

    # Update the license usage when the page is loaded. This should improve scenarios where the license usage is not up to date
    # due to dotcom's prior run of the job having run before Licensify processed some change event.
    this_business&.update_license_usage

    render "businesses/enterprise_licensing/show"
  end

  def cancel_licensing_model_transition # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_business.customer.licensing_model_transitions.scheduled.any?

    if this_business.customer.licensing_model_transitions.scheduled.first.cancelled!
      flash[:notice] = "Your metered billing transition has been cancelled."
    else
      flash[:alert] = "Unable to cancel your metered billing transition. Please try again later."
    end

    redirect_to :back
  end

  def dismiss_metered_licensing_discovery_banner # rubocop:todo GitHub/UseRestfulActions
    Businesses::MeteredLicensingDiscoveryBannerComponent.new(
      business: this_business,
      current_user: current_user,
    ).dismiss_banner

    redirect_to :back
  end

  def download_consumed_licenses # rubocop:todo GitHub/UseRestfulActions
    send_data Business::LicenseCsvGenerator.new(this_business).generate,
      filename: "consumed_licenses.csv"
  end

  def download_active_committers # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_business.advanced_security_purchased?

    render_committers_csv(entity: this_business, committer_type: :ACTIVE_COMMITTERS, filename: "ghas_active_committers_#{this_business.slug}_#{Time.now.strftime("%FT%H%M")}.csv")
  end

  def download_maximum_committers # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_business.advanced_security_purchased?

    render_committers_csv(entity: this_business, committer_type: :MAXIMUM_COMMITTERS, filename: "ghas_maximum_committers_#{this_business.slug}_#{Time.now.strftime("%FT%H%M")}.csv")
  end

  private

  def render_committers_csv(entity:, committer_type:, filename:)
    sku = GitHub::Turboghas::SKU.from_param(params[:sku])
    source = Business::AdvancedSecurityCommittersGenerator.committers_source(entity, committer_type)

    started_at = GitHub::Dogstats.monotonic_time
    send_data Business::AdvancedSecurityCommittersGenerator.generate_csv(entity: entity, committer_type: committer_type, sku: sku),
      filename: filename
    log_committers_export(
      entity: entity,
      committer_type: committer_type,
      sku: sku,
      source: source,
      mode: "legacy",
      setup_latency_ms: GitHub::Dogstats.duration(started_at),
    )
  end

  def log_committers_export(entity:, committer_type:, sku:, source:, mode:, setup_latency_ms:)
    return unless entity.is_a?(Business)

    GitHub.logger.info(
      "GHAS committers CSV request",
      "code.namespace" => "Businesses::EnterpriseLicensingController",
      "code.function" => "render_committers_csv",
      "gh.business.id" => entity.id,
      "gh.business.slug" => entity.slug,
      "gh.customer.id" => entity.customer_id,
      "gh.advanced_security.committers.mode" => mode,
      "gh.advanced_security.committers.source" => source,
      "gh.advanced_security.committers.type" => committer_type.to_s.downcase,
      "gh.advanced_security.committers.sku" => sku.to_param,
      "gh.advanced_security.committers.setup_latency_ms" => setup_latency_ms,
      "gh.http.version" => request.env["SERVER_PROTOCOL"],
    )
  end
end
