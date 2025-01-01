# typed: strict
# frozen_string_literal: true

module Sponsors
  module BulkSponsorshipImports
    module Errors
      class LoginMissingComponent < ApplicationComponent
        include Sponsors::BulkSponsorshipImports::Errors::ViewComponentMethods

        private

        sig { override.returns(String) }
        def test_selector
          "login-missing-error"
        end

        sig { override.returns(String) }
        def error_message
          "Some of the rows in your CSV file are missing the maintainer username. Please add the username " \
            "for each row and try again."
        end
      end
    end
  end
end
