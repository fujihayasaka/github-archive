# typed: false
# frozen_string_literal: true

class Octocaptcha
  DEFAULT_BROWSER_LOAD_TIMEOUT = 30_000
  HIGHER_BROWSER_LOAD_TIMEOUT  = 50_000

  class UnableToLoadCaptcha < StandardError; end

  attr_reader :session, :octocaptcha_session, :octocaptcha, :skip_octocaptcha, :origin_page

  delegate :version, to: :octocaptcha
  delegate :public_key, to: :octocaptcha
  delegate :token, to: :octocaptcha_session
  delegate :value, to: :octocaptcha_session
  delegate :error, to: :octocaptcha_session
  delegate :funcaptcha_response_body, to: :octocaptcha_session
  delegate :is_more_data_exchange_enabled, to: :octocaptcha

  # Move to SpamuraiDevKit::Octocaptcha as a follow up
  SpamuraiDevKit::Octocaptcha.class_eval do
    attr_accessor :version, :public_key, :is_more_data_exchange_enabled, :skip_octocaptcha
  end

  def self.octocaptcha_service_configuration(feature_flag, key: :key1)
    ->(config) do
      config.env = Rails.env
      config.is_captcha_disabled = -> do
        return true if !GitHub.funcaptcha_enabled?
        # The following is to maintain back compatibility with the old Flipper code `FlipperFeature.find_by_name(feature_flag)&.fully_disabled?`
        return nil unless FeatureFlag.vexi.exists_or_raise?(feature_flag) # rubocop: disable GitHub/FeatureManagement/NoVexiNonStandardUsage
        FeatureFlag.vexi.fully_disabled_or_raise?(feature_flag) # rubocop: disable GitHub/FeatureManagement/NoVexiNonStandardUsage
      rescue
        nil
      end
      config.is_captcha_service_disabled = -> do
        return true if !GitHub.funcaptcha_enabled?
        # The following is to maintain back compatibility with the old Flipper code `!FlipperFeature.find_by_name(:octocaptcha)&.fully_enabled?`
        !(FeatureFlag.vexi.fully_enabled_or_raise?(:octocaptcha) || FeatureFlag.vexi.percentage_of_actors_value_or_raise(:octocaptcha) == 100.0) # rubocop: disable GitHub/FeatureManagement/NoVexiNonStandardUsage
      rescue
        nil
      end

      config.use_arkose_V4_api = -> do
        true
      end

      config.public_key, config.private_key = GitHub.funcaptcha_enabled? ? OCTOCAPTCHA_KEYS[key] : ["<fake-key>", "<fake-key>"]
      config.version = feature_flag == :octocaptcha_signup_redesign ? 2 : 1

      config.is_more_data_exchange_enabled = -> do
        FeatureFlag.vexi.enabled?("#{feature_flag}_more_data_exchange_enabled".to_sym, default: false)
      end

      config.skip_octocaptcha = ->(user) do
        # Octocaptcha won't work without a user so skip if we don't have one
        return false if user.nil?

        # Skip if the user is hammy (i.e. definitely not spammy)
        return true if user.try(:hammy?)

        # If you need to skip octocaptcha for a specific octocaptcha page add a new feature
        # flag named "#{feature_flag}_skip_octocaptcha" and enable it.
        #
        # See the possible feature flag names below where octocaptcha_service_configuration is called.
        #
        # Examples:
        #   octocaptcha_signup_redesign_skip_octocaptcha
        #   octocaptcha_enterprise_trial_form_skip_octocaptcha
        # This check comes before require_octocaptcha to allow explicit skipping even when
        # captcha is globally required (useful for testing).
        return true if FeatureFlag.vexi.enabled?("#{feature_flag}_skip_octocaptcha".to_sym, user, default: false)

        # If you need to require the octocaptcha everywhere add a new feature flag named
        # "require_octocaptcha" and enable it.
        return false if FeatureFlag.vexi.enabled?(:require_octocaptcha, default: false)

        false
      end
    end
  end

  OCTOCAPTCHA_KEYS = {
    key1: [GitHub.funcaptcha_public_key_version_2, GitHub.funcaptcha_private_key_version_2],
    key2: [GitHub.funcaptcha_public_key_2_version_2, GitHub.funcaptcha_private_key_2_version_2],
    key3: [GitHub.funcaptcha_public_key_3, GitHub.funcaptcha_private_key_3],
  }

  LAZY_OCTOCAPTCHA_PAGES = {
    github_signup: -> { SpamuraiDevKit::Octocaptcha.new("github", "signup", &(octocaptcha_service_configuration(:octocaptcha_integration))) },
    github_signup_redesign: -> { SpamuraiDevKit::Octocaptcha.new("github", "signup_redesign", &(octocaptcha_service_configuration(:octocaptcha_signup_redesign, key: :key2))) },
    github_org_create: -> { SpamuraiDevKit::Octocaptcha.new("github", "org_create", &(octocaptcha_service_configuration(:octocaptcha_org_create))) },
    github_password_reset: -> { SpamuraiDevKit::Octocaptcha.new("github", "password_reset", &(octocaptcha_service_configuration(:octocaptcha_password_reset))) },
    github_two_factor_sms_setup: -> { SpamuraiDevKit::Octocaptcha.new("github", "two_factor_sms_setup", &(octocaptcha_service_configuration(:octocaptcha_two_factor_sms_setup))) },
    github_two_factor_sms_login: -> { SpamuraiDevKit::Octocaptcha.new("github", "two_factor_sms_login", &(octocaptcha_service_configuration(:octocaptcha_two_factor_sms_login))) },
    github_report_abuse: -> { SpamuraiDevKit::Octocaptcha.new("github", "report_abuse", &(octocaptcha_service_configuration(:octocaptcha_report_abuse))) },
    github_enterprise_contact: -> { SpamuraiDevKit::Octocaptcha.new("github", "enterprise_contact", &(octocaptcha_service_configuration(:octocaptcha_enterprise_contact))) },
    github_enterprise_trial_create: -> { SpamuraiDevKit::Octocaptcha.new("github", "enterprise_trial_create", &(octocaptcha_service_configuration(:octocaptcha_enterprise_trial_create))) },
    enterprise_trial_form: -> { SpamuraiDevKit::Octocaptcha.new("enterprise", "trial_form", &(octocaptcha_service_configuration(:octocaptcha_enterprise_trial_form))) },
    enterprise_contact: -> { SpamuraiDevKit::Octocaptcha.new("enterprise", "contact", &(octocaptcha_service_configuration(:octocaptcha_enterprise_contact))) },
    support_contact_form: -> { SpamuraiDevKit::Octocaptcha.new("support", "contact_form", &(octocaptcha_service_configuration(:octocaptcha_support_contact_formt))) },
    npm_signup: -> { SpamuraiDevKit::Octocaptcha.new("npm", "signup", &(octocaptcha_service_configuration(:octocaptcha_npm_signup))) },
    npm_support: -> { SpamuraiDevKit::Octocaptcha.new("npm", "support", &(octocaptcha_service_configuration(:octocaptcha_npm_support))) },
    marketing_forms: -> { SpamuraiDevKit::Octocaptcha.new("marketing", "forms", &(octocaptcha_service_configuration(:octocaptcha_marketing_forms, key: :key3))) },
  }

  OCTOCAPTCHA_PAGES = Hash.new do |h, k|
    if LAZY_OCTOCAPTCHA_PAGES.key?(k)
      h[k] = LAZY_OCTOCAPTCHA_PAGES[k].call
    else
      LAZY_OCTOCAPTCHA_PAGES.default ||= SpamuraiDevKit::Octocaptcha.new("github", "default", &(octocaptcha_service_configuration(:octocaptcha_default)))
    end
  end


  # Factory method: Returns either Octocaptcha or Octocaptcha::Null based on context.
  # When captcha should be skipped (e.g., user is hammy, or page-specific skip flag is set),
  # returns a null object that safely no-ops all operations.
  def self.new(session, token = nil, page: :signup, origin_page: nil, user: nil)
    # Determine origin_page
    computed_origin_page = origin_page.present? ? origin_page.to_sym : "github_#{page}".to_sym

    # Check if captcha should be skipped based on user properties and feature flags
    o = OCTOCAPTCHA_PAGES[computed_origin_page]
    should_skip = o.skip_octocaptcha.call(user)

    # Return null object when captcha should be skipped
    if should_skip
      GitHub.dogstats.increment "octocaptcha.null_object_returned", tags: ["origin_page:#{computed_origin_page}"]
      return Octocaptcha::Null.new(session, origin_page: computed_origin_page)
    end

    # Create real Octocaptcha instance
    instance = allocate
    instance.send(:initialize, session, token, page: page, origin_page: origin_page, user: user)
    instance
  end

  # TODO: Remove page argument after all pages are migrated to origin_page
  def initialize(session, token = nil, page: :signup, origin_page: nil, user: nil)
    @origin_page = origin_page.present? ? origin_page.to_sym : "github_#{page}".to_sym
    o = OCTOCAPTCHA_PAGES[@origin_page]

    @octocaptcha = o
    @skip_octocaptcha = o.skip_octocaptcha.call(user)
    @octocaptcha_session = o.new_session(token: token)
    @session = session
  end

  # Puts the user into test groups for our experiment.
  # source_page        - the page the user started the signup flow from.
  def set_test_group(source_page = nil)
    return if !octocaptcha_dotcom_fully_enabled?

    # Sanitize string and remove : delimeter
    session[:source_page] = source_page.to_s.gsub(":", "") if source_page
    session[:source_page] = "unknown" if session[:source_page].blank?
  end

  def instrument_event(event_name, signup_time: nil, user: nil, email_address: nil, funcaptcha_response: nil, nux_test: nil, datadome_data_exchange: nil)
    tags = []
    tags << "validation_value:#{value}" if value
    tags << "validation_error:#{error}" if error
    tags << "signup_time:#{signup_time}" if signup_time
    tags << "source_page:#{session[:source_page]}" if session[:source_page]
    tags << "show_captcha:#{show_captcha?}"
    tags << "nux_test:#{nux_test}"
    GitHub.dogstats.increment "octocaptcha.#{event_name}", tags: tags

    payload = {
      occurred_at: Time.now,
      event_type: "octocaptcha_#{event_name}".upcase,
      session_id: session.id&.public_id,
      show_captcha: show_captcha?,
    }

    payload[:validation_value] = value.to_s if value
    payload[:validation_error] = error.to_s if error
    payload[:signup_time] = signup_time if signup_time
    payload[:source_page] = session[:source_page] if session[:source_page]
    payload[:user] = user if user
    payload[:email_address] = email_address if email_address

    event_funcaptcha_response = funcaptcha_response.presence || (response_body if value && !(response_body.class < Exception))
    if datadome_data_exchange.present?
      event_funcaptcha_response = event_funcaptcha_response.is_a?(Hash) ? event_funcaptcha_response.deep_dup : {}
      event_funcaptcha_response["datadome_data_exchange"] = datadome_data_exchange
    end

    payload[:funcaptcha_response] = event_funcaptcha_response if event_funcaptcha_response.present?
    payload[:octo_id] = session[:octo_id].presence

    GlobalInstrumenter.instrument("octocaptcha.signup", payload)
  end

  def show_captcha?
    return false if skip_octocaptcha

    octocaptcha_session.show_captcha?
  end

  def verify
    return if skip_octocaptcha

    octocaptcha_session.verify

    verify_response = octocaptcha_session.send(:response)

    data = {}
    data[:code] = verify_response.try(:code)
    data[:body] = begin
                    JSON.parse((verify_response.try(:body)).to_s)
                  rescue JSON::ParserError
                    verify_response.try(:body)
                  end
    data[:headers] = verify_response.try(:to_hash)
    data[:message] = verify_response.try(:message)
    data[:exception] = verify_response.inspect if verify_response.class < Exception
    data[:value] = value.to_s
    data[:error] = error.to_s
    data[:solved] = solved?
    data[:punished] = punished?
    data[:suggested_action] = suggested_action&.to_s

    if FeatureFlag.vexi.enabled?(:datadome_js_tag_enabled, default: false)
      datadome_data_exchange = decoded_datadome_data_exchange
      data[:datadome_data_exchange] = datadome_data_exchange if datadome_data_exchange.present?
    end

    GlobalInstrumenter.instrument "octocaptcha.log", {
      event_type: "verify_response",
      arkose_public_key: public_key,
      origin_page: origin_page,
      data: data.to_json,
    }
  end

  def decoded_datadome_data_exchange
    blob = response_body.try(:dig, "session_details", "optional", "blob")
    return if blob.blank?

    decoded_data_exchange = Octocaptcha.decode_and_decrypt_dx_payload(blob)
    return unless decoded_data_exchange.is_a?(Hash)

    decoded_data_exchange.select { |key, _| key.to_s.start_with?("HEADER_x-datadome-") }.presence
  rescue OpenSSL::Cipher::CipherError, JSON::ParserError, TypeError, ArgumentError
    nil
  end

  def solved?
    return true if skip_octocaptcha

    octocaptcha_session.solved?
  end

  sig { returns(T::Boolean) }
  def punished?
    return false if skip_octocaptcha
    return false unless octocaptcha_dotcom_fully_enabled?
    return false unless response_body.is_a? Hash

    response_body.dig("session_details", "punishable_actioned") || false
  end

  # Based on these specific fields in the response body, we suggest an action to the user based on guidance from Arkose
  sig { returns(T.nilable(Symbol)) }
  def suggested_action
    # if the user is not punished, there is no suggested action
    return nil unless punished?

    telltale_user = response_body.dig("session_details", "telltale_user")
    arkose_suggested_action = response_body.dig("email_intelligence", "email_assessment", "suggested_action")

    # if the telltale_user does not include "-email-", the user was blocked for non-email reasons and there is no suggested action
    return :blocked_no_action unless telltale_user&.include?("-email-")

    case arkose_suggested_action
    # if the suggested action is email_no_risk, we ask the user to try again later as their email is likely safe
    when "email_no_risk"
      :try_again_later
    # if the suggested action is different_email, we ask the user to try a different email
    when "different_email"
      :try_different_email
    # if the suggested action is different_domain, we ask the user to try a different email domain
    when "different_domain"
      :try_different_domain
    else
      # default suggested action is to try again later
      :try_again_later
    end
  end

  def octocaptcha_dotcom_fully_enabled?
    octocaptcha_session.show_captcha?
  end

  def response_body
    funcaptcha_response_body
  end

  def funcaptcha_session_id
    return "" if !octocaptcha_dotcom_fully_enabled?
    return "" unless response_body.is_a? Hash
    response_body.dig("session_details", "session") || response_body.dig("other", "session") || ""
  end

  def funcaptcha_response
    return {} if !octocaptcha_dotcom_fully_enabled?
    return {} unless response_body.is_a? Hash

    response_body
  end

  def funcaptcha_solved
    return if !octocaptcha_dotcom_fully_enabled?
    value == :solved_captcha
  end

  def solved_interactive_captcha?
    return if !octocaptcha_dotcom_fully_enabled?
    return unless response_body.is_a? Hash
    response_body["solved"] && !(response_body.dig("session_details", "suppressed") == true)
  end

  def self.extra_data_exchange_fields(request, github_context = {})
    ip = Hydro::IpAddr.new(github_context[:actor_ip])
    {
      "HEADER_user-agent" => safe_header_parse(github_context[:user_agent]),
      "HEADER_accept-language" => safe_header_parse(request.headers["HTTP_ACCEPT_LANGUAGE"]),
      "HEADER_origin" => safe_header_parse(request.headers["HTTP_ORIGIN"]),
      "HEADER_referer" => safe_header_parse(github_context[:referrer]),
      "HEADER_sec-fetch-site" => safe_header_parse(request.headers["HTTP_SEC_FETCH_SITE"]),
      "HEADER_sec-ch-ua" => safe_header_parse(request.headers["HTTP_SEC_CH_UA"]),
      "HEADER_sec-ch-ua-mobile" => safe_header_parse(request.headers["HTTP_SEC_CH_UA_MOBILE"]),
      "HEADER_sec-ch-ua-platform" => safe_header_parse(request.headers["HTTP_SEC_CH_UA_PLATFORM"]),
      "ip_address" => ip.to_s,
      # These are standard fields in the arkose api. For now we are just sending empty strings
      # but eventually we should send these values. e.g. sending client_id (not the real one)
      # would be useful to detect browser re-use and arkose can challenge with more difficult
      # captchas in those cases.
      "user_identifier" => "",
      "cookie_id" => "",
      "use_case" => "",
      "app" => "",
    }
  end

  def self.safe_header_parse(header)
    header&.dup&.force_encoding(Encoding::UTF_8)&.scrub!
  end

  def self.encode_and_encrypt_dx_payload(payload)
    return "" unless GitHub.funcaptcha_data_exchange_key.present?

    result = encrypt(GitHub.funcaptcha_data_exchange_key, payload.to_json)
    encode(result[:iv], result[:ciphertext], result[:tag])
  end

  def self.encrypt(key_bytes, data)
    cipher = OpenSSL::Cipher::AES256.new(:GCM).encrypt
    iv = OpenSSL::Random.random_bytes(cipher.iv_len) # 12 bytes/chars = 96 bits

    cipher.key = Base64.decode64(key_bytes) # this will convert key length into 32
    cipher.iv = iv
    cipher.auth_data = ""
    ciphertext = cipher.update(data) + cipher.final
    tag = cipher.auth_tag

    {
      iv: iv,
      ciphertext: ciphertext,
      tag: tag
    }
  end

  def self.encode(iv, ciphertext, tag)
    b64_iv = Base64.strict_encode64(iv)
    b64_ciphertext_tag = Base64.strict_encode64("#{ciphertext}#{tag}")
    # Format: <base64 encoded iv>.<base64 encoded ciphertext + tag>
    "#{b64_iv}.#{b64_ciphertext_tag}"
  end

  def self.decode_and_decrypt_dx_payload(payload)
    return "" unless GitHub.funcaptcha_data_exchange_key.present?
    return "" if payload.blank?

    decoded = decode(payload)
    decrypted_payload = decrypt(GitHub.funcaptcha_data_exchange_key, decoded[:b64_iv], decoded[:b64_ciphertext_tag])
    JSON.parse(decrypted_payload)
  end

  def self.decrypt(key_bytes, b64_iv, b64_ciphertext_tag)
    # Decode the base64 encoded iv, ciphertext, and tag
    iv = Base64.decode64(b64_iv)
    ciphertext_and_tag = Base64.decode64(b64_ciphertext_tag)
    tag_length = 16 # GCM tag is usually 16 bytes (128 bits)
    ciphertext = ciphertext_and_tag[0...-tag_length]
    tag = ciphertext_and_tag[-tag_length..]

    # Create a new AES cipher for decryption
    cipher = OpenSSL::Cipher::AES256.new(:GCM).decrypt
    cipher.key = Base64.decode64(key_bytes) # Decode the base64 encoded key
    cipher.iv = iv
    cipher.auth_tag = tag
    cipher.auth_data = ""

    # Decrypt the ciphertext
    cipher.update(ciphertext) + cipher.final
  end

  def self.decode(encoded_payload)
    return { b64_iv: nil, b64_ciphertext_tag: nil } if encoded_payload.nil?
    b64_iv, b64_ciphertext_tag = encoded_payload.split(".")
    { b64_iv: b64_iv, b64_ciphertext_tag: b64_ciphertext_tag }
  end

  # NullOctocaptcha implements the Null Object Pattern for Octocaptcha.
  # It provides safe no-op implementations of all Octocaptcha public methods.
  # This class is returned when captcha should be skipped (e.g., when the user
  # is hammy or when a page-specific skip feature flag is enabled).
  #
  # By using this pattern, we eliminate the need for defensive `if octocaptcha.show_captcha?`
  # checks throughout the codebase, making the API safer and easier to use.
  class Null
    attr_reader :session, :origin_page

    def initialize(session, origin_page: :github_signup)
      @session = session
      @origin_page = origin_page
    end

    # Captcha state methods - all return safe values indicating no captcha needed
    def show_captcha? = false
    def solved? = true
    def punished? = false
    def suggested_action = nil
    def octocaptcha_dotcom_fully_enabled? = false

    # Verification methods - all are safe no-ops
    def verify = nil
    def set_test_group(_source_page = nil) = nil

    # Event instrumentation - no-op since there's no captcha to instrument
    def instrument_event(_event_name, signup_time: nil, user: nil, email_address: nil, funcaptcha_response: nil, nux_test: nil) = nil

    # Delegated methods from octocaptcha - return safe default values
    def version = 1
    def public_key = ""

    # Delegated methods from octocaptcha_session - return safe default values
    def token = nil
    def value = nil
    def error = nil
    def funcaptcha_response_body = nil

    # Additional query methods - return safe defaults
    def response_body = nil
    def funcaptcha_session_id = ""
    def funcaptcha_response = {}
    def funcaptcha_solved = nil
    def solved_interactive_captcha? = nil

    # Feature flag check - return safe default
    def is_more_data_exchange_enabled = false

    # Reader for octocaptcha compatibility (used in tests)
    def octocaptcha = nil
    def octocaptcha_session = nil
    def skip_octocaptcha = true
  end
end
