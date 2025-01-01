# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module Overages
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :overages_enabled?, :overages_disabled?, :overages_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_overages"
          end
        end
      end
    end
  end
end
