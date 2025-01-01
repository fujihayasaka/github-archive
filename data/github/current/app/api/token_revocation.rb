# typed: true
# frozen_string_literal: true

class Api::TokenRevocation < Api::App
  include ReceiveSchemaWithOpenApi

  post "/credentials/revoke", operation_id: "credentials/revoke" do
    return deliver_empty status: 404 unless TokenRevocation::Helper.credential_revocation_enabled?

    control_access :submit_credentials_for_revocation,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    GitHub.dogstats.increment("credential_revocation_api.request", tags: ["state: initial", "token_count:#{data.count}"])

    tokens = TokenIdentification.identify_tokens(data)
    valid_tokens_count = T.must(tokens[:PERSONAL_ACCESS_TOKEN]).size + T.must(tokens[:FINE_GRAINED_PERSONAL_ACCESS_TOKEN]).size
    unknown_tokens_count = T.must(tokens[:UNKNOWN]).size
    GitHub.dogstats.increment("credential_revocation_api.request", tags: ["state:token_identification"])
    GitHub.dogstats.increment("credential_revocation_api.token_identification", tags: ["valid_count:#{valid_tokens_count}", "invalid_count:#{unknown_tokens_count}"])

    return deliver_empty status: 202 if unknown_tokens_count == data.count

    TokenRevocationJob.perform_later(tokens)
    GitHub.dogstats.increment("credential_revocation_api.request", tags: ["state:job_performing"])
    deliver_empty status: 202
  end
end
