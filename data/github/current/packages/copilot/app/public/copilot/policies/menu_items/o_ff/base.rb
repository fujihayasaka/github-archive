# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module OFf
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :o_ff_enabled?, :o_ff_disabled?, :o_ff_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_o_ff"
          end
        end
      end
    end
  end
end
