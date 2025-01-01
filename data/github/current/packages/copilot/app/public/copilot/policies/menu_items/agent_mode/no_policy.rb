# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module AgentMode
        class NoPolicy < Copilot::Policies::MenuItems::AgentMode::Base
          DESCRIPTION = "Each of your organizations will be able to set their own policy."

          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            agent_mode_no_policy?
          end

          sig { override.returns(String) }
          def description
            DESCRIPTION
          end

          sig { override.returns(T::Boolean) }
          def render?
            business? && !standalone_business?
          end
        end
      end
    end
  end
end
