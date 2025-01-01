# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module Cli
        class Unconfigured < Copilot::Policies::MenuItems::Cli::Base
          private

          sig { override.returns(T::Boolean) }
          def checked?
            true
          end

          sig { override.returns(String) }
          def type
            "button"
          end

          sig { override.returns(T::Boolean) }
          def render?
            return false if business?
            cli_unconfigured? || cli_no_policy?
          end
        end
      end
    end
  end
end
