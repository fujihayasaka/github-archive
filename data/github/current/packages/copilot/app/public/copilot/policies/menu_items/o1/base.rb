# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module O1
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :o1_enabled?, :o1_disabled?, :o1_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_o1"
          end
        end
      end
    end
  end
end
