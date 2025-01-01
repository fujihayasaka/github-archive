# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module CustomModels
        class Enabled < Copilot::Policies::MenuItems::CustomModels::Base
          BUSINESS_DESCRIPTION = "All organizations will have access to the feature"

          private

          sig { override.returns(T::Boolean) }
          def checked?
            custom_models_enabled?
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
