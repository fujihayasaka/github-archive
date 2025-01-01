# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module OF
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :o_f_enabled?, :o_f_disabled?, :o_f_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_o_f"
          end
        end
      end
    end
  end
end
