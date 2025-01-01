# typed: true
# frozen_string_literal: true
module TeamSync
  class Tenant < ApplicationRecord::Notify

    class InvalidStatusError < StandardError; end

    include GitHub::Relay::GlobalIdentification
    include Instrumentation::Model

    self.table_name = "team_sync_tenants"

    belongs_to :organization, foreign_key: "organization_id", class_name: "Organization", inverse_of: :team_sync_tenant
    has_many :team_group_mappings, class_name: "Team::GroupMapping", inverse_of: :tenant

    encrypts :encrypted_ssws_token

    after_update_commit :instrument_status_change, if: :status_previously_changed?
    after_update_commit :instrument_okta_credentials_change, if: :encrypted_ssws_token_previously_changed?


    PROVIDER_TYPE_MAP = {
      "unknown" => :UNKNOWN,
      "azuread" => :AZURE_AD,
      "okta" => :OKTA,
    }

    PROVIDER_LABEL_MAP = {
      "unknown" => "Unknown",
      "azuread" => "Entra ID",
      "okta" => "Okta",
    }

    STATUS_MAP = {
      "unknown" => :UNKNOWN_STATUS,
      "pending" => :PENDING,
      "failed" => :FAILED,
      "ready" => :READY,
      "enabled" => :ENABLED,
      "disabled" => :DISABLED,
    }

    enum :status, {
      pending: 1, # prior to completion of admin consent
      failed: 2, # admin consent failed
      ready: 3, # setup complete but not yet enabled by admin
      enabled: 4, # setup complete and enabled by admin
      disabled: 5, # permission no longer exists for tenant
    }

    enum :provider_type, {
      azuread: 1,
      okta: 2,
    }

    alias_method :team_sync_enabled?, :enabled?

    def setup_url_template
      GitHub.kv.get("team_sync_tenant:#{id}:setup_url").value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    def setup_url_template=(setup_url)
      GitHub.kv.set("team_sync_tenant:#{id}:setup_url", setup_url) # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    def register(service_client:  GroupSyncer.client)
      # RPC
      res = service_client.register_tenant(
        org_id: T.must(self.organization).global_relay_id.to_s,
        external_provider_type: GroupSyncer::V1::ExternalProviderType.resolve(PROVIDER_TYPE_MAP[self.provider_type]),
        external_provider_id: self.provider_id,
        status: GroupSyncer::V1::TenantStatus.resolve(STATUS_MAP[self.status]),
        token: self.encrypted_ssws_token,
        url: self.url,
      )
      return res.error if res.error.present?

      # otherwise response was a success
      res = res.data
      self.setup_url_template = res.setup_url

      nil
    end

    def disable
      self.team_group_mappings.destroy_all
      update(status: "disabled")
      UpdateTeamSyncTenantJob.perform_later(self)
    end

    def saml_settings_changed(saml_provider)
      disable if saml_provider.destroyed? || provider_settings_diverged?(saml_provider)
    end

    def provider_label
      PROVIDER_LABEL_MAP[self.provider_type]
    end

    def event_prefix
      :team_sync_tenant
    end

    def event_payload
      {
        team_sync_tenant: self,
        org: self.organization,
        provider_id: self.provider_id,
      }
    end

    private

    def provider_settings_diverged?(saml_provider)
      provider = ::TeamSync::Provider.detect(issuer: saml_provider.issuer)

      return true if provider.nil?
      return true if provider.type != self.provider_type
      provider.id != self.provider_id
    end

    def instrument_status_change
      GlobalInstrumenter.instrument "team_sync_tenant.status_change",
        team_sync_tenant: self,
        organization: self.organization,
        previous_status: status_before_last_save,
        current_status: status
    end

    def instrument_okta_credentials_change
      instrument :update_okta_credentials
    end
  end
end
