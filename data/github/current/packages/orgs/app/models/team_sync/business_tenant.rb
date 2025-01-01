# typed: true
# frozen_string_literal: true
module TeamSync
  class BusinessTenant < ApplicationRecord::Notify

    include GitHub::Relay::GlobalIdentification
    include Instrumentation::Model

    self.table_name = "team_sync_business_tenants"

    belongs_to :business, foreign_key: "business_id", class_name: "Business", inverse_of: :team_sync_tenant

    encrypts :encrypted_ssws_token

    after_update_commit :instrument_status_change, if: :status_previously_changed?
    after_update_commit :instrument_okta_credentials_change, if: :encrypted_ssws_token_previously_changed?

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

    def register(service_client:  GroupSyncer.client)
      # We register a group-syncer tenant for the business, just so we can get
      # the template for building the URL that will initiate setup on the
      # provider). We may consider other options (e.g., a dedicated endpoint or
      # a gem method) in the future.
      res = service_client.register_tenant(
        org_id: T.must(self.business).global_relay_id.to_s,
        external_provider_type: GroupSyncer::V1::ExternalProviderType.resolve(TeamSync::Tenant::PROVIDER_TYPE_MAP[self.provider_type]),
        external_provider_id: self.provider_id,
        status: GroupSyncer::V1::TenantStatus.resolve(TeamSync::Tenant::STATUS_MAP[self.status]),
        token: self.encrypted_ssws_token,
        url: self.url,
      )
      return res.error if res.error.present?

      # otherwise response was a success
      res = res.data
      self.update(setup_url_template: res.setup_url)

      nil
    end

    def disable
      T.must(business).organizations
              .map(&:team_sync_tenant).compact
              .each(&:disable)
      update(status: "disabled")
      UpdateTeamSyncTenantJob.perform_later(self)
    end

    def saml_settings_changed(saml_provider)
      disable if saml_provider.destroyed? || provider_settings_diverged?(saml_provider)
    end

    def provider_label
      TeamSync::Tenant::PROVIDER_LABEL_MAP[self.provider_type]
    end

    def event_prefix
      :team_sync_tenant
    end

    def event_payload
      {
        team_sync_business_tenant: self,
        business: self.business,
        plain_ssws_token: encrypted_ssws_token,
        url: url,
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
        team_sync_business_tenant: self,
        business: self.business,
        previous_status: status_before_last_save,
        current_status: status
    end

    def instrument_okta_credentials_change
      instrument :update_okta_credentials
    end
  end
end
