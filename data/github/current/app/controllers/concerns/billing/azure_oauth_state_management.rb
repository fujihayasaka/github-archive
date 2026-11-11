# typed: strict
# frozen_string_literal: true

module Billing
  module AzureOauthStateManagement
    include Kernel
    extend T::Helpers
    extend ActiveSupport::Concern

    class AzureStateValidationError < StandardError; end

    sig { params(target: T.any(Organization, Business), explicit_tenant_selected: T::Boolean, tenant: String).returns(URI::HTTPS) }
    def azure_subscription_uri(target:, explicit_tenant_selected: false, tenant: "common")
      uri = URI("https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/authorize")

      state_hash = build_state_hash(target: target, explicit_tenant_selected: explicit_tenant_selected)
      state_encoded = hash_to_state(hash: state_hash)

      uri.query = URI.encode_www_form({
        client_id: GitHub.azure_oauth_app_id,
        redirect_uri: redirect_uri_for_target(target),
        scope: "https://management.azure.com/user_impersonation",
        response_type: "code",
        state: state_encoded,
        response_mode: "query",
        prompt: "select_account"
      })
      T.cast(uri, URI::HTTPS)
    end

    sig { params(hash: T::Hash[T.any(Symbol, String), T.untyped]).returns(String) }
    def hash_to_state(hash:)
      azure_state_token = T.unsafe(self).session[:azure_state_token]
      if azure_state_token.blank?
        azure_state_token = SecureRandom.hex
        T.unsafe(self).session[:azure_state_token] = azure_state_token
      end

      secure_hash = hash.merge(azure_state_token: azure_state_token)
      Base64.encode64(secure_hash.to_json)
    end

    sig { params(state: String, validate: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
    def state_to_hash(state:, validate: true)
      decoded_state = Base64.decode64(state)
      parsed_state = JSON.parse(decoded_state, { symbolize_names: true })

      validate_azure_oauth_state!(parsed_state) if validate
      parsed_state
    end

    private

    sig { params(state_data: T::Hash[Symbol, T.untyped]).void }
    def validate_azure_oauth_state!(state_data)
      if state_data[:azure_state_token].blank?
        raise(AzureStateValidationError, "Invalid OAuth state: missing state token")
      end

      session_state_token = T.unsafe(self).session[:azure_state_token]
      if session_state_token.blank?
        raise(AzureStateValidationError, "Invalid OAuth state: no session state found")
      end

      # Clear the state token from session so it can't be reused (one-time use)
      T.unsafe(self).session[:azure_state_token] = nil
      unless state_data[:azure_state_token] == session_state_token
        raise(AzureStateValidationError, "Invalid OAuth state: state token mismatch")
      end
    end

    sig { params(target: T.any(Business, Organization), explicit_tenant_selected: T::Boolean).returns(T::Hash[T.any(Symbol, String), T.untyped]) }
    def build_state_hash(target:, explicit_tenant_selected: false)
      hash = if target.is_a?(Business)
        {
          business_slug: target.slug,
          explicit_tenant_selected: explicit_tenant_selected,
        }
      else
        {
          org_login: target.display_login,
          explicit_tenant_selected: explicit_tenant_selected
        }
      end

      if target.is_a?(Business) && GitHub.multi_tenant_enterprise?
        # We pass the host name with tenant so the Azure redirects will work in Proxima where customers have custom subdomains
        hash[:host_name] = GitHub.host_name_with_tenant
      elsif target.is_a?(Business) && Rails.env.development? && T.unsafe(self).request.host != "localhost"
        # For local testing Azure requires redirect_uri to be "localhost", but we want to test
        # the Proxima cross-domain flow. When user starts on github.localhost (or ghe.localhost), Azure redirects
        # back to localhost/oauth_callback. Without setting the host_name here it then won't redirect back to github.localhost (or the original host).
        # Setting host_name here ensures the callback controller redirects to the original host.
        hash[:host_name] = GitHub.host_name
      end

      hash
    end

    sig { params(target: T.any(Business, Organization)).returns(String) }
    def redirect_uri_for_target(target)
      return GitHub.azure_oauth_app_redirect_uri_for_businesses if target.is_a?(Business)

      GitHub.azure_oauth_app_redirect_uri_for_orgs
    end
  end
end
