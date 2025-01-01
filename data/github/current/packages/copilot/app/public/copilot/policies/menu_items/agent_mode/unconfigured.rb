# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module AgentMode
        class Unconfigured < Copilot::Policies::MenuItems::AgentMode::Base
          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            !agent_mode_enabled? && !agent_mode_disabled?
          end

          sig { override.returns(String) }
          def type
            "button"
          end

          sig { override.returns(T::Boolean) }
          def render?
            false
          end
        end
      end
    end
  end
end
