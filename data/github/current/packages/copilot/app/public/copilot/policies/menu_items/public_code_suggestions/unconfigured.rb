# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module PublicCodeSuggestions
        class Unconfigured < Copilot::Policies::MenuItems::PublicCodeSuggestions::Base
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
            !allow_public_code_suggestions? && !block_public_code_suggestions?
          end
        end
      end
    end
  end
end
