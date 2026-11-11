# typed: strict
# frozen_string_literal: true

class Api::EnterpriseLicenseSync < Api::Enterprise::App
  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  get "/enterprises/:enterprise_id/license-sync-status", operation_id: "enterprise-admin/get-license-sync-status" do
    enterprise = find_enterprise!

    control_access :read_licensing,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      resource: enterprise

    enterprise_license_sync_data = Business::LicenseAttributer.new(enterprise).enterprise_installation_sync_status
    deliver_raw(enterprise_license_sync_data, status: 200)
  end
end
