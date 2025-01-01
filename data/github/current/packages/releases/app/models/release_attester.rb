# typed: true
# frozen_string_literal: true

require "monolith-twirp-attester"

module ReleaseAttester
  ATTESTER_URL = GitHub.attester_url
  ATTESTER_HMAC_KEY = GitHub.attester_hmac_key
  FAILBOT_APP_NAME = "attester"
  SERVICE_NAME = "attester"

  # Create a release attestation from the provided statement
  sig { params(statement: InTotoAttestation::V1::Statement).returns(TwirpResponse) }
  def self.attest_release(statement)
    response = TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      attester_client.create_release_attestation(
        MonolithTwirp::Attester::V0::CreateReleaseAttestationRequest.new(statement: statement)
      )
    end

    T.let(response, TwirpResponse).tap do |res|
      GitHub.dogstats.increment("attester.api.status", tags: ["status:#{res.status}", "rpc:create_release_attestation"])
    end
  end

  # Internal: Constructs a Attester client
  sig { returns(MonolithTwirp::Attester::V0::ReleaseAPIClient) }
  def self.attester_client
    MonolithTwirp::Attester::V0::ReleaseAPIClient.new(self.attester_connection)
  end

  sig { returns(Faraday::Connection) }
  def self.attester_connection
    # setup the Faraday connection
    # This adds GitHub::FaradayMiddleware::RequestID & GitHub::FaradayMiddleware::TenantContext for us
    connection = GitHub::FaradayClient.internal(SERVICE_NAME, ATTESTER_URL) do |conn|
      # Use the Attester Request-HMAC middleware to sign the request
      conn.use MonolithTwirp::Attester::RequestHMAC, ATTESTER_HMAC_KEY
      # Send actor_id, installation_id, etc to TMA via headers
      conn.use GitHub::FaradayMiddleware::RequestAnalytics

      # Increase request timeouts
      conn.options[:timeout]      = 8     # read/write timeouts set to 8 seconds
      conn.options[:open_timeout] = 0.250 # connection open timeout to 250ms
    end
  end
end
