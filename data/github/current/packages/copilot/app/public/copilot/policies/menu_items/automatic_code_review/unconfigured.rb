# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module AutomaticCodeReview
        class Unconfigured < Copilot::Policies::MenuItems::AutomaticCodeReview::Base
          private

          sig { override.returns(T::Boolean) }
          def checked?
            !automatic_code_review_enabled? && !automatic_code_review_disabled?
          end

          sig { override.returns(String) }
          def type
            "button"
          end

          sig { override.returns(T::Boolean) }
          def render?
            false
          end
        end
      end
    end
  end
end
