# typed: true
# frozen_string_literal: true

class Api::EnterpriseLicensing < Api::Enterprise::App
  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  get "/enterprises/:enterprise_id/consumed-licenses", operation_id: "enterprise-admin/get-consumed-licenses" do
    enterprise = find_enterprise!

    control_access :read_licensing,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      resource: enterprise

    enterprise_consumed_licenses = Business::LicenseAttributer.new(enterprise).license_usage_hash(pagination: true, page: pagination[:page], per_page: pagination[:per_page])
    unless enterprise_consumed_licenses[:users].nil?
      paginator.collection_size = enterprise_consumed_licenses[:total_seats_consumed]
    end
    deliver_raw(enterprise_consumed_licenses, status: 200)
  end
end
