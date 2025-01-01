# typed: true
# frozen_string_literal: true

class Site::Enterprise::ContactRequestsController < Site::Enterprise::BaseController
  include ReactHelper

  before_action :add_csp_exceptions
  around_action :switch_locale

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:create]

  CSP_EXCEPTIONS = {
    frame_src: [GitHub.urls.octocaptcha_host_name],
  }

  javascript_bundle "marketing-form-validator"
  javascript_bundle "signup"
  javascript_bundle "marketing-signup"
  stylesheet_bundle "enterprise-contact"

  def index
    contact_request = Site::EnterpriseContactRequest.new
    octocaptcha = Octocaptcha.new(session, page: :enterprise_contact)

    return Site::LandingPagesController.dispatch(:show, request, response) if feature_enabled_globally_or_for_current_user?(:contentful_lp_contact_sales_form)

    render "site/enterprise/contact_requests/index", locals: {
      contact_request: contact_request,
      octocaptcha: octocaptcha,
    }
  end

  def create
    parse_json_params if request&.xhr? && is_contact_sales_lp

    contact_request = Site::EnterpriseContactRequest.new(enterprise_contact_request_params)

    if octocaptcha_solved? && contact_request.save
      analytics_event(category: "Contact Sales", action: "Success")
      lead_generation_event(email: contact_request.email, source: "Contact Sales", actor: current_user)

      contact_request.enqueue_submission_job

      if request&.xhr? && is_contact_sales_lp
        head :no_content
      else
        redirect_to thanks_enterprise_contact_requests_path(ref_id: microsoft_analytics_ref_id(contact_request.email), **utm_params)
      end
    else
      if contact_request.errors.include?(:email)
        GitHub.dogstats.increment("site.enterprise.contact_page.invalid_email")

        flash.now[:error] = "Please enter a valid work email address."
      end

      if request&.xhr? && is_contact_sales_lp
        render json: { message: "Bad Request" }, status: 400
      else
        octocaptcha = Octocaptcha.new(session, page: :enterprise_contact)

        render "site/enterprise/contact_requests/index", locals: {
          contact_request: contact_request,
          octocaptcha: octocaptcha,
        }
      end
    end
  end

  private

  def is_contact_sales_lp
    feature_enabled_globally_or_for_current_user?(:contentful_lp_contact_sales_form)
  end

  def enterprise_contact_request_params
    params
      .require(:site_enterprise_contact_request)
      .permit(
        :company,
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
    enterprise_contact_request_params.slice(:utm_source, :utm_medium, :utm_campaign, :utm_content, :utm_term)
  end

  def octocaptcha_solved?
    octocaptcha = Octocaptcha.new(
      session,
      params["octocaptcha-token"],
      page: :enterprise_contact
    )
    return true unless octocaptcha.show_captcha?

    octocaptcha.verify

    if octocaptcha.solved?
      true
    else
      flash[:error] = "Unable to verify your captcha response. Please visit " \
        "#{octocaptcha_help_url} for troubleshooting information"

      false
    end
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
