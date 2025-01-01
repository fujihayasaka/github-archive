# typed: true
# frozen_string_literal: true

class Site::ContactSalesRequestsController < Site::Enterprise::BaseController
  before_action :add_csp_exceptions
  around_action :switch_locale

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:create]

  CSP_EXCEPTIONS = {
    frame_src: [GitHub.urls.octocaptcha_host_name],
  }

  def create
    return head :bad_request unless request&.xhr?

    parse_json_params
    contact_request = Site::EnterpriseContactRequest.new(contact_sales_request_params)

    if octocaptcha_solved? && contact_request.save
      analytics_event(category: "Contact Sales", action: "Success")
      lead_generation_event(email: contact_request.email, source: "Contact Sales", actor: current_user)

      contact_request.enqueue_submission_job

      render json: { ref_id: microsoft_analytics_ref_id(contact_request.email) }, status: :ok
    else
      head :bad_request
    end
  end

  private

  def contact_sales_request_params
    params
      .require(:contact_sales_request)
      .permit(
        :company,
        :job_title,
        :country,
        :email,
        :first_name,
        :last_name,
        :full_name,
        :marketing_email_opt_in,
        :phone,
        :request_details,
        :user_agent,
        :ref_cta,
        :ref_loc,
        :ref_page,
        :variant,
        :utm_source,
        :utm_medium,
        :utm_campaign,
        :utm_content,
        :utm_term
      )
      .merge(locale: I18n.locale)
      .merge(remote_ip: request&.remote_ip)
  end

  def utm_params
    contact_sales_request_params.slice(:utm_source, :utm_medium, :utm_campaign, :utm_content, :utm_term)
  end

  def octocaptcha_solved?
    octocaptcha = Octocaptcha.new(
      session,
      params["octocaptcha-token"],
      origin_page: :marketing_forms
    )
    return true unless octocaptcha.show_captcha?

    octocaptcha.verify
    octocaptcha.solved?
  end

  def lead_generation_event(email:, source:, actor:)
    GlobalInstrumenter.instrument("analytics.lead_generation", email: email, source: source, actor: actor)
  end

  def microsoft_analytics_ref_id(id)
    return unless id.present?
    return unless utm_params.present?

    Digest::SHA256.hexdigest(id)
  end
end
