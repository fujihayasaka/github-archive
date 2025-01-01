# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module CustomModels
        class Disabled < Copilot::Policies::MenuItems::CustomModels::Base
          BUSINESS_DESCRIPTION = "Organizations won’t have access to the feature"

          private

          sig { override.returns(T::Boolean) }
          def checked?
            custom_models_disabled?
          end

          sig { override.returns(String) }
          def description
            BUSINESS_DESCRIPTION
          end
        end
      end
    end
  end
end
