# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module MobileChat
        class Unconfigured < Copilot::Policies::MenuItems::MobileChat::Base
          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            !mobile_chat_enabled? && !mobile_chat_disabled?
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
