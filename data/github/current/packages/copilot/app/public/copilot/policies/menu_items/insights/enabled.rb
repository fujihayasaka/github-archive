# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module Insights
        class Enabled < Copilot::Policies::MenuItems::Insights::Base
          DESCRIPTION = "All organizations, enterprises, and their admins and authorized users have access to this feature. Billing managers also have access at the enterprise level. It cannot be disabled at the organization level."

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            insights_enabled?
          end

          sig { returns(String) }
          def label
            "Enabled everywhere"
          end

          sig { override.returns(String) }
          def description
            DESCRIPTION
          end
        end
      end
    end
  end
end
