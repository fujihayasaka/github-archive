# typed: true
# frozen_string_literal: true

class Api::IntegrationManifests < Api::App
  include ReceiveSchemaWithOpenApi
  # This endpoint is unauthenticated by design, so has a higher unauthenticated
  # rate limit than other endpoints to enable valid, non-abusive usage on platforms
  # like Glitch that would otherwise be prohibited by the default rate limiting rules
  rate_limit_as Api::RateLimitConfiguration::INTEGRATION_MANIFEST_FAMILY

  post "/app-manifests/:code/conversions", operation_id: "apps/create-from-manifest" do
    receive_with_schema("app-manifest", "convert")
    manifest = IntegrationManifest.find_by(code: params["code"])
    record_or_404(manifest)

    unless T.must(manifest).valid?
      deliver_error! 422, errors: T.must(manifest).errors.full_messages
    end

    control_access :write_integration_manifest_conversion,
      resource: manifest,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    integration, pem, secret = T.must(manifest).create_integration!

    GlobalInstrumenter.instrument "integration.create", {
      integration: integration,
      actor: T.must(manifest).creator,
      owner: T.must(manifest).owner,
      from_manifest: true,
      manifest: T.must(manifest).data,
    }

    deliver :integration_hash, integration, pem: pem, secret: secret, status: 201
  end

  private

  # https://github.com/github/ecosystem-apps/issues/4779
  # similarly to skipping emu_visibility CAP we skip enforcing the tenant_verification CAP for the app-manifests endpoint
  def tenant_verification_enforceable
    :no
  end

  def emu_visibility_enforceable
    :no
  end
end
