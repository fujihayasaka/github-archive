# typed: true
# frozen_string_literal: true

class AddMarketingConsentToMultiTenantProvisioningRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :multi_tenant_provisioning_requests, :marketing_consent, :boolean, null: false, default: false
  end
end
