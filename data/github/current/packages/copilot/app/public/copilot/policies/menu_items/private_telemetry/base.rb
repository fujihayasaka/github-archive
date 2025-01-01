# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module PrivateTelemetry
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :private_telemetry_unconfigured?, :private_telemetry_disabled?, :private_telemetry_enabled?,
                   :private_telemetry_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "private_telemetry"
          end
        end
      end
    end
  end
end
