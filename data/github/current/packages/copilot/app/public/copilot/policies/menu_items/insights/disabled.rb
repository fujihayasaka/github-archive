# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module Insights
        class Disabled < Copilot::Policies::MenuItems::Insights::Base
          DESCRIPTION = "All organizations, enterprises, and their admins, billing managers, and authorized users will not have access to this feature. It cannot be enabled at the organization level."

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            insights_disabled?
          end

          sig { returns(String) }
          def label
            "Disabled everywhere"
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
