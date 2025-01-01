# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    module Ai
      class SidebarComponent < ApplicationComponent
        extend T::Sig

        sig { returns(String) }
        def submit_button_text
          "Generate suggestions"
        end

        sig { params(index: Integer).returns(String) }
        def generated_expression_id(index)
          "generated-expression-#{index}"
        end
      end
    end
  end
end
