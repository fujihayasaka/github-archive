# typed: true
# frozen_string_literal: true

# Stats are primarily for use with Enterprise Server and all data is already collected for dotcom.
class Api::Enterprise::Stats::SecurityProducts < Api::Enterprise::App
  before do
    deliver_error! 404 unless GitHub.enterprise?
  end

  get "/enterprise/stats/security-products", operation_id: "enterprise-admin/get-security-products" do
    unless trusted_port?
      control_access :enterprise,
        allow_integrations: false,
        allow_user_via_granular_actor: false,
        disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed
    end

    deliver_raw GitHub::Stats::Site.security_products_stats
  end
end
