# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module Insights
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :insights_enabled?, :insights_disabled?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_insights"
          end
        end
      end
    end
  end
end
