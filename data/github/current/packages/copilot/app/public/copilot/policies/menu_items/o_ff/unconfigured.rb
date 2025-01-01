# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module OFf
        class Unconfigured < Copilot::Policies::MenuItems::OFf::Base
          private

          sig { override.returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            !o_ff_enabled? && !o_ff_disabled?
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
