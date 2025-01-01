# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module OF
        class Unconfigured < Copilot::Policies::MenuItems::OF::Base
          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            !o_f_enabled? && !o_f_disabled?
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
