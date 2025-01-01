# typed: true
# frozen_string_literal: true

class U2fRegistrationsController < ApplicationController
  include WebauthnHelper
  include WebauthnHelper::ControllerMethods
  include GitHubMobileAuthHelper

  # U2fRegistrationsController does not require conditional access checks
  # because it *doesn't* access protected organization resources.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :ensure_security_key_enabled, except: [:trusted_facets, :login_fragment]
  before_action :login_required,              except: [:trusted_facets, :login_fragment]
  before_action :filter_enterprise_managed_users, except: [:login_fragment]
  before_action :sudo_filter,       except: [:trusted_facets, :login_fragment]
  skip_after_action :block_non_xhr_json_responses, only: :trusted_facets

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:trusted_facets]

  depends_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::Ballast, ApplicationRecord::Authnd,
    ApplicationRecord::Collab, # feature preview
    ApplicationRecord::IamAbilities,
    only: [:login_fragment]

  # nicknames that are not descriptive about the passkey to be stored.
  # stating where the passkey is used (GitHub) or what is is (passkey) is not great, we want to push people to be descriptive.
  # good things are identifiers of device and/or platform being used.
  UNINFORMATIVE_NICKNAMES = [
    "1", "1234", "2", "a", "git", "github", "githubpass", "gitpass", "key", "main", "me", "pass", "passkey", "pass key", "personal", "test",
    "githubkey", "github-key", "github_key", "github key",
    "githubpasskey", "github-passkey", "github_passkey", "github passkey", "github pass key",
    "githubpersonal", "github-personal", "github_personal", "github personal",
    "personalgithub", "personal-github", "personal_github", "personal github"]

  def create
    create_registration(webauthn_reason: :security_key_registration)
  end

  def edit
    # must be an XHR request
    return render_404 unless request.xhr?

    id = params[:id]
    submitted = params[:u2f_registration] || {}
    nickname = submitted[:nickname].to_s.strip

    error_message = nil
    if id.blank? || nickname.blank?
      error_message = "You must provide a nickname"
    end

    if nickname.length > 100
      error_message = "The nickname is too long"
    end

    # the nickname column currently does not support utfmb4 characters (any emojis or other 4-byte characters)
    if !GitHub::UTF8.valid_unicode3?(nickname)
      error_message = "The nickname contains invalid characters"
    end

    if UNINFORMATIVE_NICKNAMES.include?(nickname.downcase)
      error_message = "The nickname is not allowed, consider something uniquely identifiable, like the name of your password manager or account provider"
    end

    if error_message.blank?
      nickname_available = current_user.u2f_registrations.where(nickname: nickname).where.not(id: id).empty?
      if nickname_available
        registration = current_user.u2f_registrations.find(id)
        registration.update!(nickname: nickname)
      else
        error_message = "You already have a device called #{nickname}"
      end
    end

    respond_to do |format|
      format.json do
        if error_message.blank?
          render json: { nickname: nickname }, status: :ok
        else
          render json: { error: error_message }, status: :unprocessable_entity
        end
      end
    end
  end

  def trusted_device_create # rubocop:todo GitHub/UseRestfulActions
    return redirect_back(fallback_location: home_path) unless current_user.passkeys_enabled?
    convert_for = current_user.u2f_registrations.security_keys.find_by_id(session.delete(:security_key_to_upgrade))
    create_registration(convert_for: convert_for, webauthn_reason: convert_for ? :trusted_device_conversion : :trusted_device_registration)
  end

  def create_registration(convert_for: nil, webauthn_reason:) # rubocop:todo GitHub/UseRestfulActions
    case webauthn_reason
    when :security_key_registration
      for_passkey = false
    when :trusted_device_registration,
         :trusted_device_conversion
      for_passkey = true
    else
      # This means that our source code is inconsistent.
      track_failure(parsed_useragent, webauthn_reason, "invalid_webauthn_reason:#{webauthn_reason}")
      raise "Invalid webauthn sign request reason"
    end

    register_response_hash = JSON.parse(params[:response])

    attestation_object = Base64.urlsafe_decode64(register_response_hash["response"]["attestationObject"])
    client_data_json = Base64.urlsafe_decode64(register_response_hash["response"]["clientDataJSON"])

    # Create and verify the registration response object.
    register_response = WebAuthn::AuthenticatorAttestationResponse.new(
      client_data_json: client_data_json,
      attestation_object: attestation_object,
    )

    # Error string are shown to the user, so we use more general language
    # similar to our the client-side strings in `manage_two_factor.html.erb`.
    origin = Addressable::URI.new(scheme: request.scheme, host: request.host).to_s
    unless GitHub.webauthn_allowed_origin?(origin)
      track_failure(parsed_useragent, webauthn_reason, "invalid_hostname")
      render(status: 422, json: register_response_hash(webauthn_reason: webauthn_reason, error: "Something went really wrong."))
      return
    end

    webauthn_user_handle_base64 = session.delete(:webauthn_user_handle)
    if webauthn_user_handle_base64.nil?
      track_failure(parsed_useragent, webauthn_reason, "missing_user_handle")
      render(status: 422, json: register_response_hash(webauthn_reason: webauthn_reason, error: "Something went wrong. Please try again."))
      return
    end

    webauthn_user_handle = Base64.strict_decode64(webauthn_user_handle_base64)
    handle_record = WebauthnUserHandle.find_by(user_id: current_user.id)
    if handle_record.nil?
      if !WebauthnUserHandle.new(user_id: current_user.id, webauthn_user_handle: webauthn_user_handle).save
        # Unable to persist the user handle (e.g. transient error or race condition).
        track_failure(parsed_useragent, webauthn_reason, "error_persisting_user_handle")
        render(status: 422, json: register_response_hash(webauthn_reason: webauthn_reason, error: "Something went wrong. Please try again."))
        return
      end
    elsif handle_record.webauthn_user_handle != webauthn_user_handle
      # We've had a race condition and used the wrong handle for this registration.
      track_failure(parsed_useragent, webauthn_reason, "wrong_user_handle")
      render(status: 422, json: register_response_hash(webauthn_reason: webauthn_reason, error: "Something went wrong. Please try again."))
      return
    end

    webauthn_register_challenge, err = webauthn_register_challenge_from_request(current_user)
    if webauthn_register_challenge.nil?
      track_failure(parsed_useragent, webauthn_reason, err)
      render(status: 422, json: register_response_hash(webauthn_reason: webauthn_reason, error: "Something went wrong. Please try again."))
      return
    end

    origin = Addressable::URI.new(scheme: request.scheme, host: request.host).to_s

    begin
      unless register_response.valid?(Base64.urlsafe_decode64(webauthn_register_challenge), origin, rp_id: GitHub.webauthn_rp_id)
        # The client replied with an invalid registration attempt. This
        # shouldn't happen in normal browsers.

        track_failure(parsed_useragent, webauthn_reason, "error_decoding_challenge")
        render(status: 422, json: register_response_hash(webauthn_reason: webauthn_reason, error: "This device cannot be registered."))
        return
      end
    rescue IOError => e
      # We encountered an error validating the webauthn registration attempt
      # See https://github.com/github/authentication/issues/1235
      GitHub.logger.error({
        exception: e,
        exception_stacktrace: T.must(e.backtrace).join("\n"),
        "gh.catalog_service": "github/account_login",
        "gh.webauthn.response.size": attestation_object.length,
        "gh.webauthn.response.type": register_response_hash["type"],
        "gh.webauthn.client.type": client_data_json["type"],
        "gh.webauthn.client.origin": client_data_json["origin"],
        "gh.webauthn.client.cross_origin": client_data_json["crossOrigin"],
        "gh.webauthn.client.challenge_size": client_data_json["challenge"]&.length
      })

      track_failure(parsed_useragent, webauthn_reason, "io_error")
      render(status: 422, json: register_response_hash(webauthn_reason: webauthn_reason, error: "This device cannot be registered."))
      return
    end

    user_verifying = register_response.authenticator_data.user_verified?
    # Note:
    # - This value is not signed by the response. We trust that the value from the browser hasn't been tampered with.
    # The platform_authenticator value for all security key registrations was recorded as `false` up until Sep 2022 regardless of actual support.
    # Since then, we've started updating the platform_authenticator value during auth
    platform_authenticator = register_response_hash.dig("authenticator_attachment") == "platform"
    # Note: we started recording the `.credProps.rk` value in the DB in Nov. 2020, when Chrome 88 first added support
    # on some platforms. We started tracking a boolean-only value, where a missing `.credProps.rk` value was recorded
    # as if it was `.credProps.rk == false`. As of Feb. 2023, some browsers still don't have support, but we are now
    # tracking a missing `.credProps.rk` value as `nil`, and updating the resident_key value during auth
    #
    # Unfortunately, the spec may be ambiguous: https://w3c.github.io/webauthn/#sctn-authenticator-credential-properties-extension
    # It's unclear what is passed to `requireResidentKey` to `authenticatorMakeCredential` in the case of
    # `"residentKey`: "preferred"` (which we were using until Feb. 2023)
    #
    # It seems that:
    #
    # - `true` is is a true positive (a discoverable credential was created).
    # - `false` might be a false negative (depending on implementation details, bugs, and interpretations of the
    #   spec), but we're not sure if we'll see any such values without JavaScript tampering. Most browsers leave out
    #   the `.credProps.rk` value in situations where it would be `false` (usually because they haven't implemented
    #   it).
    # - `nil` will include a lot of registrations that are discoverable credentials, as well as lot of registrations
    #   that are not.
    resident_key = register_response_hash.dig("clientExtensionResults", "credProps", "rk")
    # We want to reject only `"rk": "false"` for passkey registrations, so we check for the other cases.
    resident_key_true_or_nil = resident_key || resident_key.nil?
    transports = register_response_hash.dig("response", "transports")
    nickname = generate_nickname(register_response_hash, for_passkey, convert_for, parsed_useragent)
    useragent_nickname = AuthenticatedDevice.generated_display_name(parsed_useragent)
    key_handle = Base64.urlsafe_encode64(register_response.authenticator_data.credential.id, padding: false)

    log_data = {
      "credential.key_handle": key_handle,
      "credential.is_passkey": for_passkey && user_verifying,
      "credential.backup_eligibility": register_response.authenticator_data.flags.backup_eligibility,
      "credential.backup_state": register_response.authenticator_data.flags.backup_state,
      "credential.resident_key": resident_key,
      "credential.user_verifying": user_verifying,
      "credential.authenticator_type": platform_authenticator ? "platform" : "cross-platform",
      "credential.aaguid": register_response.authenticator_data.attested_credential_data.aaguid
    }

    U2fRegistration.log_result("webauthn_create_registration_attempt", self.class.name, webauthn_reason, true, nil, nil, log_data)
    discoverable = resident_key_true_or_nil
    is_passkey = for_passkey && user_verifying && discoverable
    if for_passkey && !is_passkey
      # The authenticator did not meet the requirements for a passkey.
      # This means either something tampered with the JS, or the browser
      # returned an authenticator response that did not satisfy the request.
      track_failure(parsed_useragent, webauthn_reason, "missing_passkey_requirements")
      render(status: 422, json: register_response_hash(webauthn_reason: webauthn_reason, error: "This cannot be used as a passkey."))
      return
    end
    u2f_registration = T.let(nil, T.nilable(U2fRegistration))
    destroyed = T.let(false, T::Boolean)

    U2fRegistration.transaction do
      # Create the registration
      u2f_registration = current_user.u2f_registrations.create(
        key_handle: key_handle,
        public_key: Base64.strict_encode64(register_response.authenticator_data.credential.public_key.to_str),
        counter: register_response.authenticator_data.sign_count,
        nickname: nickname,
        webauthn_attestation: attestation_object,
        is_webauthn_registration: true,
        user_verifying: user_verifying,
        platform_authenticator: platform_authenticator,
        resident_key: resident_key,
        page_view: params[:page_view],
        transports: transports,
        backup_eligibility: register_response.authenticator_data.flags.backup_eligibility,
        backup_state: register_response.authenticator_data.flags.backup_state,
        is_passkey_registration: is_passkey,
        last_used_at: Time.now.utc,
      )

      destroyed = convert_for.destroy if !!convert_for
    end

    if u2f_registration.nil? || (!destroyed && !!convert_for)
      track_failure(parsed_useragent, webauthn_reason, "passkey_conversion_failure")
      render status: 422, json: register_response_hash(webauthn_reason: webauthn_reason, error: "Unable to upgrade security key")
    elsif u2f_registration.new_record?
      error = u2f_registration.errors.full_messages.to_sentence
      track_failure(parsed_useragent, webauthn_reason, "u2f_record_error")
      render(status: 422, json: register_response_hash(webauthn_reason: webauthn_reason, error: error))
    else
      GitHub.dogstats.increment("u2f_registration_create",
        tags: ["promoted:#{!!convert_for}",
          "transports:#{u2f_registration.transports}",
          "passkey:#{u2f_registration.is_passkey_registration?}",
          "useragent_nickname:#{useragent_nickname}",
          "resident_key:#{resident_key}",
          "backup_eligibility:#{u2f_registration.backup_eligibility}",
          "backup_state:#{u2f_registration.backup_state}",
          "user_verifying:#{u2f_registration.user_verifying}",
          "authenticator_type:#{u2f_registration.platform_authenticator? ? "platform" : "cross-platform"}"
        ])

      if u2f_registration.is_passkey_registration?
        AccountMailer.passkey_added(current_user, useragent_nickname).deliver_later
        if current_device_id && !associate_trusted_device_with_client(u2f_registration, :create_registration)
          track_failure(parsed_useragent, webauthn_reason, "passkey_association_failure")
        end
        session[:new_passkey_id] = u2f_registration.id
        type = u2f_registration.nickname_type(!!convert_for)
      else # security key
        session[:security_key_to_upgrade] = u2f_registration.id if u2f_registration.is_passkey_eligible_on_auth?(:create, current_device_id)
        AccountMailer.security_key_added(current_user, nickname).deliver_later
      end
      # both
      render status: 201, json: register_response_hash(webauthn_reason: webauthn_reason, nickname: nickname, passkey_type: type).merge(
          registration: render_to_string(
          partial: "settings/user/security_key",
          formats: [:html],
          locals: { registration: u2f_registration },
        ),
      )
    end
  end

  def track_failure(parsed_useragent, webauthn_reason, failure_reason) # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment("u2f_registration", tags: [
      "action:create_registration",
      "for_passkey:#{!(webauthn_reason == :security_key_registration)}",
      "failure_reason:#{failure_reason}",
    ])

    U2fRegistration.log_result("webauthn_create_registration_attempt", self.class.name, webauthn_reason, false, failure_reason, nil)
  end

  def nickname_check # rubocop:todo GitHub/UseRestfulActions
    nickname = params[:value].to_s.strip

    if nickname.empty?
      render plain: "You must provide a nickname.", status: 422
    elsif nickname.length > 100
      render plain: "The nickname is too long.", status: 422
    elsif !GitHub::UTF8.valid_unicode3?(nickname)
      # the nickname column currently does not support utfmb4 characters (any emojis or other 4-byte characters)
      render plain: "The nickname contains invalid characters.", status: 422
    elsif UNINFORMATIVE_NICKNAMES.include?(nickname.downcase)
      render plain: "The nickname is not allowed, consider something uniquely identifiable, like the name of your password manager or account provider.", status: 422
    elsif current_user.u2f_registrations.where(nickname: nickname).where.not(id: session[:new_passkey_id]).exists?
      render plain: "You already have a device called #{nickname}", status: 422
    else
      head :ok
    end
  end

  def destroy
    registration = current_user.u2f_registrations.find_by_id!(params[:id])
    is_last_security_key = current_user.u2f_registrations.security_keys.count == 1 && !registration.is_passkey_registration?
    nickname = registration.nickname
    is_passkey = registration.is_passkey_registration?

    # before destroy registration we check if it is a passkey being destroyed
    # and set trusted_device_available field in the associated authenticated device to
    # nil so that user will be prompt to register this device next time.
    if is_passkey
      devices = registration.authenticated_devices_registered
      current_user.authenticated_devices.where(id: devices).update_all(trusted_device_available: nil)
    end

    registration.destroy
    current_user.two_factor_credential.update(login_preference: nil) if is_last_security_key && current_user.two_factor_credential&.webauthn_preferred?

    if is_passkey
      AccountMailer.passkey_removed(current_user, nickname).deliver_later
    else
      AccountMailer.security_key_removed(current_user, nickname).deliver_later
    end

    if request.xhr?
      render json: register_response_hash(webauthn_reason: :security_key_registration)
    else
      redirect_to :back
    end
  end

  def trusted_facets # rubocop:todo GitHub/UseRestfulActions
    headers["Content-Type"] = "application/fido.trusted-apps+json"
    headers["Access-Control-Allow-Origin"] = "*"

    render(status: 200, json: {
      trustedFacets: [{
        version: { major: 1, minor: 0 },
        ids: GitHub.u2f_trusted_facets,
      }],
    })
  end

  # Renders the webauthn request UX and forms for the login page async after the cached page load
  # We only loading this fragment from the default login page (form_supports_passkeys)
  def login_fragment # rubocop:todo GitHub/UseRestfulActions
    if FeatureFlag.vexi.enabled?(:login_redesign, default: false)
      render partial: "sessions/webauthn/login_fragment"
    else
      render partial: "sessions/webauthn/login_fragment_old"
    end
  end

  private

  # a Hash of new RegisterRequests and SignRequests to be sent back to client.
  #
  # Returns a Hash.
  def register_response_hash(webauthn_reason:, nickname: nil, passkey_type: nil, error: nil)
    {
      webauthn_register_request: webauthn_register_request(webauthn_reason: webauthn_reason),
      registered_passkeys_count: current_user.u2f_registrations.passkeys.count,
      registered_security_keys_count: current_user.u2f_registrations.security_keys.count,
      nickname: nickname,
      passkey_type: passkey_type,
      error: error
    }
  end

  # Check that the browser/server support U2F.
  #
  # Returns boolean.
  def ensure_security_key_enabled
    request_origin_can_support_webauthn?(request)
  end

  def generate_nickname(response_hash, for_passkey, convert_for, parsed_useragent)
    if !for_passkey
      # use provided nickname for security keys
      nickname = params[:nickname].to_s
    else # passkey
      attachment = response_hash.dig("authenticator_attachment")
      transports = response_hash.dig("response", "transports")

      # use existing name when we have one
      base_nickname = if convert_for
        "#{convert_for.nickname} passkey"
      # try to separate out hardware keys. We will miss the ones that return empty transports,
      # but windows hello is also cross-platform with empty transports so we can't include them
      elsif attachment == "cross-platform" && transports && (transports.include?("usb") || transports.include?("nfc"))
        "Hardware key"
      else
        # use useragent generated display name as a placeholder to create the records for everything else
        # if it's a multi-device credential, we'll clear this nickname before returning the response
        AuthenticatedDevice.generated_display_name(parsed_useragent)
      end

      nicknames = current_user.u2f_registrations.pluck(:nickname)
      count = nicknames.count do |nickname|
        nickname.starts_with?(base_nickname)
      end

      nickname = if count > 0
        "#{base_nickname} #{count}"
      else
        base_nickname
      end
      i = 1

      # Ensure we generate something unique, we attempt 100 times to create
      # something nice looking e.g. Chrome on macOS 1-100 before
      # we give up and generate something random
      while nicknames.include?(nickname)
        if i > 100
          nickname = "#{base_nickname} #{SecureRandom.hex}"
        else
          nickname = "#{base_nickname} #{count + i}"
        end
        i += 1
      end
    end
    nickname
  end
end
