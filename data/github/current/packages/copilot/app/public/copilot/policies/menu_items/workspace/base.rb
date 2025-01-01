# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module Workspace
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :workspace_for_emu_enabled?, :workspace_for_emu_disabled?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_workspace_for_emu"
          end
        end
      end
    end
  end
end
