# frozen_string_literal: true

class InboxController < ApplicationController
  DEVELOPMENT_ENVIRONMENT_LOGIN = "octocat"
  GITHUB_EMAIL_PATTERN = /\A(?<login>.+)@github\.com\z/

  MissingAdvisoryInboxHMACSecretError = Class.new(StandardError)

  protect_from_forgery with: :exception

  before_action :verify_advisory_inbox_hmac_secret,
    if: -> { AdvisoryDB.verify_advisory_inbox_hmac_secret? }
  before_action :require_current_user

  def search
    search_type = params[:search_type].presence || "advisory_review"
    results = case search_type
              when "advisory_review"
                AdvisoryReview.search_identifiers(params[:search_query]).page(params[:page])
              when "cve_review"
                CVEReview.search_identifiers(params[:search_query]).page(params[:page])
              end

    render locals: {
      counts: {
        cve_reviews: CVEReview.search_identifiers(params[:search_query]).count,
        advisory_reviews: AdvisoryReview.search_identifiers(params[:search_query]).count,
      },
      search_type: search_type,
      search_query: params[:search_query],
      results: results,
    }
  end

  def set_color_mode
    current_user.update!(color_mode: params.require(:mode))
    head :no_content
  end

  def feature_enabled?(feature_name)
    AdvisoryDB::Features.enabled?(feature_name, for_user_login: current_user_login)
  end

  helper_method :feature_enabled?

  private

  def current_user
    return nil if current_user_login.nil?

    @current_user ||= User.find_or_create_by!(login: current_user_login)
  end

  helper_method :current_user

  def current_user_login
    return DEVELOPMENT_ENVIRONMENT_LOGIN if Rails.env.development?

    request.headers["X-Okta-Username"]&.slice(GITHUB_EMAIL_PATTERN, :login)
  end

  def in_triage_cve_review_count
    @in_triage_cve_review_count ||= CVEReview.curation_state_in_triage.count
  end

  helper_method :in_triage_cve_review_count

  def open_cve_review_count
    @open_cve_review_count ||= CVEReview.curation_state_open.count
  end

  helper_method :open_cve_review_count

  def open_advisory_review_count
    @open_advisory_review_count ||= AdvisoryReview.curation_state_open.by_campaign(nil).count
  end

  helper_method :open_advisory_review_count

  def ready_advisory_review_count
    @ready_advisory_review_count ||= AdvisoryReview.curation_state_ready.by_campaign(nil).count
  end

  helper_method :ready_advisory_review_count

  def verify_advisory_inbox_hmac_secret
    if AdvisoryDB.advisory_inbox_hmac_secret.blank?
      raise MissingAdvisoryInboxHMACSecretError, "Missing advisory inbox HMAC secret"
    end

    timestamp = request.headers["X-ONG-HMAC-Timestamp"]
    username = request.headers["X-Okta-Username"]
    raw_token = "#{username}|#{request.path}|#{timestamp}"
    expected_token = OpenSSL::HMAC.hexdigest("sha256", AdvisoryDB.advisory_inbox_hmac_secret, raw_token)

    return if request.headers["X-ONG-HMAC-Token"] == expected_token

    render plain: "Invalid Okta network gateway HMAC token", status: :unauthorized
  end

  def require_current_user
    return if current_user

    render plain: "Invalid Okta username", status: :forbidden
  end
end
