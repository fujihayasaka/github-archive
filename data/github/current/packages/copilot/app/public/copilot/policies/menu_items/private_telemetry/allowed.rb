# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module PrivateTelemetry
        class Allowed < Copilot::Policies::MenuItems::PrivateTelemetry::Base
          DESCRIPTION = "GitHub Copilot will securely collect data from developers' prompts and returned suggestions for custom model training."

          private

          sig { override.returns(T::Boolean) }
          def checked?
            private_telemetry_enabled?
          end

          sig { override.returns(String) }
          def description
            DESCRIPTION
          end

          sig { override.returns(String) }
          def text
            "Enabled"
          end
        end
      end
    end
  end
end
