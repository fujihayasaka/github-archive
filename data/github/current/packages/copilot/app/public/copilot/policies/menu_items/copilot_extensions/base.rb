# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module CopilotExtensions
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :copilot_extensions_unconfigured?, :copilot_extensions_disabled?, :copilot_extensions_enabled?,
                   :copilot_extensions_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_extensions"
          end
        end
      end
    end
  end
end
