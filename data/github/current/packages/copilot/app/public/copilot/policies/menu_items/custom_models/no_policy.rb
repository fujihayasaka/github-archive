# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module CustomModels
        class NoPolicy < Copilot::Policies::MenuItems::CustomModels::Base
          DESCRIPTION = "Each of your organizations will be able to set their own policy."

          private

          sig { override.returns(T::Boolean) }
          def checked?
            custom_models_no_policy?
          end

          sig { override.returns(String) }
          def description
            DESCRIPTION
          end

          sig { override.returns(T::Boolean) }
          def render?
            business?
          end
        end
      end
    end
  end
end
