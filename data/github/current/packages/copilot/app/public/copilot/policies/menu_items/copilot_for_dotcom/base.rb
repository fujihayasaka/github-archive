# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module CopilotForDotcom
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :copilot_for_dotcom_enabled?, :copilot_for_dotcom_disabled?, :copilot_for_dotcom_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_for_dotcom"
          end
        end
      end
    end
  end
end
