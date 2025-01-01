# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module O3
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :o3_enabled?, :o3_disabled?, :o3_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_o3"
          end
        end
      end
    end
  end
end
