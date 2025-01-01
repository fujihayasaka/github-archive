# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module CustomModels
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :custom_models_enabled?, :custom_models_disabled?, :custom_models_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "copilot_custom_models"
          end
        end
      end
    end
  end
end
