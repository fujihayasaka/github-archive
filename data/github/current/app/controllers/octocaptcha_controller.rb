# typed: true
# frozen_string_literal: true

class OctocaptchaController < ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :set_octocaptcha_csp, except: [:test]
  before_action :clear_cookies
  before_action :validate_hmac, only: [:verify_v1]

  skip_before_action :verify_authenticity_token, only: [:verify_v1]
  skip_after_action :block_non_xhr_json_responses, only: [:verify_v1]
  # octocaptcha is always public
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  layout false

  def index
    # Octocaptchas can be served to logged out users too. In order to
    # experiment with this, we will be "dark shipping" this to a
    # percentage of users. The only way to do this is to use the
    # ghost user to check if the feature is enabled for the request.
    # That way we can serve the captcha to a percentage of our logged out
    # users.
    user = current_user || User.ghost

    @target_origin = target_origin
    @origin_page = Octocaptcha::OCTOCAPTCHA_PAGES.has_key?(params[:origin_page].to_s.to_sym) ? params[:origin_page] : "origin_page_unknown"
    @responsive = params[:responsive] == "true"
    @nojs = params[:nojs] == "true"
    @require_ack = params[:require_ack] == "true"
    @style_theme = params[:style_theme] || "default"
    # Set the language for the captcha widget. This prioritizes the locale param passed from the React Octocaptcha component (via iframe URL),
    # then falls back to the current Rails locale (I18n.locale), and finally defaults to 'en-US' if neither is present.
    @language = params[:locale].presence || I18n.locale.to_s || "en-US"

    if params[:version].to_i == 2
      @public_key = GitHub.funcaptcha_public_key_2
      @public_key = GitHub.funcaptcha_public_key_2_demo if params[:captcha_demo] == "true"
      @version = 2
    else
      @public_key = GitHub.funcaptcha_public_key
      @public_key = GitHub.funcaptcha_public_key_demo if params[:captcha_demo] == "true"
      @version = 1
    end

    set_config_vars
    tags = ["target_origin:#{@target_origin}", "origin_page:#{@origin_page}"]

    if FeatureFlag.vexi.enabled_or_raise?(:octocaptcha, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      GitHub.dogstats.increment "octocaptcha.requested", tags: tags + ["response_code:200"]
      render "octocaptcha/index"
    else
      GitHub.dogstats.increment "octocaptcha.requested", tags: tags + ["response_code:404"]
      render plain: "404 Not Found", status: 404
    end
  end

  def verify_v1 # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment "octocaptcha.verify_token", tags: ["origin_page:#{params["page"]}"]
    request_body = JSON.parse(request.body.read)
    octocaptcha = Octocaptcha.new(session, request_body["octocaptcha-token"], origin_page: request_body["page"])
    octocaptcha.verify
    render json: { solved: octocaptcha.solved? }
  end

  def test # rubocop:todo GitHub/UseRestfulActions
    render "octocaptcha/test"
  end

  def octocaptcha_test # rubocop:todo GitHub/UseRestfulActions
    if FeatureFlag.vexi.enabled_or_raise?(:octocaptcha) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      GitHub.dogstats.increment "octocaptcha.enabled_check", tags: ["response_code:200"]
      render plain: "ok", status: 200
    else
      GitHub.dogstats.increment "octocaptcha.enabled_check", tags: ["response_code:404"]
      render plain: "404 Not Found", status: 404
    end
  end

  def not_found # rubocop:todo GitHub/UseRestfulActions
    render plain: "404 Not Found", status: 404
  end

  private

  def validate_hmac
    timestamp = request.headers["HTTP_X_AUTHORIZATION_TIME"]
    authorization = request.headers["Authorization"]

    return head 403 if timestamp.nil? || timestamp.empty?
    return head 403 if authorization.nil? || authorization.empty?
    time = DateTime.strptime(timestamp, "%s")
    return head 403 if time < 30.seconds.ago

    key = "#{request.fullpath},#{timestamp}"

    is_valid = ActiveSupport::SecurityUtils::secure_compare(
      OpenSSL::HMAC.hexdigest("SHA256", GitHub.octocaptcha_api_hmac_secret, key),
      authorization,
    )

    is_valid ||= ActiveSupport::SecurityUtils::secure_compare(
      OpenSSL::HMAC.hexdigest("SHA256", GitHub.octocaptcha_api_hmac_secret_v2, key),
      authorization,
    )

    head 403 if !is_valid
  end

  def target_origin
    # Allow origin to be from review-lab and staging environments
    origin = params[:origin].to_s
    if Rails.env.development?
      return origin.presence || request.base_url
    end
    return origin if origin.end_with?(".github.com")
    return origin if origin.end_with?(".githubapp.com")
    return origin if origin.end_with?(".npmjs.com")
    return origin if origin.end_with?(".npm.red")
    return origin if origin == "https://githubuniverse.com" || origin.ends_with?(".githubuniverse.com")

    GitHub.url
  end

  def clear_cookies
    cookies.clear
  end

  def set_config_vars
    o = Octocaptcha.new(session, nil, origin_page: @origin_page)
    @version = o.version
    @public_key = o.public_key
    @data_exchange_payload = generate_data_exchange_payload(o.is_more_data_exchange_enabled.call)
  end

  def generate_data_exchange_payload(more_data_exchange_enabled)
    return "" unless GitHub.funcaptcha_data_exchange_key.present?

    timestamp = Timestamp.milliseconds_since_epoch # in milliseconds
    data_exchange_data = {
      "timestamp" => timestamp,
      "api_source_validation" => {
        "token" => SecureRandom.uuid,
        "timestamp" => timestamp
      }
    }

    if more_data_exchange_enabled
      tags = ["target_origin:#{@target_origin}", "origin_page:#{@origin_page}"]
      begin
        data = params[:data] if params[:data].is_a?(Hash)
        data = JSON.parse(params[:data]) if params[:data].is_a?(String)
        data = {} if !data.is_a?(Hash)
        data_exchange_data.merge!(data)
      rescue JSON::ParserError => e
        GitHub.dogstats.increment "octocaptcha.data_exchange.data_parsing_error", tags: tags.push("error:#{e}")
      end

      data_exchange_data.merge!(Octocaptcha.extra_data_exchange_fields(request, GitHub.context))
    end

    Octocaptcha.encode_and_encrypt_dx_payload(data_exchange_data)
  end
end
