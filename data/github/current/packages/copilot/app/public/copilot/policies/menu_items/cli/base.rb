# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module Cli
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :cli_unconfigured?, :cli_disabled?, :cli_enabled?, :cli_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "cli"
          end
        end
      end
    end
  end
end
