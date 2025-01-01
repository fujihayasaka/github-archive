# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module PrivateTelemetry
        class NoPolicy < Copilot::Policies::MenuItems::PrivateTelemetry::Base
          DESCRIPTION = "Each of your organizations will be able to set their own policy for this feature."

          private

          sig { override.returns(T::Boolean) }
          def checked?
            private_telemetry_no_policy?
          end

          sig { override.returns(String) }
          def description
            DESCRIPTION
          end

          sig { override.returns(T::Boolean) }
          def render?
            business?
          end
        end
      end
    end
  end
end
