# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module Workspace
        class Enabled < Copilot::Policies::MenuItems::Workspace::Base
          DESCRIPTION = "All organizations will have access to the feature"

          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            workspace_for_emu_enabled?
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
