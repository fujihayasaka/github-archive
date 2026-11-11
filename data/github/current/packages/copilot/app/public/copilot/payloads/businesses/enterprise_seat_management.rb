# typed: strict
# frozen_string_literal: true

module Copilot
  module Payloads
    module Businesses
      class EnterpriseSeatManagement < Copilot::Payloads::Businesses::SeatManagement
        sig { override.returns(String) }
        def route_id
          "copilotForBusinessStandaloneSeatManagementEnterpriseRoute"
        end
      end
    end
  end
end
