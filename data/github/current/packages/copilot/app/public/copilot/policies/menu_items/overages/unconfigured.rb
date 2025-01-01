# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module Overages
        class Unconfigured < Copilot::Policies::MenuItems::Overages::Base
          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            !overages_enabled? && !overages_disabled?
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
