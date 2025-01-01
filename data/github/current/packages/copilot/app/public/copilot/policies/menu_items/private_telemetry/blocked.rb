# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module PrivateTelemetry
        class Blocked < Copilot::Policies::MenuItems::PrivateTelemetry::Base
          DESCRIPTION = "GitHub Copilot won’t collect data from developers' prompts and returned suggestions for custom model training."

          private

          sig { override.returns(T::Boolean) }
          def checked?
            private_telemetry_disabled?
          end

          sig { override.returns(String) }
          def description
            DESCRIPTION
          end

          sig { override.returns(String) }
          def text
            "Disabled"
          end
        end
      end
    end
  end
end
