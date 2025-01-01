# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module MobileChat
        class NoPolicy < Copilot::Policies::MenuItems::MobileChat::Base
          DESCRIPTION = "Each of your organizations will be able to set their own policy."

          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            no_mobile_chat_policy?
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
