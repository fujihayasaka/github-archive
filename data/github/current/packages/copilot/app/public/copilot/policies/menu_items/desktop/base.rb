# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module Desktop
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :desktop_unconfigured?,
            :desktop_disabled?,
            :desktop_enabled?,
            :desktop_no_policy?,
            to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "desktop"
          end
        end
      end
    end
  end
end
