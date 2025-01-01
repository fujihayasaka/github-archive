# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module PublicCodeSuggestions
        class NoPolicy < Copilot::Policies::MenuItems::PublicCodeSuggestions::Base
          DESCRIPTION = "Each of your organizations will be able to set their own policy."

          private

          sig { override.returns(T::Boolean) }
          def checked?
            return false if standalone_business?
            no_public_code_suggestions_policy?
          end

          sig { override.returns(String) }
          def description
            "Each of your organizations will be able to set their own policy."
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
