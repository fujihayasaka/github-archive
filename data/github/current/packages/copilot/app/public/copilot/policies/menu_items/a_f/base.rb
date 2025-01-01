# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module AF
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :a_f_enabled?, :a_f_disabled?, :a_f_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_a_f"
          end
        end
      end
    end
  end
end
