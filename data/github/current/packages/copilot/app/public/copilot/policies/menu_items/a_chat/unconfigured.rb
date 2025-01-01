# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module AChat
        class Unconfigured < Copilot::Policies::MenuItems::AChat::Base
          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            !a_chat_enabled? && !a_chat_disabled?
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
