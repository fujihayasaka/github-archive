# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module AutomaticCodeReview
        class Base < Copilot::Policies::MenuItems::Base
          abstract!

          private

          delegate :automatic_code_review_enabled?, :automatic_code_review_disabled?, :automatic_code_review_no_policy?, to: :copilot_configurable

          sig { override.returns(String) }
          def name
            "automatic_code_review"
          end
        end
      end
    end
  end
end
