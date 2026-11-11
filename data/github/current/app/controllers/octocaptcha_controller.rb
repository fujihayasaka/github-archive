# typed: true
# frozen_string_literal: true

class OctocaptchaController < ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :set_octocaptcha_csp, except: [:test]
  before_action :clear_cookies
  before_action :validate_hmac, only: [:verify_v1]

  skip_forgery_protection only: [:verify_v1]
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

    datadome_requested = params[:datadome_js_tag] == "true"

    if datadome_requested && FeatureFlag.vexi.enabled?(:datadome_js_tag_enabled, user, default: false)
      datadome_key = GitHub.datadome_js_key.presence

      if datadome_key
        datadome_script_nonce = SecureRandom.base64(16)

        # Keep CSP consistent with per-user rollout: only allow DataDome domains when we will actually load the tag.
        SecureHeaders.append_content_security_policy_directives(request, {
          script_src: ["https://js.datadome.co", "https://ct.captcha-delivery.com", "'nonce-#{datadome_script_nonce}'"],
          connect_src: ["https://api-js.datadome.co"],
          frame_src: ["https://*.captcha-delivery.com"],
          worker_src: ["blob:"],
        })

        response.headers["X-DataDome-Enabled"] = "true"
        @datadome_js_key = datadome_key
        @datadome_script_nonce = datadome_script_nonce
      else
        Rails.logger.warn("DataDome requested/enabled but GitHub.datadome_js_key is not configured")
      end
    end

    @target_origin = target_origin
    @origin_page = Octocaptcha::LAZY_OCTOCAPTCHA_PAGES.has_key?(params[:origin_page].to_s.to_sym) ? params[:origin_page] : "origin_page_unknown"
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
      if FeatureFlag.vexi.enabled?(:social_signup_email_token, default: false) && @forbidden_reason.present?
        GitHub.dogstats.increment "octocaptcha.requested", tags: tags + ["response_code:403", "reason:#{@forbidden_reason}"]
        return render plain: "403 Forbidden", status: 403
      end

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
    @forbidden_reason = nil
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

        if FeatureFlag.vexi.enabled?(:social_signup_email_token, default: false)
          allowed_data_keys = %w[email_address login]
          verified_email = verified_social_email_from_token(data["social_email_token"])

          if data["social_email_token"].present?
            if data["email_address"].present?
              GitHub.dogstats.increment "octocaptcha.data_exchange.social_email_token_with_email_injected", tags: tags
            end

            if verified_email.blank?
              GitHub.dogstats.increment "octocaptcha.data_exchange.social_email_token_invalid", tags: tags
              @forbidden_reason = :invalid_social_email_token
            end

            if verified_email.present?
              # Social signup only sends the token, not email_address directly
              # This intentionally overrides any user injected email_address
              data["email_address"] = verified_email
              GitHub.dogstats.increment "octocaptcha.data_exchange.social_email_verified", tags: tags
            end
          elsif data["email_address"].blank?
            GitHub.dogstats.increment "octocaptcha.data_exchange.social_token_and_email_missing", tags: tags
            @forbidden_reason = :missing_email_and_social_email_token
          end

          data_exchange_data.merge!(data.slice(*allowed_data_keys))
        else
          data_exchange_data.merge!(data)
        end
      rescue JSON::ParserError => e
        GitHub.dogstats.increment "octocaptcha.data_exchange.data_parsing_error", tags: tags.push("error:#{e}")
      end

      data_exchange_data.merge!(Octocaptcha.extra_data_exchange_fields(request, GitHub.context))
      data_exchange_data["HEADER_x-datadome-requestid"] = params[:datadome_request_id] if params[:datadome_request_id].present?
      data_exchange_data["HEADER_x-datadome-sessionid"] = params[:datadome_session_id] if params[:datadome_session_id].present?
      data_exchange_data["HEADER_x-datadome-isbot"] = params[:datadome_isbot] if params[:datadome_isbot].present?
      data_exchange_data["HEADER_x-datadome-ruletype"] = params[:datadome_ruletype] if params[:datadome_ruletype].present?
      data_exchange_data["HEADER_x-datadome-botname"] = params[:datadome_botname] if params[:datadome_botname].present?
      data_exchange_data["HEADER_x-datadome-captchapassed"] = params[:datadome_captchapassed] if params[:datadome_captchapassed].present?
      data_exchange_data["HEADER_x-datadome-traffic-rule-response"] = params[:datadome_traffic_rule_response] if params[:datadome_traffic_rule_response].present?
      data_exchange_data["HEADER_x-datadome-captchaurl"] = params[:datadome_captchaurl] if params[:datadome_captchaurl].present?
      data_exchange_data["HEADER_x-datadome-devicecheckpassed"] = params[:datadome_devicecheckpassed] if params[:datadome_devicecheckpassed].present?
      data_exchange_data["HEADER_x-datadome-matchedmodels"] = params[:datadome_matchedmodels] if params[:datadome_matchedmodels].present?
    end

    Octocaptcha.encode_and_encrypt_dx_payload(data_exchange_data)
  end

  def verified_social_email_from_token(token)
    return nil if token.blank?

    verifier = Rails.application.message_verifier(:octocaptcha_social_email)

    payload = verifier.verify(token, purpose: :social_signup)
    return nil unless payload.is_a?(Hash)
    return nil unless payload["flow"] == "social_signup"

    payload["email"].to_s
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
