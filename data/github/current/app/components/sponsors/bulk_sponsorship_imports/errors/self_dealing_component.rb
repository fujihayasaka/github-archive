# typed: strict
# frozen_string_literal: true

module Sponsors
  module BulkSponsorshipImports
    module Errors
      class SelfDealingComponent < ApplicationComponent
        include Sponsors::BulkSponsorshipImports::Errors::ViewComponentMethods

        private

        sig { override.returns(String) }
        def test_selector
          "self-dealing-error"
        end

        sig { override.returns(String) }
        def error_message
          "You cannot sponsor yourself. Please remove @#{sponsor}."
        end
      end
    end
  end
end
