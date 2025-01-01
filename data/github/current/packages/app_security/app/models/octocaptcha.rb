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
        FlipperFeature.find_by_name(feature_flag)&.fully_disabled?
      end
      config.is_captcha_service_disabled = -> do
        return true if !GitHub.funcaptcha_enabled?
        !FlipperFeature.find_by_name(:octocaptcha)&.fully_enabled?
      end

      config.use_arkose_V4_api = -> do
        true
      end

      config.public_key, config.private_key = GitHub.funcaptcha_enabled? ? OCTOCAPTCHA_KEYS[key] : ["<fake-key>", "<fake-key>"]
      config.version = feature_flag == :octocaptcha_signup_redesign ? 2 : 1

      config.is_more_data_exchange_enabled = -> do
        GitHub.flipper["#{feature_flag}_more_data_exchange_enabled".to_sym].enabled?
      end

      config.skip_octocaptcha = ->(user) do
        # Octocaptcha won't work without a user so skip if we don't have one
        return false if user.nil?

        # Skip if the user is hammy (i.e. definitely not spammy)
        return true if user.try(:hammy?)

        # If you need to require the octocaptcha everywhere add a new feature flag named
        # "require_octocaptcha" and enable it.
        return false if GitHub.flipper[:require_octocaptcha].enabled?

        # If you need to skip octocaptcha for a specific octocaptcha page add a new feature
        # flag named "#{feature_flag}_skip_octocaptcha" and enable it.
        #
        # See the possible feature flag names below where octocaptcha_service_configuration is called.
        #
        # Examples:
        #   octocaptcha_signup_redesign_skip_octocaptcha
        #   octocaptcha_enterprise_trial_form_skip_octocaptcha
        return true if GitHub.flipper["#{feature_flag}_skip_octocaptcha".to_sym].enabled?(user)

        false
      end
    end
  end

  OCTOCAPTCHA_KEYS = {
    key1: [GitHub.funcaptcha_public_key_version_2, GitHub.funcaptcha_private_key_version_2],
    key2: [GitHub.funcaptcha_public_key_2_version_2, GitHub.funcaptcha_private_key_2_version_2],
    key3: [GitHub.funcaptcha_public_key_3, GitHub.funcaptcha_private_key_3],
  }

  OCTOCAPTCHA_PAGES = {
    github_signup: SpamuraiDevKit::Octocaptcha.new("github", "signup", &(octocaptcha_service_configuration(:octocaptcha_integration))),
    github_signup_redesign: SpamuraiDevKit::Octocaptcha.new("github", "signup_redesign", &(octocaptcha_service_configuration(:octocaptcha_signup_redesign, key: :key2))),
    github_org_create: SpamuraiDevKit::Octocaptcha.new("github", "org_create", &(octocaptcha_service_configuration(:octocaptcha_org_create))),
    github_password_reset: SpamuraiDevKit::Octocaptcha.new("github", "password_reset", &(octocaptcha_service_configuration(:octocaptcha_password_reset))),
    github_two_factor_sms_setup: SpamuraiDevKit::Octocaptcha.new("github", "two_factor_sms_setup", &(octocaptcha_service_configuration(:octocaptcha_two_factor_sms_setup))),
    github_two_factor_sms_login: SpamuraiDevKit::Octocaptcha.new("github", "two_factor_sms_login", &(octocaptcha_service_configuration(:octocaptcha_two_factor_sms_login))),
    github_report_abuse: SpamuraiDevKit::Octocaptcha.new("github", "report_abuse", &(octocaptcha_service_configuration(:octocaptcha_report_abuse))),
    github_enterprise_contact: SpamuraiDevKit::Octocaptcha.new("github", "enterprise_contact", &(octocaptcha_service_configuration(:octocaptcha_enterprise_contact))),
    github_enterprise_trial_create: SpamuraiDevKit::Octocaptcha.new("github", "enterprise_trial_create", &(octocaptcha_service_configuration(:octocaptcha_enterprise_trial_create))),
    enterprise_trial_form: SpamuraiDevKit::Octocaptcha.new("enterprise", "trial_form", &(octocaptcha_service_configuration(:octocaptcha_enterprise_trial_form))),
    enterprise_contact: SpamuraiDevKit::Octocaptcha.new("enterprise", "contact", &(octocaptcha_service_configuration(:octocaptcha_enterprise_contact))),
    support_contact_form: SpamuraiDevKit::Octocaptcha.new("support", "contact_form", &(octocaptcha_service_configuration(:octocaptcha_support_contact_formt))),
    npm_signup: SpamuraiDevKit::Octocaptcha.new("npm", "signup", &(octocaptcha_service_configuration(:octocaptcha_npm_signup))),
    npm_support: SpamuraiDevKit::Octocaptcha.new("npm", "support", &(octocaptcha_service_configuration(:octocaptcha_npm_support))),
    marketing_forms: SpamuraiDevKit::Octocaptcha.new("marketing", "forms", &(octocaptcha_service_configuration(:octocaptcha_marketing_forms, key: :key3))),
  }

  OCTOCAPTCHA_PAGES.default = SpamuraiDevKit::Octocaptcha.new("github", "default", &(octocaptcha_service_configuration(:octocaptcha_default)))

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

  def instrument_event(event_name, signup_time: nil, user: nil, email_address: nil, funcaptcha_response: nil)
    tags = []
    tags << "validation_value:#{value}" if value
    tags << "validation_error:#{error}" if error
    tags << "signup_time:#{signup_time}" if signup_time
    tags << "source_page:#{session[:source_page]}" if session[:source_page]
    tags << "show_captcha:#{show_captcha?}"
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
    payload[:funcaptcha_response] = funcaptcha_response.present? ? funcaptcha_response : (response_body if value && !(response_body.class < Exception))

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

    GlobalInstrumenter.instrument "octocaptcha.log", {
      event_type: "verify_response",
      arkose_public_key: public_key,
      origin_page: origin_page,
      data: data.to_json,
    }
  end

  def solved?
    return true if skip_octocaptcha

    octocaptcha_session.solved?
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
end
