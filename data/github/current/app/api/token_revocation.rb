# typed: true
# frozen_string_literal: true

class Api::TokenRevocation < Api::App
  include ReceiveSchemaWithOpenApi

  before do
    deliver_error! 404 unless TokenRevocation::Helper.credential_revocation_enabled?
    # Dotcom : we won't allow any authenticated requests
    # Proxima/GHES : we will allow authenticated requests given the nature of the environment
    if !GitHub.single_or_multi_tenant_enterprise? && !anonymous_request?
      deliver_error! 403,
        message: "This API endpoint can only be accessed anonymously.",
        documentation_url: "/credentials/revoke#revoke-a-list-of-credentials"
    end
  end

  rate_limit_as Api::RateLimitConfiguration::CREDENTIAL_REVOCATION_FAMILY

  post "/credentials/revoke", operation_id: "credentials/revoke" do
    control_access :submit_credentials_for_revocation,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi
    credentials = data["credentials"]

    GitHub.dogstats.increment("credential_revocation_api.request", tags: ["state:initial", "request_size:#{request_bucket(credentials.size.to_s)}"])
    tokens = TokenIdentification.identify_tokens(credentials)
    # identify_tokens always initializes all token type keys. `T.must_because` is needed because
    # Sorbet types hash access as nilable even when the key is always present.
    must_reason = "identify_tokens always initializes this key"
    valid_tokens_count = T.must_because(tokens[:PERSONAL_ACCESS_TOKEN]) { must_reason }.size +
      T.must_because(tokens[:FINE_GRAINED_PERSONAL_ACCESS_TOKEN]) { must_reason }.size +
      T.must_because(tokens[:OAUTH_APP_TOKEN]) { must_reason }.size +
      T.must_because(tokens[:GH_APP_USER_TO_SERVER_TOKEN]) { must_reason }.size +
      T.must_because(tokens[:GH_APP_REFRESH_TOKEN]) { must_reason }.size
    unknown_tokens_count = T.must_because(tokens[:UNKNOWN]) { must_reason }.size
    GitHub.dogstats.increment("credential_revocation_api.request", tags: ["state:token_identification"])
    GitHub.dogstats.count("credential_revocation_api.valid_tokens_identified", valid_tokens_count)
    GitHub.dogstats.count("credential_revocation_api.invalid_tokens_identified", unknown_tokens_count)

    return deliver_empty status: 202 if valid_tokens_count.zero?

    encrypted_tokens = TokenRevocation::Helper.encrypt_credentials(tokens)

    TokenRevocationJob.perform_later(encrypted_tokens)
    GitHub.dogstats.increment("credential_revocation_api.request", tags: ["state:job_performing"])
    deliver_empty status: 202
  end

  private

  def request_bucket(credential_size)
    credential_size[0] + ("x" * credential_size[1..].length)
  end
end
