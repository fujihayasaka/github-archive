# typed: true
# frozen_string_literal: true

module Businesses
  module SecuritySettings
    module TeamSync
      class InitiateSetupView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
        attr_reader :business, :tenant, :token

        delegate :provider_label, to: :tenant

        def share_link
          urls.team_sync_setup_enterprise_url(business, params: { token: token }, host: GitHub.host_name)
        end
      end
    end
  end
end
