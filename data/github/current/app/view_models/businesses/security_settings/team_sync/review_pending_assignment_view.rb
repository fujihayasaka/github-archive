# typed: true
# frozen_string_literal: true

module Businesses
  module SecuritySettings
    module TeamSync
      class ReviewPendingAssignmentView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
        attr_reader :tenant_name, :business_name, :business, :team_sync_setup_flow

        delegate :provider_label, to: :tenant

        def team_sync_provider_id
          team_sync_setup_flow.provider_id
        end

        private

        def tenant
          team_sync_setup_flow.tenant
        end
      end
    end
  end
end
