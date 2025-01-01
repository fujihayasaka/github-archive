# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module O1
        class Unconfigured < Copilot::Policies::MenuItems::O1::Base
          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            !o1_enabled? && !o1_disabled?
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
