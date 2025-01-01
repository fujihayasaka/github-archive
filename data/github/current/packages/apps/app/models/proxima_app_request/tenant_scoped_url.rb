# typed: strict
# frozen_string_literal: true

class ProximaAppRequest
  module TenantScopedUrl

    ProximaSyncableApp = T.type_alias { T.any(Integration, OauthApplication) }

    sig { params(app: ProximaSyncableApp).returns(T::Boolean) }
    def self.app_supports_tenant_url?(app)
      return app.owner == GitHub.first_party_apps_owner if GitHub.multi_tenant_enterprise?

      Apps::Privileged.capable?(:proxima_first_party_sync, app: app)
    end

    sig { params(app: ProximaSyncableApp, url: T.nilable(String)).returns(T::Boolean) }
    def self.should_generate?(app:, url: nil)
      return false if url.blank?

      url.include?("{hostname}") && app_supports_tenant_url?(app)
    end

    sig { params(templated_url: String, app: ProximaSyncableApp).returns(T.nilable(String)) }
    def self.generate(templated_url, app)
      if GitHub.multi_tenant_enterprise?
        return templated_url.gsub("{hostname}", GitHub::host_name_with_tenant)
      end

      hostname = app.feature_enabled?(:override_generated_url_hostname) ? Apps::Privileged.property(:proxima_url_templating_hostname, app: app) : GitHub::host_name
      templated_url.gsub("{hostname}", hostname)
    end
  end
end
