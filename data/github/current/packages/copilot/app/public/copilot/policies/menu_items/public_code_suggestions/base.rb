# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module PublicCodeSuggestions
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :allow_public_code_suggestions?, :block_public_code_suggestions?,
                   :no_public_code_suggestions_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_public_code_suggestions"
          end
        end
      end
    end
  end
end
