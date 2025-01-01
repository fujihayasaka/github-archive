# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module AgentMode
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :agent_mode_enabled?, :agent_mode_disabled?, :agent_mode_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_agent_mode"
          end
        end
      end
    end
  end
end
