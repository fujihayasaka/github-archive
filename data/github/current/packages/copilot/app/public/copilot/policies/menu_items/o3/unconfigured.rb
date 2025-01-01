# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module O3
        class Unconfigured < Copilot::Policies::MenuItems::O3::Base
          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            !o3_enabled? && !o3_disabled?
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
