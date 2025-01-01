# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module Workspace
        class Disabled < Copilot::Policies::MenuItems::Workspace::Base
          DESCRIPTION = "All organizations won’t have access to the feature"

          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            workspace_for_emu_disabled?
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
