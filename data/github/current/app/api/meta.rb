# typed: true
# frozen_string_literal: true

class Api::Meta < Api::App

  include Api::App::CryptoKeyHelper

  # For the general /meta endpoint, individual service teams own the implementations to return the values in the payload.
  # There is work underway (https://github.com/github/proxima/issues/1216) to split the logic of populating the /meta
  # hash values into separate files in order to assign proper ownership.

  get "/meta", operation_id: "meta/get" do
    control_access :public_site_information, resource: Platform::PublicResource.new, allow_integrations: true, allow_user_via_granular_actor: true # rubocop:disable GitHub/PublicResource

    payload = {
      verifiable_password_authentication: GitHub.auth.verifiable?,
    }

    if GitHub.enterprise?
      payload[:installed_version] = GitHub.version_number
    else
      if FeatureFlag.vexi.enabled?(:proxima_meta_endpoint_support, default: false)
        domains = {
          "website" => Api::MetaPayloads::WebsiteDomains.payload,
          "codespaces" => Api::MetaPayloads::CodespacesDomains.payload,
          "copilot" => Api::MetaPayloads::CopilotDomains.payload,
          "packages" => Api::MetaPayloads::PackagesDomains.payload,
          "actions" => Api::MetaPayloads::ActionsDomains.payload,
          "actions_inbound" => Api::MetaPayloads::ActionsInboundDomains.payload,
          "artifact_attestations" => Api::MetaPayloads::ArtifactAttestationsDomains.payload,
        }.reject { |_, v| v == {} || v == [] }

        meta_payloads = {
          ssh_key_fingerprints: Api::MetaPayloads::SshKeyFingerprints.payload,
          ssh_keys: Api::MetaPayloads::SshKeys.payload,
          hooks: Api::MetaPayloads::Hooks.payload,
          web: Api::MetaPayloads::Web.payload,
          api: Api::MetaPayloads::Api.payload,
          git: Api::MetaPayloads::Git.payload,
          github_enterprise_importer: Api::MetaPayloads::GitHubEnterpriseImporter.payload,
          packages: Api::MetaPayloads::Packages.payload,
          pages: Api::MetaPayloads::Pages.payload,
          importer: Api::MetaPayloads::Importer.payload,
          actions: Api::MetaPayloads::Actions.payload,
          actions_macos: Api::MetaPayloads::ActionsMacos.payload,
          codespaces: Api::MetaPayloads::Codespaces.payload,
          dependabot: Api::MetaPayloads::DependabotIps.payload,
          copilot: Api::MetaPayloads::CopilotIps.payload,
          domains: domains
        }.reject { |_, v| v == {} || v == [] }

        payload.merge!(meta_payloads)
      else
        if GitHub.multi_tenant_enterprise?
          # for now, we only expose the artifact attestation domains
          payload.merge!(domains: GitHub::Config::ArtifactAttestations.meta_info_with_key)
        else
          payload.merge!(
            ssh_key_fingerprints: GitHub.ssh_host_key_fingerprints,
            ssh_keys: GitHub.ssh_host_keys,
            hooks: GitHub.hook_ips,
            web: GitHub.web_ips,
            api: GitHub.api_ips,
            git: GitHub.git_ips,
            github_enterprise_importer: GitHub.github_enterprise_importer_ips,
            packages: GitHub.packages_ips,
            pages: GitHub.pages_a_record_ips,
            importer: GitHub.github_source_importer_ips,
            actions: GitHub.actions_runner_ip_ranges,
            actions_macos: GitHub.maccloud_ips,
            codespaces: GitHub.codespaces_vm_ip_ranges,
            dependabot: GitHub.dependabot_ips,
            copilot: GitHub.copilot_ips,
            domains: GitHub.dnsdomains,
          )
        end
      end
    end

    deliver_raw payload
  end

  # in the future the following endpoints will be moved into separate files and assigned to the appropriate service teams

  get "/meta/public_keys/webhooks", operation_id: :unreleased do
    @route_owner = "@github/ecosystem-events"
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_vault_key(name: "EARTHSMOKE_HOOKSHOT_SIGNATURE_KEY", feature_flag: :public_key_webhook_signing)
  end

  # this endpoint can be deprecated once docs changes reflecting the new endpoint is out.
  get "/meta/public_keys/token_scanning", operation_id: :unreleased do
    @route_owner = "@github/secret-scanning"
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_vault_key(name: "EARTHSMOKE_TOKEN_SCANNING_SIGNING_KEY", feature_flag: nil)
  end

  get "/meta/public_keys/secret_scanning", operation_id: :unreleased do
    @route_owner = "@github/secret-scanning"
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_vault_key(name: "EARTHSMOKE_TOKEN_SCANNING_SIGNING_KEY", feature_flag: nil)
  end

  get "/meta/public_keys/copilot_api", operation_id: :unreleased do
    @route_owner = "@github/copilot-extensibility"
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_vault_key(name: "EARTHSMOKE_COPILOT_API_SIGNING_KEY", feature_flag: nil)
  end
end
