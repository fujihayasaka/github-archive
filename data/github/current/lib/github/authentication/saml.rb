# typed: true
# frozen_string_literal: true

require "securerandom"
require "security_utils"
require "saml"

module GitHub
  module Authentication
    # SAML 2.0 web single sign on (SSO) and single logout authentication
    # described in
    # http://docs.oasis-open.org/security/saml/v2.0/saml-profiles-2.0-os.pdf
    # sections 4 and 4.4.
    #
    # ## Auth options
    #
    # Identity Provider (idP) configuration
    #
    # :sso_url              - endpoint for single sign on.
    # :idp_certificate      - idP certificate for verifying responses.
    # :idp_certificate_file - if `idp_certificate` isn't specified, read from this file
    #                         for the idP certificate. This is for backwards compatability with
    #                         enterprise-vm which stores the certificate in a file.
    # :issuer               - idP issuer. Used to validate responses.
    # :idp_initiated_sso    - if this is on, responses will not be checked for corresponding requests
    #                         and AuthnRequest will not be provided to the IdP.
    # :disable_admin_demote - if this is on, admin bit is ignored and users won't promoted or demoted.
    # :signature_method     - algorithm to use for the signature.
    # :digest_method        - algorithm to use for the digest.
    # :encrypted_assertions - if this is on, SAML responses require assertions to be encrypted via sp_pkcs12_file
    # :encryption_method    - algorithm to use for encrypted assertions.
    # :key_transport_method - algorithm to use for the key of encrypted assertions.
    #
    # SP configuration
    #
    # :sp_pkcs12_file       - SP keypair for signing AuthnRequests and Metadata as well as encrypting assertions.
    # :sp_url               - base URL of SP.
    #
    #
    # Optional attribute mappings for pre-populating user profiles.
    #
    # :admin        - promote user as admin if value is present
    # :profile_name - real name
    # :profile_mail - list of emails
    # :profile_key  - list of ssh public keys
    #
    # ## See also
    #
    # * https://www.oasis-open.org/committees/download.php/11511/sstc-saml-tech-overview-2.0-draft-03.pdf
    # * https://www.oasis-open.org/standards#samlv2.0
    #
    class SAML < Default
      include UserHandler

      INVALID_RESPONSE = "External authentication returned an invalid message, please have your administrator check the authentication log."
      UNAUTHORIZED_RESPONSE = "External authentication was not able to authenticate you, please have your administrator check the authentication log."
      REQUEST_DENIED_RESPONSE = "External authentication has denied your request to access this site."

      # In seconds
      AUTHN_REQUEST_TIMEOUT = 300
      DEFAULT_SAML_SESSION_EXPIRATION = 604800 # 1 week
      MAX_RETRIES = 3

      def name
        custom_authentication_name || "SAML"
      end

      def default_config
        {}
      end

      def external?
        true
      end

      # Since users may be either all external, or a mix of builtin and external,
      # 2FA requirement is never an option for SAML.
      def two_factor_org_requirement_allowed?
        false
      end

      # Public: Determines if a given user is externally managed by SAML or SAML + SCIM,
      # or if they're using builtin authentication.
      #
      # If the user does not exist locally, assume we are asking about an
      # SAML user whose account has not yet been created.
      #
      # user_or_login - The User itself or their login/email.
      #
      # Returns a Boolean.
      def external_user?(user_or_login)
        # In GHES environments, SCIM enablement does not make all users external ones.
        return true unless builtin_auth_fallback? || GitHub.global_business&.enterprise_server_scim_enabled?

        user = User.reify(user_or_login)
        return true unless user.present?

        if GitHub.global_business&.enterprise_server_scim_enabled?
          external_identity = user.external_identities.first
          external_identity.present?
        else
          user.saml_mapping.present?
        end
      end

      # Public: Returns any mapping information we have on hand, if any, for
      # external users.
      def external_mapping(user)
        user.saml_mapping
      end

      def signup_enabled?
        false
      end

      # Whether or not to validate a user using username and password.
      #
      # This is used in the /meta API endpoint in order to signal to our
      # client apps (like Desktop) whether they will be able to authenticate
      # using username and password or if they have to use the oauth web flow
      # for sign in.
      #
      # Returns false for the SAML authentication provider
      def verifiable?
        false
      end

      def sudo_mode_enabled?(user)
        return false unless builtin_auth_fallback?

        !external_user?(user)
      end

      def idp_initiated_sso?
        configuration[:idp_initiated_sso]
      end

      # Public: Returns a string containing the IdP certificate or nil.
      def idp_certificate
        @idp_certificate ||= if configuration[:idp_certificate]
          configuration[:idp_certificate]
        elsif configuration[:idp_certificate_file]
          File.read(configuration[:idp_certificate_file])
        end
      end

      # Public: Returns OpenSSL::PKCS12 instance containing the SP key or nil.
      def sp_pkcs12
        return nil unless configuration[:sp_pkcs12_file]
        @sp_pkcs12 ||= OpenSSL::PKCS12.new(File.read(configuration[:sp_pkcs12_file]))
      end

      def encrypted_assertions
        !!configuration[:encrypted_assertions]
      end

      def request_tracking?
        return false if ::SAML.mocked[:skip_request_tracking] || idp_initiated_sso?
        true
      end

      def self.track_request(request, expiry, csrf)
        ActiveRecord::Base.connected_to(role: :writing) do
          key = saml_request_key(request.id)
          if csrf
            GitHub.kv.set(key, csrf, expires: expiry) # rubocop:todo GitHub/DoNotUseGlobalKv
          else
            GitHub.kv.del(key) # rubocop:todo GitHub/DoNotUseGlobalKv
          end
        end
      end

      def track_request(request, expiry, csrf)
        self.class.track_request(request, expiry, csrf)
      end

      def saml_request_key(id)
        self.class.saml_request_key(id)
      end

      def self.saml_request_key(id)
        raise "No id supplied" if id.nil?
        "saml:in_response_to_requests:#{id}"
      end

      def debug_logging_enabled?
        GitHub.config.get("saml.debug_logging_enabled") == "true"
      end

      def self.in_response_to_request?(response, http_request)
        # Use the backup cookie for those cases where the browser doesn't support the SameSite=none attribute.
        saml_cookie = http_request.cookies["saml_csrf_token"] || http_request.cookies["saml_csrf_token_legacy"]
        cookie_csrf = saml_cookie.to_s
        relaystate_csrf = http_request.params[:RelayState].to_s
        # ensure both the request and client maintain the csrf token
        return false unless SecurityUtils.secure_compare(relaystate_csrf, cookie_csrf) && !relaystate_csrf.nil?

        key = saml_request_key(response.in_response_to) if response.in_response_to
        stored_csrf = GitHub.kv.get(key).value { return false } if key # rubocop:todo GitHub/DoNotUseGlobalKv
        return false unless key && stored_csrf

        if SecurityUtils.secure_compare(stored_csrf, relaystate_csrf)
          # clean up
          ActiveRecord::Base.connected_to(role: :writing) do
            GitHub.kv.del(key) # rubocop:todo GitHub/DoNotUseGlobalKv
          end
          true
        else
          false
        end
      end

      def in_response_to_request?(response, http_request)
        self.class.in_response_to_request?(response, http_request)
      end

      # idP URL string to redirect to for authentication
      def path(return_to = nil, csrf = nil, force_authn = false)
        redirect = URI.parse(configuration[:sso_url])

        # When idp_initiated_sso is turned on, we redirect to the IdP without
        # an AuthnRequest. This doesn't follow the SAML spec, but the setting
        # itself is a workaround for IdPs that aren't fully to spec, and we
        # don't want users to turn on the setting unless it's needed.
        # See https://github.com/github/github/issues/48636#issuecomment-164474369
        return redirect.to_s if idp_initiated_sso?

        # five minutes from now
        expiry = Time.now.utc + AUTHN_REQUEST_TIMEOUT

        request = ::SAML::Message::AuthnRequest.new \
          assertion_consumer_service_url: "#{configuration[:sp_url]}/saml/consume",
          destination: configuration[:sso_url],
          issuer: service_provider_url,
          expiry: expiry,
          signature_method: configuration[:signature_method],
          digest_method: configuration[:digest_method],
          force_authn: force_authn

        params = {
          "SAMLRequest" => request.to_query,
        }

        # PKCS12 is a container that holds both a private key, and a public
        # certificate. This file is generated by github/enterprise2 in
        # `vm_files/usr/local/share/enterprise/ghe-storage-prepare`.
        #
        # The certificate in not embedded in the auth request because it causes
        # the redirect url to be too long for nginx to handle. According to the
        # spec, the certificate should be defined by SP metadata.

        if request_tracking?
          track_request(request, expiry, csrf)
          params["RelayState"] = csrf
        end

        if pkcs12 = sp_pkcs12
          params["SigAlg"] = request.signature_method
          # request.sign(:private_key => pkcs12.key, :external => true)
          params["Signature"] = request.query_signature({ private_key: pkcs12.key, data: params })
        end

        redirect.query = [redirect.query, params.to_param].compact.join("&")
        redirect.to_s
      end

      # SP XML metadata string used by idP
      def metadata
        options = {
          assertion_consumer_service_url: "#{configuration[:sp_url]}/saml/consume",
          sign_assertions: true,
          encrypted_assertions: encrypted_assertions,
          issuer: configuration[:sp_url],
          name_identifier_format: configuration[:name_id_format],
        }

        if pkcs12 = sp_pkcs12
          # We use the SP certificate here for signing *and* encryption
          options[:sp_signing_certificate] = pkcs12.certificate.to_s
          options[:sp_encryption_certificate] = pkcs12.certificate.to_s
        end

        metadata = ::SAML::Message::Metadata.new(options)
        metadata.to_xml
      end

      # Alias builtin web request authentication so we can override it for SAML
      # but still call it if builtin authentication fallback is enabled.
      alias_method :builtin_rails_authenticate, :rails_authenticate

      # Callback endpoint for authentication request specified in section "4.1
      # Web Browser SSO Profile".
      #
      # If built-in authentication fallback is enabled *and* the request includes
      # a login/password pair, it will defer to the default (builtin) auth class.
      #
      # Returns a GitHub::Authentication::Result struct
      #
      # TODO: Default#rails_authenticate should only log, then call a custom auth method
      def rails_authenticate(request, octolytics_id:, current_device_id:)
        if builtin_auth_fallback? && builtin_auth_attempt?(request)
          return builtin_rails_authenticate(request, octolytics_id: octolytics_id, current_device_id: current_device_id)
        end
        GitHub::Authentication.logger.with_named_tags("code.namespace" => self.class.name, "code.function" => __method__, "http.client_ip" => request.remote_ip) do
          # Only log raw response if debugging
          GitHub::Authentication.logger.info("starting SAML auth", "gh.saml.raw_request" => request.params[:SAMLResponse]) if debug_logging_enabled?

          options = {
            encrypted_assertions: encrypted_assertions,
            key: sp_pkcs12&.key,
            encryption_method: configuration[:encryption_method],
            key_transport_method: configuration[:key_transport_method],
          }

          begin
            saml_response = ::SAML::Message::Response.from_param(request.params[:SAMLResponse], options)
            failure_result = get_auth_failure_result(saml_response, request)
          rescue => err
            log_auth_validation_event("failure - Invalid SAML response - #{err.message}", nil, request.params)
            failure_result = GitHub::Authentication::Result.failure message: INVALID_RESPONSE
          end

          if failure_result
            GitHub.dogstats.increment("saml.sso_completed", tags: [
              "saml_result:failure",
              "reason:#{failure_result.failure_type || :unspecified}"
            ])

            return failure_result
          end

          saml_user_data = Platform::Provisioning::SamlUserData.load(
            saml_response,
            persist_attributes: true,
            configurable_attrs: attribute_mappings.values,
            attribute_mapping: attribute_mappings,
          )

          result = if GitHub.global_business&.enterprise_server_scim_enabled?
            Platform::Provisioning::EnterpriseServerSCIMIdentityProvisioner.find_user_in_scim_managed_enterprise \
              target: GitHub.global_business,
              user_data: saml_user_data,
              mapper: Platform::Provisioning::SamlMapper
          else
            Platform::Provisioning::EnterpriseServerIdentityProvisioner.provision_and_add_member \
              user_data: saml_user_data,
              mapper: Platform::Provisioning::SamlMapper
          end

          user = result&.user
          log_data = { "gh.saml.login" => user.try(:login) || saml_user_data.name_id }
          log_data.merge!({ "gh.saml.response.attributes" => saml_response.attributes }) if debug_logging_enabled?

          GitHub::Authentication.logger.with_named_tags(log_data) do
            if user
              if error = result.errors.detect { |e| e.reason == :user_suspended }
                GitHub::Authentication.logger.error("SAML failure - user suspended", "exception.message" => error.message)

                GitHub.dogstats.increment("saml.sso_completed", tags: [
                  "saml_result:failure",
                  "reason:user_suspended",
                ])

                return GitHub::Authentication::Result.suspended_failure message: error.message
              end

              number_of_retries = 0

              while number_of_retries < MAX_RETRIES do
                message = ::SAML::Session.transaction do
                  begin
                    # Set us up the SAML::Session for SAML state tracking
                    saml_session = ::SAML::Session.where(user_id: user.id).first
                    saml_session ||= ::SAML::Session.new(user_id: user.id)

                    # update how long this session should be good for
                    expires_at = saml_response.session_expires_at || Time.now + saml_session_expiration_default

                    # mysql doesn't store timezone offset, but ActiveRecord attributes
                    # are converted to local time. This makes the number line up so that
                    # when it is converted, it's the correct utc time.
                    saml_session.expires_at = expires_at.localtime

                    unless saml_session.save
                      next saml_session.errors.full_messages.join("\n")
                    end
                  rescue ActiveRecord::RecordNotUnique
                    saml_session.errors.full_messages.join("\n")
                  end
                end

                if message
                  # retry creation of a session when it failed first time
                  next if ++number_of_retries < MAX_RETRIES
                  GitHub::Authentication.logger.error("SAML failure - couldn't save session", "exception.message" => message)
                  return GitHub::Authentication::Result.failure message: message
                end
                GitHub::Authentication.logger.info("SAML success", "gh.saml.result.message" => message)

                break
              end

              GitHub.dogstats.increment("saml.sso_completed", tags: [
                "saml_result:success",
              ])

              GitHub::Authentication::Result.success user
            else
              messages = result.error_messages
              message_text = messages.join "\n"
              if result.errors.any? { |e| e.reason == :missing_login }

                GitHub.dogstats.increment("saml.sso_completed", tags: [
                  "saml_result:failure",
                  "reason:missing_login",
                ])
                GitHub::Authentication.logger.error("failure - unable to find a login", "exception.message" => message_text)
              else
                GitHub.dogstats.increment("saml.sso_completed", tags: [
                  "saml_result:failure",
                  "reason:user_not_found",
                ])
                GitHub::Authentication.logger.error("failure - user not found", "exception.message" => message_text)
              end
              GitHub::Authentication::Result.failure message: message_text
            end
          end
        end
      end

      def rails_logout(request, current_user, redirect_to: "/")
        LogoutResult.success redirect_to
      end

      # Alias builtin password authentication so we can override it for SAML but
      # still call it if builtin authentication fallback is enabled.
      alias_method :builtin_password_authenticate, :password_authenticate

      # Public: Attempts to authenticate a user via login and password.
      #
      # The normal SAML flow won't call it, so it returns a failure by default.
      # But if built-in authentication fallback is enabled, rails_authenticate
      # defers to builtin_rails_authenticate, which will try to call this one,
      # so we must defer again to the builtin counterpart.
      #
      # login    - The user login String
      # password - The user password String.
      #
      # Returns a GitHub::Authentication::Result
      def password_authenticate(login, password)
        return builtin_password_authenticate(login, password) if builtin_auth_fallback? && !external_user?(login)

        GitHub::Authentication::Result.failure message: "Password authentication is not supported by SAML authentication."
      end

      # Do not redirect on failure so we can display configuration or
      # bad response error messages
      def redirect_on_failure?
        false
      end

      # Mapping from name of attribute to idP configured attribute name. This
      # will be replaced with constant values rather than configurable values.
      def attribute_mappings
        @attribute_mappings ||= {
          user_name: configuration[:user_name],
          admin: configuration[:admin] || "administrator".freeze,
          emails: configuration[:emails] || "emails".freeze,
          display_name: configuration[:display_name] || "full_name".freeze,
          ssh_keys: configuration[:ssh_keys] || "public_keys".freeze,
          gpg_keys: configuration[:gpg_keys] || "gpg_keys".freeze,
        }
      end

      # Whether or not this authentication strategy allows built-in autentication
      # as a fallback (e.g. Allow users to sign in via SAML or username/password).
      def builtin_auth_fallback?
        GitHub.builtin_auth_fallback
      end

      private

      # Private: Checks if runtime environment is codespaces within development and changes the service
      #   provider url to include business slug for development in a codespace environment
      #
      # Returns String
      def service_provider_url
        return configuration[:sp_url] unless GitHub.codespaces?

        business = GitHub.global_business
        return configuration[:sp_url] unless business

        "#{configuration[:sp_url]}/enterprises/#{business.slug}"
      end

      # Public - Create a mapping between the user and the SAML NameID or
      # claim/name or claim/emailaddress in the case of a transient NameID and
      # keep a record of this.
      # It also updates the mapping when it exists.
      #
      # name_id: is the raw SAML NameID attribute or claim/name or claim/emailaddress from the SAML response.
      # name_id_format: is the format of the SAML response.
      # user_id: is the ID of the logged in User.
      #
      # Returns true if the mapping was created.
      def map_saml_entry(name_id, name_id_format, user_id)
        SamlMapping.by_name_id_and_name_id_format(name_id, name_id_format) || SamlMapping.create(user_id: user_id, name_id: name_id, name_id_format: name_id_format)
      rescue ActiveRecord::RecordNotUnique
        # we don't care if the insert fails due to dupe key violation
        true
      end

      def log_auth_validation_event(message, saml_response, params)
        log_data = {
          "gh.saml.login" => saml_response&.name_id || "_unknown",
          "gh.saml.errors" => saml_response&.errors || message,
        }
        # Only log params if debugging
        log_data["gh.saml.params"] = params if debug_logging_enabled?
        GitHub::Authentication.logger.info(message, log_data)
      end

      def get_auth_failure_result(saml_response, request)
        unless saml_response.in_response_to || idp_initiated_sso? || ::SAML.mocked[:skip_in_response_to_check]
          return GitHub::Authentication::Result.external_response_ignored
        end

        unless saml_response.valid?(
          issuer: configuration[:issuer],
          idp_certificate: idp_certificate,
          sp_url: configuration[:sp_url],
        )
          log_auth_validation_event("failure - Invalid SAML response", saml_response, request.params)
          return GitHub::Authentication::Result.failure message: INVALID_RESPONSE
        end

        if saml_response.request_denied?
          log_auth_validation_event("failure - RequestDenied", saml_response, request.params)
          return GitHub::Authentication::Result.failure message: saml_response.status_message || REQUEST_DENIED_RESPONSE
        end

        unless saml_response.success?
          log_auth_validation_event("failure - Unauthorized", saml_response, request.params)
          return GitHub::Authentication::Result.failure message: UNAUTHORIZED_RESPONSE
        end

        if request_tracking? && !in_response_to_request?(saml_response, request)
          log_auth_validation_event("failure - Unauthorized - In Response To invalid", saml_response, request.params)
          GitHub::Authentication::Result.failure message: UNAUTHORIZED_RESPONSE
        end
      end

      def saml_session_expiration_default
        configuration[:default_session_expiration] || DEFAULT_SAML_SESSION_EXPIRATION
      end
    end
  end
end
